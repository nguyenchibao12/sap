*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_DELETE
*& ADK Delete — Archive Object Z_ARCH_EKK
*& READ_OBJECT + GET_TABLE; if READ_OBJECT EOF on 1st call → GET_NEXT_OBJECT + GET_TABLE (file handle)
*& ARCHIVE_GET_INFORMATION: metadata + USED_CLASSES (structure list in file)
*& Legacy: P_JSON = X → ty_arch_rec + ARCHIVE_GET_NEXT_RECORD (old WRITE_RECORD dumps)
*& After DB delete: ARCHIVE_DELETE_RECORD (ECC) or ARCHIVE_DELETE_OBJECT_DATA (some S/4)
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
TYPES ty_del_agg_htab TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name.

DATA: ls_arec      TYPE ty_arch_rec,
      lv_cnt       TYPE i VALUE 0,
      lv_err       TYPE i VALUE 0,
      lt_del_agg   TYPE ty_del_agg_htab,
      lv_arch_h    TYPE syst-tabix,
      lv_obj       TYPE arch_obj-object VALUE 'Z_ARCH_EKK',
      lv_arch_name TYPE heada-arkey,
      lv_doc       TYPE admi_run-document,
      gr_dyn       TYPE REF TO data,
      lt_cfg_tabs  TYPE TABLE OF tabname,
      lv_cfg_tab   TYPE tabname,
      ls_hub_admi  TYPE admi_run,
      lv_open_obj  TYPE arch_obj-object,
      lv_arch_key  TYPE admi_files-archiv_key,
      gv_del_doc_log TYPE admi_run-document,
      lv_use_p_table TYPE abap_bool VALUE abap_true,
      lv_prev_del_like TYPE string,
      lv_prev_del_cnt  TYPE i,
      lv_dbcnt         TYPE i.

PARAMETERS: p_table TYPE tabname DEFAULT 'ZSP26_EKKO'.
PARAMETERS: p_test  TYPE c AS CHECKBOX DEFAULT 'X'.
PARAMETERS: p_json  TYPE c AS CHECKBOX DEFAULT ' '.
PARAMETERS: p_doc   TYPE admi_run-document.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  DATA lv_hub_tab TYPE tabname.
  IMPORT arch_tabname = lv_hub_tab FROM MEMORY ID 'Z_GSP18_ARCH_TAB'.
  IF sy-subrc = 0.
    IF p_table IS INITIAL AND lv_hub_tab IS NOT INITIAL.
      p_table = lv_hub_tab.
    ENDIF.
    FREE MEMORY ID 'Z_GSP18_ARCH_TAB'.
  ENDIF.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
