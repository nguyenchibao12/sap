*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_DELETE
*& ADK Delete — Archive Object Z_ARCH_EKK
*& Default: READ_OBJECT + ARCHIVE_GET_TABLE (matches Z_ARCH_EKK_WRITE PUT_TABLE)
*& ARCHIVE_GET_INFORMATION: metadata + USED_CLASSES (structure list in file)
*& Legacy: P_JSON = X → ty_arch_rec + ARCHIVE_GET_NEXT_RECORD (old WRITE_RECORD dumps)
*& DELETE (tab) FROM TABLE <itab> — key match per SAP rules; then ARCHIVE_DELETE_RECORD
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_delete.

INCLUDE z_gsp18_arch_dyn.

TYPES: BEGIN OF ty_arch_rec,
         rec_type   TYPE c LENGTH 1,
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_arch_rec.

TYPES: BEGIN OF ty_del_agg,
         table_name TYPE tabname,
         cnt        TYPE i,
       END OF ty_del_agg.

DATA: ls_arec      TYPE ty_arch_rec,
      lv_cnt       TYPE i VALUE 0,
      lv_err       TYPE i VALUE 0,
      lt_del_agg   TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name,
      lv_arch_h    TYPE syst-tabix,
      lv_obj       TYPE arch_obj-object VALUE 'Z_ARCH_EKK',
      lv_arch_name TYPE heada-arkey,
      lv_doc       TYPE admi_run-document,
      gr_dyn       TYPE REF TO data.

PARAMETERS: p_table TYPE tabname DEFAULT 'ZSP26_EKKO'.
PARAMETERS: p_test  TYPE c AS CHECKBOX DEFAULT 'X'.
PARAMETERS: p_json  TYPE c AS CHECKBOX DEFAULT ' '.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  WRITE: / '=== ADK Delete: Z_ARCH_EKK ===' && ' p_table=' && p_table && ' p_json=' && p_json && ' ==='.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no DB delete ***'. ENDIF.
  WRITE: /.

  IF p_json = 'X'.
    PERFORM run_delete_legacy_json.
    EXIT.
  ENDIF.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    IMPORTING
      archive_handle = lv_arch_h
    EXCEPTIONS
      file_already_open     = 1
      file_io_error         = 2
      internal_error        = 3
      no_files_available    = 4
      object_not_found      = 5
      open_error            = 6
      not_authorized        = 7
      archiving_standard_violation = 8
      OTHERS                = 9.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive for delete. Run via SARA with a selected file.' TYPE 'A'.
  ENDIF.

  " USED_CLASSES: list of DDIC names (often same shape as ARCH_DDIC-NAME)
  DATA: lt_used TYPE TABLE OF arch_ddic,
        ls_used TYPE arch_ddic.

  CALL FUNCTION 'ARCHIVE_GET_INFORMATION'
    EXPORTING
      archive_handle = lv_arch_h
    IMPORTING
      archive_name     = lv_arch_name
      object           = lv_obj
      archive_document = lv_doc
    TABLES
      used_classes     = lt_used
    EXCEPTIONS
      internal_error          = 1
      wrong_access_to_archive = 2
      OTHERS                  = 3.

  WRITE: / 'GET_INFORMATION: obj ' && lv_obj && ' arch ' && lv_arch_name && ' doc ' && lv_doc && ' rc ' && sy-subrc.
  LOOP AT lt_used INTO ls_used.
    WRITE: / |  REGISTERED_DDIC_NAME: { ls_used-name }|.
  ENDLOOP.
  WRITE: /.

  DATA: lv_tab_try TYPE tabname,
        lv_got     TYPE abap_bool.

  WHILE abap_true.
    CALL FUNCTION 'ARCHIVE_READ_OBJECT'
      EXPORTING
        archive_handle = lv_arch_h
        object         = lv_obj
      EXCEPTIONS
        no_record_found           = 1
        file_io_error           = 2
        internal_error          = 3
        open_error              = 4
        cancelled_by_user       = 5
        object_not_found        = 6
        filename_creation_failure = 7
        file_already_open       = 8
        not_authorized          = 9
        file_not_found          = 10
        OTHERS                  = 11.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.

    CLEAR lv_got.

    " Prefer P_TABLE; else try each DDIC name from GET_INFORMATION rows (ARCH_DDIC / class list)
    IF p_table IS NOT INITIAL.
      PERFORM process_one_arch_table
        USING    lv_arch_h p_table p_test
        CHANGING lv_cnt lv_err lt_del_agg lv_got.
    ENDIF.

    IF lv_got = abap_false.
      LOOP AT lt_used INTO ls_used.
        lv_tab_try = ls_used-name.
        CHECK lv_tab_try IS NOT INITIAL.
        PERFORM process_one_arch_table
          USING    lv_arch_h lv_tab_try p_test
          CHANGING lv_cnt lv_err lt_del_agg lv_got.
        IF lv_got = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_got = abap_false.
      SELECT table_name FROM zsp26_arch_cfg INTO TABLE @DATA(lt_cfg_tabs)
        WHERE is_active = 'X'.
      LOOP AT lt_cfg_tabs INTO DATA(ls_ct).
        PERFORM process_one_arch_table
          USING    lv_arch_h ls_ct-table_name p_test
          CHANGING lv_cnt lv_err lt_del_agg lv_got.
        IF lv_got = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_got = abap_false.
      WRITE: / 'WARN: Could not ARCHIVE_GET_TABLE for this object (set P_TABLE or check registration).'.
      lv_err = lv_err + 1.
    ENDIF.
  ENDWHILE.

  CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
    EXCEPTIONS
      OTHERS = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_agg lv_err.
  ENDIF.

  WRITE: /.
  WRITE: / '=== Summary: processed ' && lv_cnt && ' errors ' && lv_err && ' ==='.
  IF p_test = 'X'. WRITE: / 'Uncheck Test Mode to delete DB rows + log.'. ENDIF.