*----------------------------------------------------------------------*
  PERFORM f4_arch_cfg_table CHANGING p_table.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  CONDENSE p_table.
  TRANSLATE p_table TO UPPER CASE.

  WRITE: / |=== Archive delete: table { p_table } ===|.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — database rows are not removed ***'. ENDIF.
  WRITE: /.

  CLEAR: ls_hub_admi, lv_arch_key.
  lv_open_obj = lv_obj.
  CLEAR gv_del_doc_log.

  IF p_doc IS NOT INITIAL.
    ls_hub_admi-object   = lv_obj.
    ls_hub_admi-document = p_doc.
  ELSE.
    IMPORT del_admi = ls_hub_admi FROM MEMORY ID 'Z_GSP18_ADMI_DEL'.
  ENDIF.
  IF ls_hub_admi-document IS NOT INITIAL.
    lv_use_p_table = abap_false.
    gv_del_doc_log = ls_hub_admi-document.
    DATA: lt_af_dd   TYPE TABLE OF dfies,
          ls_af_dd   TYPE dfies,
          lv_where_af TYPE string,
          lv_col_obj  TYPE fieldname,
          lv_col_doc  TYPE fieldname,
          lv_col_cli  TYPE fieldname.

    WRITE: / |Session { ls_hub_admi-document } (archive object { ls_hub_admi-object })|.
    lv_open_obj = ls_hub_admi-object.

    CLEAR lt_af_dd.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING
        tabname   = 'ADMI_FILES'
      TABLES
        dfies_tab = lt_af_dd
      EXCEPTIONS
        OTHERS    = 1.
    IF sy-subrc <> 0 OR lt_af_dd IS INITIAL.
      WRITE: / 'Error: could not read archive file metadata from the system.'.
      RETURN.
    ENDIF.

    CLEAR: lv_col_obj, lv_col_doc, lv_col_cli.

    READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'OBJECT'.
    IF sy-subrc = 0.
      lv_col_obj = 'OBJECT'.
    ELSE.
      READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'AR_OBJECT'.
      IF sy-subrc = 0.
        lv_col_obj = 'AR_OBJECT'.
      ELSE.
        READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'ARCHIVE_OBJECT'.
        IF sy-subrc = 0.
          lv_col_obj = 'ARCHIVE_OBJECT'.
        ELSE.
          READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'ARCH_OBJECT'.
          IF sy-subrc = 0.
            lv_col_obj = 'ARCH_OBJECT'.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    " Prefer ARCH_DOCID because many systems store the session number in this column;
    " DOCUMENT may hold a different identifier and lead to wrong ARCHIV_KEY.
    READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'ARCH_DOCID'.
    IF sy-subrc = 0.
      lv_col_doc = 'ARCH_DOCID'.
    ELSE.
      READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOCUMENT'.
      IF sy-subrc = 0.
        lv_col_doc = 'DOCUMENT'.
      ELSE.
        READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOC_ID'.
        IF sy-subrc = 0.
          lv_col_doc = 'DOC_ID'.
        ELSE.
          READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOCID'.
          IF sy-subrc = 0.
            lv_col_doc = 'DOCID'.
          ELSE.
            READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOCUMENT_ID'.
            IF sy-subrc = 0.
              lv_col_doc = 'DOCUMENT_ID'.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'MANDT'.
    IF sy-subrc = 0.
      lv_col_cli = 'MANDT'.
    ELSE.
      READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'CLIENT'.
      IF sy-subrc = 0.
        lv_col_cli = 'CLIENT'.
      ENDIF.
    ENDIF.

    IF lv_col_doc IS INITIAL.
      WRITE: / 'Available archive index columns on this system:'.
      LOOP AT lt_af_dd INTO ls_af_dd.
        WRITE: / '  - ' && ls_af_dd-fieldname.
      ENDLOOP.
      MESSAGE 'ADMI_FILES structure on this system is non-standard (document column not found).' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DATA: lv_doc_esc TYPE string,
          lv_obj_esc TYPE string,
          lv_mandt_s TYPE string.
    lv_doc_esc = |{ ls_hub_admi-document }|.
    lv_obj_esc = |{ ls_hub_admi-object }|.
    lv_mandt_s = |{ sy-mandt }|.
    PERFORM zsp26_sql_escape_quote CHANGING lv_doc_esc.
    PERFORM zsp26_sql_escape_quote CHANGING lv_obj_esc.
    lv_where_af = |{ lv_col_doc } = '{ lv_doc_esc }'|.

    " Some systems have an object column, some do not
    IF lv_col_obj IS NOT INITIAL.
      lv_where_af = |{ lv_col_obj } = '{ lv_obj_esc }' AND | && lv_where_af.
    ENDIF.

    IF lv_col_cli IS NOT INITIAL.
      lv_where_af = |{ lv_col_cli } = '{ lv_mandt_s }' AND | && lv_where_af.
    ENDIF.

    SELECT SINGLE archiv_key
      FROM admi_files
      WHERE (lv_where_af)
      INTO @lv_arch_key.
    IF sy-subrc <> 0.
      " Soft fallback: some systems store document in a different format (ARCH_DOCID has suffix, or different preferred column).
      DATA: lt_af_scan TYPE TABLE OF admi_files,
            ls_af_scan TYPE admi_files,
            lv_doc_in  TYPE string,
            lv_doc_db  TYPE string,
            lv_ok_hit  TYPE abap_bool.
      FIELD-SYMBOLS: <fs_doc_any> TYPE any.

      lv_doc_in = ls_hub_admi-document.
      CONDENSE lv_doc_in.

      SELECT * FROM admi_files INTO TABLE @lt_af_scan UP TO 5000 ROWS.

      CLEAR lv_arch_key.
      lv_ok_hit = abap_false.
      LOOP AT lt_af_scan INTO ls_af_scan.
        CLEAR lv_doc_db.

        ASSIGN COMPONENT lv_col_doc OF STRUCTURE ls_af_scan TO <fs_doc_any>.
        IF sy-subrc = 0 AND <fs_doc_any> IS ASSIGNED.
          lv_doc_db = <fs_doc_any>.
          CONDENSE lv_doc_db.
        ENDIF.

        IF lv_doc_db IS INITIAL.
          ASSIGN COMPONENT 'DOCUMENT' OF STRUCTURE ls_af_scan TO <fs_doc_any>.
          IF sy-subrc = 0 AND <fs_doc_any> IS ASSIGNED.
            lv_doc_db = <fs_doc_any>.
            CONDENSE lv_doc_db.
          ENDIF.
        ENDIF.

        IF lv_doc_db IS INITIAL.
          ASSIGN COMPONENT 'ARCH_DOCID' OF STRUCTURE ls_af_scan TO <fs_doc_any>.
          IF sy-subrc = 0 AND <fs_doc_any> IS ASSIGNED.
            lv_doc_db = <fs_doc_any>.
            CONDENSE lv_doc_db.
          ENDIF.
        ENDIF.

        IF lv_doc_db IS INITIAL.
          CONTINUE.
        ENDIF.

        IF lv_doc_db = lv_doc_in OR lv_doc_db CS lv_doc_in OR lv_doc_in CS lv_doc_db.
          lv_arch_key = ls_af_scan-archiv_key.
          lv_ok_hit = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_ok_hit = abap_false OR lv_arch_key IS INITIAL.
        FREE MEMORY ID 'Z_GSP18_ADMI_DEL'.
        MESSAGE 'File key not found in ADMI_FILES for the selected session (OBJECT/DOCUMENT).' TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ENDIF.
    FREE MEMORY ID 'Z_GSP18_ADMI_DEL'.
  ENDIF.
  IF gv_del_doc_log IS INITIAL AND p_doc IS NOT INITIAL.
    gv_del_doc_log = p_doc.
  ENDIF.
  lv_obj = lv_open_obj.

  " Pre-check: warn if this session already has a DELETE log
  IF gv_del_doc_log IS NOT INITIAL AND p_test = ' '.
    lv_prev_del_like = |%DOC={ gv_del_doc_log }%|.
    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_prev_del_cnt
      WHERE action  = 'DELETE'
        AND status  = 'S'
        AND message LIKE @lv_prev_del_like.
    IF lv_prev_del_cnt > 0.
      WRITE: / |Notice: session { gv_del_doc_log } already logged { lv_prev_del_cnt } successful delete run(s).|.
      WRITE: / 'DB data may already have been deleted. If no rows are deleted this time, a warning will be logged.'.
      WRITE: /.
    ENDIF.
  ENDIF.

  WRITE: /.

  IF p_json = 'X'.
    PERFORM run_delete_legacy_json.
    EXIT.
  ENDIF.

  DATA lv_open_rc TYPE sy-subrc.

  IF lv_arch_key IS NOT INITIAL.
    WRITE: / |Archive file key: { lv_arch_key }|.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
      EXPORTING
        aindflag     = space
        object       = lv_open_obj
        archive_name = lv_arch_key
        test_mode    = p_test
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
    lv_open_rc = sy-subrc.
  ELSE.
    WRITE: / 'No file key in the index; opening archive by object only.'.
    lv_open_rc = 4.
  ENDIF.

  IF lv_open_rc <> 0.
    WRITE: / |Open by file key failed (code { lv_open_rc }); retrying by object.|.
    " Fallback: open by object when key/session mapping differs on this system.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
      EXPORTING
        aindflag     = space
        object       = lv_open_obj
        test_mode    = p_test
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
    lv_open_rc = sy-subrc.
  ENDIF.

  IF lv_open_rc <> 0.
    WRITE: / |Could not open archive for delete (code { lv_open_rc }).|.
    CASE lv_open_rc.
      WHEN 4.
        MESSAGE 'Cannot open archive for delete (no matching files).' TYPE 'S' DISPLAY LIKE 'E'.
      WHEN 5.
        MESSAGE 'Archive object (AOBJ) not found or not registered.' TYPE 'S' DISPLAY LIKE 'E'.
      WHEN OTHERS.
        MESSAGE 'Cannot open archive for delete (check permissions, files, session).' TYPE 'S' DISPLAY LIKE 'E'.
    ENDCASE.
    RETURN.
  ENDIF.

  " USED_CLASSES: log what is inside the archive file (generic ZSTR_ARCH_REC vs legacy table line type)
  DATA: lt_used         TYPE adk_classes,
        ls_used_inf     LIKE LINE OF lt_used,
        lv_tab_try      TYPE tabname,
        lv_obj_h        TYPE syst-tabix,
        lv_ro_ix        TYPE i VALUE 0,
        lv_gno_fallback TYPE abap_bool VALUE abap_false,
        lv_gno_ix       TYPE i VALUE 0.

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

  IF sy-subrc <> 0.
    WRITE: / |Error: could not read archive contents (code { sy-subrc }).|.
    CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
      EXPORTING archive_handle = lv_arch_h
      EXCEPTIONS OTHERS         = 0.
    RETURN.
  ENDIF.
  WRITE: / |Archive: { lv_arch_name }; Session: { lv_doc }; Object: { lv_obj }|.
  IF gv_del_doc_log IS INITIAL AND lv_doc IS NOT INITIAL.
    gv_del_doc_log = lv_doc.
  ENDIF.
  LOOP AT lt_used INTO ls_used_inf.
    PERFORM adk_used_row_to_tabname USING ls_used_inf CHANGING lv_tab_try.
    WRITE: / |  Contains table type: { lv_tab_try }|.
  ENDLOOP.
  WRITE: /.

  DO.
    CLEAR lv_obj_h.
    ADD 1 TO lv_ro_ix.
    CALL FUNCTION 'ARCHIVE_READ_OBJECT'
      EXPORTING
        object = lv_obj
      IMPORTING
        archive_handle = lv_obj_h
      EXCEPTIONS
        no_record_found           = 1
        file_io_error             = 2
        internal_error            = 3
        open_error                = 4
        cancelled_by_user         = 5
        object_not_found          = 6
        filename_creation_failure = 7
        file_already_open         = 8
        not_authorized            = 9
        file_not_found            = 10
        OTHERS                    = 11.
    IF sy-subrc <> 0.
      IF lv_ro_ix = 1.
        WRITE: / |End of first read pass (code { sy-subrc }); continuing with next-object step.|.
        lv_gno_fallback = abap_true.
      ENDIF.
      EXIT.
    ENDIF.

    WRITE: / |Object batch { lv_ro_ix } (internal step { lv_obj_h })|.
    PERFORM process_delete_adk_object USING lv_obj_h lt_used lv_use_p_table
      CHANGING lv_cnt lv_err.
  ENDDO.

  IF lv_gno_fallback = abap_true.
    WRITE: /.
    WRITE: / 'Reading remaining objects from the archive file...'.
    CLEAR lv_gno_ix.
    DO.
      ADD 1 TO lv_gno_ix.
      CALL FUNCTION 'ARCHIVE_GET_NEXT_OBJECT'
        EXPORTING
          archive_handle = lv_arch_h
        EXCEPTIONS
          end_of_file             = 1
          file_io_error           = 2
          internal_error          = 3
          open_error              = 4
          wrong_access_to_archive = 5
          OTHERS                  = 6.
      IF sy-subrc <> 0.
        IF lv_gno_ix = 1.
          WRITE: / |No more objects in file (code { sy-subrc }); file may be empty or already processed.|.
        ENDIF.
        EXIT.
      ENDIF.
      WRITE: / |Object { lv_gno_ix }: read OK|.
      PERFORM process_delete_adk_object USING lv_arch_h lt_used lv_use_p_table
        CHANGING lv_cnt lv_err.
    ENDDO.
  ENDIF.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_arch_h
    EXCEPTIONS
      OTHERS         = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_agg lv_err.
  ENDIF.

  WRITE: /.
  WRITE: / |=== Summary: rows removed { lv_cnt }, issues { lv_err } ===|.
  WRITE: / 'If counts look wrong, check the table list printed above and the application log.'.
  IF p_test = 'X'.
    WRITE: / 'Turn off Test Mode to remove database rows and write the delete log.'.
  ENDIF.

*&---------------------------------------------------------------------*
*& Mark one DB row removed in ADK (FM varies by release).
*&---------------------------------------------------------------------*
FORM archive_adk_mark_deleted_row
  USING    VALUE(pv_handle) TYPE syst-tabix
  CHANGING cv_need_object_data_fm TYPE abap_bool.

  TRY.
    CALL FUNCTION 'ARCHIVE_DELETE_RECORD'
      EXCEPTIONS
        OTHERS = 1.
  CATCH cx_sy_dyn_call_illegal_func.
    cv_need_object_data_fm = abap_true.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& One call per archive object when ARCHIVE_DELETE_RECORD is unavailable.
*&---------------------------------------------------------------------*
FORM archive_adk_mark_del_obj USING VALUE(pv_handle) TYPE syst-tabix.

  TRY.
    CALL FUNCTION 'ARCHIVE_DELETE_OBJECT_DATA'
      EXPORTING
        archive_handle = pv_handle
      EXCEPTIONS
        internal_error          = 1
        wrong_access_to_archive = 2
        OTHERS                  = 3.
  CATCH cx_sy_dyn_call_illegal_func.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Escape ' → '' for literals in dynamic Open SQL WHERE fragments.
*&---------------------------------------------------------------------*
FORM zsp26_sql_escape_quote CHANGING cv_txt TYPE string.
  CHECK cv_txt IS NOT INITIAL.
  REPLACE ALL OCCURRENCES OF `'` IN cv_txt WITH `''`.