*&---------------------------------------------------------------------*
FORM process_one_arch_table
  USING    VALUE(pv_handle) TYPE syst-tabix
           VALUE(pv_tab)    TYPE tabname
           VALUE(pv_test)   TYPE c
  CHANGING cv_cnt TYPE i
           cv_err TYPE i
           ct_agg TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name
           cv_got TYPE abap_bool.

  FIELD-SYMBOLS: <lt> TYPE ANY TABLE.

  cv_got = abap_false.
  TRY.
      CREATE DATA gr_dyn TYPE TABLE OF (pv_tab).
    CATCH cx_sy_create_data_error.
      RETURN.
  ENDTRY.
  ASSIGN gr_dyn->* TO <lt>.
  REFRESH <lt>.

  CALL FUNCTION 'ARCHIVE_GET_TABLE'
    EXPORTING
      archive_handle           = pv_handle
      record_structure         = pv_tab
      all_records_of_object    = 'X'
    TABLES
      table                    = <lt>
    EXCEPTIONS
      end_of_object            = 1
      internal_error           = 2
      wrong_access_to_archive  = 3
      OTHERS                   = 4.

  IF sy-subrc <> 0 OR <lt> IS INITIAL.
    RETURN.
  ENDIF.

  cv_got = abap_true.

  IF pv_test = ' '.
    DELETE (pv_tab) FROM TABLE <lt>.
    IF sy-subrc = 0 OR sy-subrc = 4.
      DATA(lv_lines) = lines( <lt> ).
      cv_cnt = cv_cnt + lv_lines.
      PERFORM del_agg_add USING ct_agg pv_tab lv_lines.
      DO lv_lines TIMES.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD'
          EXCEPTIONS OTHERS = 1.
      ENDDO.
    ELSE.
      cv_err = cv_err + 1.
      WRITE: / |  ERR: DB delete failed, tab { pv_tab }, rc { sy-subrc }|.
    ENDIF.
  ELSE.
    DATA(lv_t) = lines( <lt> ).
    cv_cnt = cv_cnt + lv_t.
    WRITE: / |  [TEST] Would delete { lv_t } rows, tab { pv_tab }|.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM del_agg_add
  USING    ct_agg TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name
           VALUE(pv_tab) TYPE tabname
           VALUE(pv_n) TYPE i.

  FIELD-SYMBOLS: <dg> LIKE LINE OF ct_agg.
  READ TABLE ct_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + pv_n.
  ELSE.
    DATA(ls) TYPE ty_del_agg.
    ls-table_name = pv_tab.
    ls-cnt        = pv_n.
    INSERT ls INTO TABLE ct_agg.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM flush_arch_log_delete
  USING    ct_agg TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name
           VALUE(pv_err) TYPE i.

  DATA: ls_log TYPE zsp26_arch_log,
        ls_a   TYPE ty_del_agg,
        lv_ts  TYPE timestampl.
  GET TIME STAMP FIELD lv_ts.

  IF lines( ct_agg ) > 0.
    LOOP AT ct_agg INTO ls_a.
      CLEAR ls_log.
      TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error. ENDTRY.
      ls_log-table_name = ls_a-table_name.
      ls_log-action     = 'DELETE'.
      ls_log-rec_count  = ls_a-cnt.
      ls_log-status     = COND #( WHEN pv_err = 0 THEN 'S' ELSE 'W' ).
      ls_log-start_time = lv_ts.
      ls_log-end_time   = lv_ts.
      ls_log-exec_user  = sy-uname.
      ls_log-exec_date  = sy-datum.
      ls_log-message    = 'ADK DELETE (GET_TABLE): ' && ls_a-cnt && ' rows, tab ' && ls_a-table_name && '. err ' && pv_err.
      INSERT zsp26_arch_log FROM ls_log.
    ENDLOOP.
  ELSEIF pv_err > 0.
    CLEAR ls_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-table_name = 'Z_ARCH_EKK'.
    ls_log-action     = 'DELETE'.
    ls_log-rec_count  = 0.
    ls_log-status     = 'W'.
    ls_log-start_time = lv_ts.
    ls_log-end_time   = lv_ts.
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    ls_log-message    = 'ADK DELETE: errors ' && pv_err && ' (no row aggregates).'.
    INSERT zsp26_arch_log FROM ls_log.
  ENDIF.
  COMMIT WORK.