ENDFORM.

*&---------------------------------------------------------------------*
*& Process one ADK data object: GET_TABLE ZSTR_ARCH_REC + legacy DDIC rows.
*& pv_handle = object handle from READ_OBJECT, or file handle after GET_NEXT_OBJECT.
*&---------------------------------------------------------------------*
FORM process_delete_adk_object
  USING    VALUE(pv_handle)   TYPE syst-tabix
           VALUE(pt_used)     TYPE adk_classes
           VALUE(pv_use_ptab) TYPE abap_bool
  CHANGING cv_cnt TYPE i
           cv_err TYPE i.

  DATA: lv_got       TYPE abap_bool,
        lv_gt_rc     TYPE sy-subrc,
        lt_arch_gen  TYPE TABLE OF zstr_arch_rec,
        ls_arch_gen  TYPE zstr_arch_rec,
        lt_pairs_gen TYPE TABLE OF string,
        lv_pair_gen  TYPE string,
        lv_kf_gen    TYPE string,
        lv_kv_gen    TYPE string,
        lv_kv_esc    TYPE string,
        lv_where_gen TYPE string,
        lv_del_rc    TYPE i,
        lv_tn_cmp    TYPE tabname,
        lv_tab_try   TYPE tabname,
        lt_cfg_loc   TYPE TABLE OF tabname,
        lv_cfg_loc   TYPE tabname,
        lv_skip_rec_fm TYPE abap_bool VALUE abap_false,
        lv_zstr_db_del TYPE i VALUE 0,
        ls_pt_used     LIKE LINE OF pt_used,
        lv_del_tab     TYPE tabname,
        lv_mandt_q     TYPE string,
        lv_bad_key     TYPE abap_bool,
        lo_osql        TYPE REF TO cx_sy_dynamic_osql_error,
        lo_any         TYPE REF TO cx_root.

  CLEAR lv_got.

  REFRESH lt_arch_gen.
  CLEAR lv_gt_rc.
  CALL FUNCTION 'ARCHIVE_GET_TABLE'
    EXPORTING
      archive_handle        = pv_handle
      record_structure      = 'ZSTR_ARCH_REC'
      all_records_of_object = 'X'
    TABLES
      table                 = lt_arch_gen
    EXCEPTIONS
      end_of_object           = 1
      internal_error          = 2
      wrong_access_to_archive = 3
      OTHERS                  = 4.
  lv_gt_rc = sy-subrc.

  IF lv_gt_rc = 0 AND lt_arch_gen IS NOT INITIAL.
    WRITE: / |  Loaded { lines( lt_arch_gen ) } archive row(s) for processing.|.
    lv_got = abap_true.
    LOOP AT lt_arch_gen INTO ls_arch_gen.
      CHECK ls_arch_gen-rec_type = 'D'.
      IF p_table IS NOT INITIAL.
        lv_tn_cmp = ls_arch_gen-table_name.
        CONDENSE lv_tn_cmp.
        TRANSLATE lv_tn_cmp TO UPPER CASE.
        IF lv_tn_cmp <> p_table.
          CONTINUE.
        ENDIF.
      ENDIF.

      lv_del_tab = ls_arch_gen-table_name.
      CONDENSE lv_del_tab.
      TRANSLATE lv_del_tab TO UPPER CASE.
      IF lv_del_tab IS INITIAL.
        ADD 1 TO cv_err.
        WRITE: / '  Warning: archive row has no table name.'.
        CONTINUE.
      ENDIF.

      CLEAR: lv_where_gen, lv_pair_gen, lv_kf_gen, lv_kv_gen, lv_kv_esc, lv_bad_key.
      REFRESH lt_pairs_gen.
      SPLIT ls_arch_gen-key_vals AT '|' INTO TABLE lt_pairs_gen.
      LOOP AT lt_pairs_gen INTO lv_pair_gen.
        SPLIT lv_pair_gen AT '=' INTO lv_kf_gen lv_kv_gen.
        CONDENSE lv_kf_gen.
        CONDENSE lv_kv_gen.
        TRANSLATE lv_kf_gen TO UPPER CASE.
        PERFORM zsp26_arch_norm_keyfname CHANGING lv_kf_gen.
        CHECK lv_kf_gen IS NOT INITIAL.
        IF NOT lv_kf_gen CO '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_/'.
          WRITE: / |  Error: invalid key name in archive data: { lv_kf_gen }|.
          lv_bad_key = abap_true.
          EXIT.
        ENDIF.
        lv_kv_esc = lv_kv_gen.
        PERFORM zsp26_sql_escape_quote CHANGING lv_kv_esc.
        IF lv_where_gen IS NOT INITIAL.
          lv_where_gen = lv_where_gen && ' AND '.
        ENDIF.
        lv_where_gen = lv_where_gen && lv_kf_gen && ` EQ '` && lv_kv_esc && `'`.
      ENDLOOP.
      IF lv_bad_key = abap_true.
        ADD 1 TO cv_err.
        CONTINUE.
      ENDIF.
      IF lv_where_gen IS INITIAL.
        ADD 1 TO cv_err.
        WRITE: / |  Warning: missing key values for table { lv_del_tab }.|.
        CONTINUE.
      ENDIF.
      PERFORM zsp26_arch_fix_where_glued_and USING lv_del_tab CHANGING lv_where_gen.
      lv_mandt_q = |{ sy-mandt }|.
      lv_where_gen = |MANDT EQ '{ lv_mandt_q }' AND | && lv_where_gen.

      IF p_test = ' '.
        TRY.
            DELETE FROM (lv_del_tab) WHERE (lv_where_gen).
            lv_del_rc = sy-subrc.
            lv_dbcnt  = sy-dbcnt.
          CATCH cx_sy_dynamic_osql_error INTO lo_osql.
            ADD 1 TO cv_err.
            lv_del_rc = 8.
            lv_dbcnt  = 0.
            WRITE: / |  Error: could not delete from { lv_del_tab }: { lo_osql->get_text( ) }|.
            WRITE: / '  (Selection condition omitted here for readability.)'.
          CATCH cx_root INTO lo_any.
            ADD 1 TO cv_err.
            lv_del_rc = 8.
            lv_dbcnt  = 0.
            WRITE: / |  Error: delete failed for { lv_del_tab }: { lo_any->get_text( ) }|.
        ENDTRY.
        IF ( lv_del_rc = 0 OR lv_del_rc = 4 ) AND lv_dbcnt > 0.
          PERFORM archive_adk_mark_deleted_row USING pv_handle CHANGING lv_skip_rec_fm.
          ADD 1 TO lv_zstr_db_del.
          ADD 1 TO cv_cnt.
          PERFORM del_agg_bump_legacy USING lt_del_agg lv_del_tab.
        ELSEIF ( lv_del_rc = 0 OR lv_del_rc = 4 ) AND lv_dbcnt = 0.
          WRITE: / |  Skipped { lv_del_tab } ({ ls_arch_gen-key_vals }): row not in database (already removed).|.
        ELSEIF lv_del_rc <> 8.
          ADD 1 TO cv_err.
          WRITE: / |  Error: delete from { lv_del_tab } returned code { lv_del_rc }.|.
        ENDIF.
      ELSE.
        ADD 1 TO cv_cnt.
        WRITE: / |  [TEST] Would remove { lv_del_tab } / { ls_arch_gen-key_vals }|.
      ENDIF.
    ENDLOOP.
  ELSE.
    WRITE: / |  Primary archive format empty (code { lv_gt_rc }); trying alternate table layout.|.
  ENDIF.

  IF lv_got = abap_false.
    IF pv_use_ptab = abap_true AND p_table IS NOT INITIAL.
      PERFORM process_one_arch_table USING pv_handle p_table p_test CHANGING cv_cnt cv_err lv_got.
    ENDIF.

    IF lv_got = abap_false.
      LOOP AT pt_used INTO ls_pt_used.
        PERFORM adk_used_row_to_tabname USING ls_pt_used CHANGING lv_tab_try.
        CHECK lv_tab_try IS NOT INITIAL.
        CHECK lv_tab_try <> 'ZSTR_ARCH_REC'.
        PERFORM process_one_arch_table USING pv_handle lv_tab_try p_test CHANGING cv_cnt cv_err lv_got.
        IF lv_got = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_got = abap_false.
      SELECT table_name FROM zsp26_arch_cfg INTO TABLE lt_cfg_loc
        WHERE is_active = 'X'.
      LOOP AT lt_cfg_loc INTO lv_cfg_loc.
        PERFORM process_one_arch_table USING pv_handle lv_cfg_loc p_test CHANGING cv_cnt cv_err lv_got.
        IF lv_got = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_got = abap_false.
      WRITE: / '  Warning: could not read rows for this object from the archive file.'.
      ADD 1 TO cv_err.
    ENDIF.
  ENDIF.

  IF p_test = ' ' AND lv_skip_rec_fm = abap_true AND lv_zstr_db_del > 0.
    PERFORM archive_adk_mark_del_obj USING pv_handle.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& DDIC row type of ADK_CLASSES is not always ARCH_DDIC (no -NAME on some releases).
*& Try common component names; convert first non-empty to TABNAME.
*&---------------------------------------------------------------------*
FORM adk_used_row_to_tabname USING    ps_row TYPE any
                               CHANGING cv_tab TYPE tabname.

  FIELD-SYMBOLS <fs_comp> TYPE any.
  DATA: lt_nm TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
        lv_nm TYPE string,
        lv_s  TYPE string.

  APPEND `NAME` TO lt_nm.
  APPEND `CLASS` TO lt_nm.
  APPEND `TABNAME` TO lt_nm.
  APPEND `STRUCTURE` TO lt_nm.
  APPEND `RECORD_STRUCTURE` TO lt_nm.
  APPEND `DDIC_NAME` TO lt_nm.
  APPEND `OBJ_CLASS` TO lt_nm.
  APPEND `ARCH_CLASS` TO lt_nm.

  CLEAR cv_tab.
  LOOP AT lt_nm INTO lv_nm.
    ASSIGN COMPONENT lv_nm OF STRUCTURE ps_row TO <fs_comp>.
    IF sy-subrc <> 0 OR <fs_comp> IS NOT ASSIGNED.
      CONTINUE.
    ENDIF.
    TRY.
        MOVE <fs_comp> TO lv_s.
      CATCH cx_root.
        CONTINUE.
    ENDTRY.
    CONDENSE lv_s.
    IF strlen( lv_s ) = 0 OR strlen( lv_s ) > 30.
      CONTINUE.
    ENDIF.
    cv_tab = lv_s.
    TRANSLATE cv_tab TO UPPER CASE.
    RETURN.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