ENDFORM.

*&---------------------------------------------------------------------*
FORM run_delete_legacy_json.
  DATA: ls_arec_loc   TYPE ty_arch_rec,
        lv_where_loc  TYPE string,
        lv_cnt_loc    TYPE i VALUE 0,
        lv_err_loc    TYPE i VALUE 0,
        lt_pairs_loc  TYPE TABLE OF string,
        lv_pair_loc   TYPE string,
        lv_kf_loc     TYPE string,
        lv_kv_loc     TYPE string,
        lt_del_loc    TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name,
        ls_del_loc    TYPE ty_del_agg.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive for delete (legacy).' TYPE 'A'.
  ENDIF.

  DO.
    CLEAR ls_arec_loc.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
      IMPORTING  record      = ls_arec_loc
      EXCEPTIONS end_of_file = 1
                 OTHERS      = 2.
    IF sy-subrc = 1. EXIT.
    ELSEIF sy-subrc > 1.
      ADD 1 TO lv_err_loc.
      CONTINUE.
    ENDIF.

    CHECK ls_arec_loc-rec_type = 'D'.

    CLEAR: lv_where_loc, lv_pair_loc, lv_kf_loc, lv_kv_loc.
    REFRESH lt_pairs_loc.
    SPLIT ls_arec_loc-key_vals AT '|' INTO TABLE lt_pairs_loc.
    LOOP AT lt_pairs_loc INTO lv_pair_loc.
      SPLIT lv_pair_loc AT '=' INTO lv_kf_loc lv_kv_loc.
      IF lv_where_loc IS NOT INITIAL. lv_where_loc &&= ' AND '. ENDIF.
      lv_where_loc &&= lv_kf_loc && ` EQ '` && lv_kv_loc && `'`.
    ENDLOOP.
    lv_where_loc = |MANDT EQ '{ sy-mandt }' AND | && lv_where_loc.

    WRITE: / |  LEGACY { ls_arec_loc-table_name } / { ls_arec_loc-key_vals }|.

    IF p_test = ' '.
      DELETE FROM (ls_arec_loc-table_name) WHERE (lv_where_loc).
      IF sy-subrc = 0.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD' EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt_loc.
        PERFORM del_agg_bump_legacy USING lt_del_loc ls_arec_loc-table_name.
      ELSEIF sy-subrc = 4.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD' EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt_loc.
        PERFORM del_agg_bump_legacy USING lt_del_loc ls_arec_loc-table_name.
        WRITE: / |    INFO: already deleted|.
      ELSE.
        ADD 1 TO lv_err_loc.
      ENDIF.
    ELSE.
      ADD 1 TO lv_cnt_loc.
    ENDIF.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
    EXCEPTIONS
      OTHERS = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_loc lv_err_loc.
  ENDIF.

  WRITE: / |=== Legacy JSON summary: { lv_cnt_loc } / err { lv_err_loc } ===|.
ENDFORM.

*&---------------------------------------------------------------------*
FORM del_agg_bump_legacy
  USING    ct_agg TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name
           VALUE(pv_tab) TYPE tabname.

  FIELD-SYMBOLS: <dg> LIKE LINE OF ct_agg.
  READ TABLE ct_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + 1.
  ELSE.
    DATA(ls) TYPE ty_del_agg.
    ls-table_name = pv_tab.
    ls-cnt        = 1.
    INSERT ls INTO TABLE ct_agg.
  ENDIF.
ENDFORM.