FORM process_one_arch_table
  USING    VALUE(pv_handle) TYPE syst-tabix
           VALUE(pv_tab)    TYPE tabname
           VALUE(pv_test)   TYPE c
  CHANGING cv_cnt TYPE i
           cv_err TYPE i
           cv_got TYPE abap_bool.

  DATA: lv_lines TYPE i,
        lv_t     TYPE i,
        lv_fb    TYPE abap_bool VALUE abap_false.

  " FM ARCHIVE_GET_TABLE — TABLES only accepts STANDARD TABLE (ANY TABLE → SYNTAX_ERROR).
  FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.

  cv_got = abap_false.
  TRY.
      CREATE DATA gr_dyn TYPE STANDARD TABLE OF (pv_tab).
    CATCH cx_sy_create_data_error.
      RETURN.
  ENDTRY.
  ASSIGN gr_dyn->* TO <lt>.
  REFRESH <lt>.

  TRY.
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
    CATCH cx_sy_dyn_call_illegal_type.
      WRITE: / |  Warning: table layout mismatch for { pv_tab }; skipped.|.
      RETURN.
    CATCH cx_sy_dyn_call_illegal_func.
      WRITE: / '  Warning: archive read API not available for this table on this system.'.
      RETURN.
  ENDTRY.

  IF sy-subrc <> 0 OR <lt> IS INITIAL.
    RETURN.
  ENDIF.

  cv_got = abap_true.

  IF pv_test = ' '.
    DELETE (pv_tab) FROM TABLE <lt>.
    IF sy-subrc = 0 OR sy-subrc = 4.
      lv_lines = lines( <lt> ).
      cv_cnt = cv_cnt + lv_lines.
      PERFORM del_agg_add USING lt_del_agg pv_tab lv_lines.
      CLEAR lv_fb.
      DO lv_lines TIMES.
        PERFORM archive_adk_mark_deleted_row USING pv_handle CHANGING lv_fb.
      ENDDO.
      IF lv_fb = abap_true AND lv_lines > 0.
        PERFORM archive_adk_mark_del_obj USING pv_handle.
      ENDIF.
    ELSE.
      cv_err = cv_err + 1.
      WRITE: / |  Error: database delete failed for { pv_tab } (code { sy-subrc }).|.
    ENDIF.
  ELSE.
    lv_t = lines( <lt> ).
    cv_cnt = cv_cnt + lv_t.
    WRITE: / |  [TEST] Would remove { lv_t } row(s) from { pv_tab }.|.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM del_agg_add
  USING    ct_agg TYPE ty_del_agg_htab
           VALUE(pv_tab) TYPE tabname
           VALUE(pv_n) TYPE i.

  DATA ls TYPE ty_del_agg.

  FIELD-SYMBOLS: <dg> LIKE LINE OF ct_agg.
  READ TABLE ct_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + pv_n.
  ELSE.
    CLEAR ls.
    ls-table_name = pv_tab.
    ls-cnt        = pv_n.
    INSERT ls INTO TABLE ct_agg.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM flush_arch_log_delete
  USING    ct_agg TYPE ty_del_agg_htab
           VALUE(pv_err) TYPE i.

  DATA: ls_log TYPE zsp26_arch_log,
        ls_a   TYPE ty_del_agg,
        lv_ts  TYPE timestampl.
  GET TIME STAMP FIELD lv_ts.

  IF lines( ct_agg ) > 0.
    LOOP AT ct_agg INTO ls_a.
      CLEAR ls_log.
      TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        ls_log-log_id = CONV sysuuid_x16( |{ sy-datum }{ sy-uzeit }{ sy-tabix }| ).
      ENDTRY.
      ls_log-table_name = ls_a-table_name.
      ls_log-action     = 'DELETE'.
      ls_log-rec_count  = ls_a-cnt.
      ls_log-status     = COND #( WHEN pv_err = 0 THEN 'S' ELSE 'W' ).
      ls_log-start_time = lv_ts.
      ls_log-end_time   = lv_ts.
      ls_log-exec_user  = sy-uname.
      ls_log-exec_date  = sy-datum.
      ls_log-message    = |ADK DELETE DOC={ gv_del_doc_log } (GET_TABLE): { ls_a-cnt } rows, tab { ls_a-table_name }. err { pv_err }|.
      INSERT zsp26_arch_log FROM ls_log.
      IF sy-subrc <> 0.
        WRITE: / |Warning: could not save application log line for { ls_a-table_name }.|.
      ENDIF.
    ENDLOOP.
  ELSEIF pv_err > 0.
    CLEAR ls_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      ls_log-log_id = CONV sysuuid_x16( |{ sy-datum }{ sy-uzeit }{ sy-tabix }| ).
    ENDTRY.
    ls_log-table_name = COND tabname( WHEN p_table IS NOT INITIAL THEN p_table ELSE 'Z_ARCH_EKK' ).
    ls_log-action     = 'DELETE'.
    ls_log-rec_count  = 0.
    ls_log-status     = 'E'.
    ls_log-start_time = lv_ts.
    ls_log-end_time   = lv_ts.
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    ls_log-message    = |ADK DELETE DOC={ gv_del_doc_log }: errors { pv_err } — 0 rows deleted, ROLLBACK issued.|.
    INSERT zsp26_arch_log FROM ls_log.
    ROLLBACK WORK.
    RETURN.
  ELSE.
    CLEAR ls_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      ls_log-log_id = CONV sysuuid_x16( |{ sy-datum }{ sy-uzeit }{ sy-tabix }| ).
    ENDTRY.
    ls_log-table_name = COND tabname( WHEN p_table IS NOT INITIAL THEN p_table ELSE 'Z_ARCH_EKK' ).
    ls_log-action     = 'DELETE'.
    ls_log-rec_count  = 0.
    ls_log-status     = 'W'.
    ls_log-start_time = lv_ts.
    ls_log-end_time   = lv_ts.
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    IF lv_prev_del_cnt > 0.
      ls_log-message = |ADK DELETE DOC={ gv_del_doc_log }: 0 rows — DB data already deleted (duplicate run).|.
      WRITE: / |Notice: no rows removed for session { gv_del_doc_log } (data was already removed).|.
    ELSE.
      ls_log-message = |ADK DELETE DOC={ gv_del_doc_log }: 0 rows — no archive objects found in session.|.
      WRITE: / |Notice: session { gv_del_doc_log } has no objects to process in the archive file.|.
    ENDIF.
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
        lv_kv_esc_loc TYPE string,
        lt_del_loc    TYPE ty_del_agg_htab,
        ls_del_loc    TYPE ty_del_agg,
        lv_leg_h      TYPE syst-tabix,
        lv_leg_fb     TYPE abap_bool VALUE abap_false,
        lv_leg_del_n  TYPE i VALUE 0,
        lv_leg_subrc  TYPE sy-subrc,
        lo_leg        TYPE REF TO cx_sy_dynamic_osql_error,
        lo_leg2       TYPE REF TO cx_root.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    IMPORTING
      archive_handle = lv_leg_h
    EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive (legacy / P_JSON).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
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
      CONDENSE lv_kf_loc.
      CONDENSE lv_kv_loc.
      TRANSLATE lv_kf_loc TO UPPER CASE.
      PERFORM zsp26_arch_norm_keyfname CHANGING lv_kf_loc.
      CHECK lv_kf_loc IS NOT INITIAL.
      lv_kv_esc_loc = lv_kv_loc.
      PERFORM zsp26_sql_escape_quote CHANGING lv_kv_esc_loc.
      IF lv_where_loc IS NOT INITIAL. lv_where_loc &&= ' AND '. ENDIF.
      lv_where_loc &&= lv_kf_loc && ` EQ '` && lv_kv_esc_loc && `'`.
    ENDLOOP.
    PERFORM zsp26_arch_fix_where_glued_and USING ls_arec_loc-table_name CHANGING lv_where_loc.
    lv_where_loc = 'MANDT EQ ''' && sy-mandt && ''' AND ' && lv_where_loc.

    WRITE: / |  Legacy row: { ls_arec_loc-table_name } / { ls_arec_loc-key_vals }|.

    IF p_test = ' '.
      CLEAR lv_leg_subrc.
      TRY.
          DELETE FROM (ls_arec_loc-table_name) WHERE (lv_where_loc).
          lv_leg_subrc = sy-subrc.
        CATCH cx_sy_dynamic_osql_error INTO lo_leg.
          ADD 1 TO lv_err_loc.
          lv_leg_subrc = 8.
          WRITE: / |    Error (legacy): { lo_leg->get_text( ) }|.
        CATCH cx_root INTO lo_leg2.
          ADD 1 TO lv_err_loc.
          lv_leg_subrc = 8.
          WRITE: / |    Error (legacy): { lo_leg2->get_text( ) }|.
      ENDTRY.
      IF lv_leg_subrc = 0.
        PERFORM archive_adk_mark_deleted_row USING lv_leg_h CHANGING lv_leg_fb.
        ADD 1 TO lv_leg_del_n.
        ADD 1 TO lv_cnt_loc.
        PERFORM del_agg_bump_legacy USING lt_del_loc ls_arec_loc-table_name.
      ELSEIF lv_leg_subrc = 4.
        PERFORM archive_adk_mark_deleted_row USING lv_leg_h CHANGING lv_leg_fb.
        ADD 1 TO lv_leg_del_n.
        ADD 1 TO lv_cnt_loc.
        PERFORM del_agg_bump_legacy USING lt_del_loc ls_arec_loc-table_name.
        WRITE: / '    Note: row already removed from database.'.
      ELSEIF lv_leg_subrc <> 8.
        ADD 1 TO lv_err_loc.
      ENDIF.
    ELSE.
      ADD 1 TO lv_cnt_loc.
    ENDIF.
  ENDDO.

  IF p_test = ' ' AND lv_leg_fb = abap_true AND lv_leg_del_n > 0.
    PERFORM archive_adk_mark_del_obj USING lv_leg_h.
  ENDIF.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_leg_h
    EXCEPTIONS
      OTHERS         = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_loc lv_err_loc.
  ENDIF.

  WRITE: / |=== Legacy format summary: processed { lv_cnt_loc }, issues { lv_err_loc } ===|.
ENDFORM.

*&---------------------------------------------------------------------*
FORM del_agg_bump_legacy
  USING    ct_agg TYPE ty_del_agg_htab
           VALUE(pv_tab) TYPE tabname.

  DATA ls TYPE ty_del_agg.

  FIELD-SYMBOLS: <dg> LIKE LINE OF ct_agg.
  READ TABLE ct_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + 1.
  ELSE.
    CLEAR ls.
    ls-table_name = pv_tab.
    ls-cnt        = 1.
    INSERT ls INTO TABLE ct_agg.
  ENDIF.
ENDFORM.
