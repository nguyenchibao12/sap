REPORT z_arch_ekk_read.

INCLUDE z_gsp18_arch_dyn.

*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_READ
*& ADK Read / Restore — Archive Object Z_ARCH_EKK
*& OPEN_FOR_READ → GET_NEXT_OBJECT + GET_TABLE first (PUT_TABLE / S/4); else READ_OBJECT fallback
*& Display: REUSE_ALV_LIST_DISPLAY I_STRUCTURE_NAME (no manual fieldcat)
*& Restore: MODIFY (upsert) + merge JSON chunks (D + 2) + ZSP26_ARCH_LOG
*& P_JSON: legacy ty_arch_rec + GET_NEXT_RECORD + SALV on flat ty_disp
*&---------------------------------------------------------------------*

TYPES: BEGIN OF ty_arch_rec,
        rec_type   TYPE c LENGTH 1,
        table_name TYPE c LENGTH 30,
        key_vals   TYPE c LENGTH 255,
        data_json  TYPE c LENGTH 255,
      END OF ty_arch_rec.

TYPES: BEGIN OF ty_disp,
        table_name TYPE tabname,
        key_vals   TYPE char255,
        data_json  TYPE string,
      END OF ty_disp.

DATA: ls_arec    TYPE ty_arch_rec,
      lt_disp    TYPE TABLE OF ty_disp,
      ls_disp    TYPE ty_disp,
      g_scr_r0(72) TYPE c,
      lv_arch_h  TYPE syst-tabix,
      lv_obj     TYPE arch_obj-object VALUE 'Z_ARCH_EKK',
      gr_dyn     TYPE REF TO data.

FIELD-SYMBOLS: <lt_dyn> TYPE ANY TABLE.

PARAMETERS: p_table TYPE tabname.
PARAMETERS: p_rest  TYPE c       AS CHECKBOX DEFAULT ' '.
PARAMETERS: p_json  TYPE c       AS CHECKBOX DEFAULT ' '.
PARAMETERS: p_doc   TYPE admi_run-document.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  g_scr_r0 = 'F4=ZSP26_ARCH_CFG. P_REST=restore. P_DOC=session (optional). P_JSON=legacy JSON.'.

  DATA: lv_hub_tab TYPE tabname,
        ls_ra      TYPE admi_run.

  IMPORT arch_tabname = lv_hub_tab FROM MEMORY ID 'Z_GSP18_ARCH_TAB'.
  IF sy-subrc = 0.
    IF p_rest = 'X' AND p_doc IS NOT INITIAL.
      CLEAR p_table.
    ENDIF.
    IF p_table IS INITIAL
       AND lv_hub_tab IS NOT INITIAL
       AND NOT ( p_rest = 'X' AND p_doc IS NOT INITIAL ).
      p_table = lv_hub_tab.
    ENDIF.
    FREE MEMORY ID 'Z_GSP18_ARCH_TAB'.
  ENDIF.

  IMPORT read_admi = ls_ra FROM MEMORY ID 'Z_GSP18_ARCH_READ_DOC'.
  IF sy-subrc = 0 AND ls_ra-document IS NOT INITIAL.
    p_doc = ls_ra-document.
  ENDIF.
  FREE MEMORY ID 'Z_GSP18_ARCH_READ_DOC'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
*----------------------------------------------------------------------*
  PERFORM f4_arch_cfg_table CHANGING p_table.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_doc.
*----------------------------------------------------------------------*
  PERFORM f4_arch_doc_user CHANGING p_doc.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  IF p_json = 'X'.
    PERFORM run_read_legacy_json.
    EXIT.
  ENDIF.

  IF p_doc IS NOT INITIAL.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
      EXPORTING
        object             = 'Z_ARCH_EKK'
        archive_document   = p_doc
      IMPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        file_already_open             = 1
        file_io_error                 = 2
        internal_error                = 3
        no_files_available            = 4
        object_not_found              = 5
        open_error                    = 6
        not_authorized                = 7
        archiving_standard_violation  = 8
        OTHERS                        = 9.
  ELSE.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
      EXPORTING
        object = 'Z_ARCH_EKK'
      IMPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        file_already_open             = 1
        file_io_error                 = 2
        internal_error                = 3
        no_files_available            = 4
        object_not_found              = 5
        open_error                    = 6
        not_authorized                = 7
        archiving_standard_violation  = 8
        OTHERS                        = 9.
  ENDIF.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open the archive for reading. Check the session ID or pick the correct archive file.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CONDENSE p_table.
  TRANSLATE p_table TO UPPER CASE.

  DATA: lv_obj_h TYPE syst-tabix,
        lv_ro_ix TYPE i VALUE 0,
        lv_gno_ix TYPE i VALUE 0.

  CLEAR lt_disp.

  " 1) File handle path first — avoids READ_OBJECT moving cursor before GET_NEXT (same as Z_ARCH_EKK_DELETE).
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
      EXIT.
    ENDIF.

    PERFORM read_process_zstr_object USING lv_arch_h.
  ENDDO.

  " 2) Object-handle path if nothing found (older stacks / other file layout).
  IF lines( lt_disp ) = 0.
    CLEAR lv_ro_ix.
    DO.
      ADD 1 TO lv_ro_ix.
      CLEAR lv_obj_h.
      CALL FUNCTION 'ARCHIVE_READ_OBJECT'
        EXPORTING
          object = lv_obj
        IMPORTING
          archive_handle = lv_obj_h
        EXCEPTIONS
          no_record_found             = 1
          file_io_error               = 2
          internal_error              = 3
          open_error                  = 4
          cancelled_by_user           = 5
          object_not_found            = 6
          filename_creation_failure   = 7
          file_already_open           = 8
          not_authorized              = 9
          file_not_found              = 10
          OTHERS                      = 11.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      PERFORM read_process_zstr_object USING lv_obj_h.
    ENDDO.
  ENDIF.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_arch_h
    EXCEPTIONS
      OTHERS         = 1.

  IF lt_disp IS INITIAL.
    MESSAGE |No data found for { p_table }. Check the archive session matches your write run, or use legacy mode if your file uses the old format.| TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF p_rest = 'X'.
    " INSERT + log + MESSAGE already done in read_process_zstr_object — do not open ALV again.
  ELSE.
    DATA: lo_alv    TYPE REF TO cl_salv_table,
          lo_funcs  TYPE REF TO cl_salv_functions,
          lo_cols   TYPE REF TO cl_salv_columns_table,
          lo_col    TYPE REF TO cl_salv_column_table,
          lo_disp_s TYPE REF TO cl_salv_display_settings,
          lx_gen    TYPE REF TO cx_salv_msg.
    TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_disp ).
      lo_funcs = lo_alv->get_functions( ).
      lo_funcs->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      TRY. lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
          lo_col->set_long_text( 'Table Name' ). CATCH cx_salv_not_found. ENDTRY.
      TRY. lo_col ?= lo_cols->get_column( 'KEY_VALS' ).
          lo_col->set_long_text( 'Key Values' ). CATCH cx_salv_not_found. ENDTRY.
      TRY. lo_col ?= lo_cols->get_column( 'DATA_JSON' ).
          lo_col->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.
      lo_disp_s = lo_alv->get_display_settings( ).
      lo_disp_s->set_list_header(
        |GENERIC ADK — { p_table } [ { lines( lt_disp ) } ]| ).
      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_gen.
      MESSAGE lx_gen->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDIF.

*&---------------------------------------------------------------------*
*& One ADK object: GET_TABLE ZSTR_ARCH_REC → lt_disp; optional restore.
*&---------------------------------------------------------------------*
FORM read_process_zstr_object
  USING VALUE(pv_handle) TYPE syst-tabix.

  TYPES: BEGIN OF ty_tbl_stat,
           table_name TYPE tabname,
           cnt_ok     TYPE i,
           cnt_err    TYPE i,
         END OF ty_tbl_stat.

  DATA: lt_arch   TYPE TABLE OF zstr_arch_rec,
        ls_arch2  TYPE zstr_arch_rec,
        ls_fill   TYPE zstr_arch_rec,
        lv_ins_rc TYPE i,
        ls_log    TYPE zsp26_arch_log,
        lv_ts_s   TYPE timestampl,
        lv_ts_e   TYPE timestampl,
        lv_ins    TYPE i,
        lv_ief    TYPE i,
        lv_tn_cmp TYPE tabname,
        lv_tn_row TYPE tabname,
        lv_disp0  TYPE i,
        lv_from   TYPE syst-tabix,
        lv_gt_rc  TYPE sy-subrc,
        lt_tbl_stat TYPE TABLE OF ty_tbl_stat,
        ls_tbl_stat TYPE ty_tbl_stat,
        lv_mode_txt TYPE char20,
        lv_doc_txt  TYPE char40,
        lv_tbl_msg  TYPE string,
        lv_tbl_seg  TYPE string,
        lv_stat_ix  TYPE sy-tabix.

  DATA: BEGIN OF ls_mj,
          mj_table TYPE tabname,
          mj_keys  TYPE char255,
          mj_json  TYPE string,
        END OF ls_mj.
  DATA lv_mj_ok TYPE abap_bool.

  lv_disp0 = lines( lt_disp ).

  REFRESH lt_arch.

  CALL FUNCTION 'ARCHIVE_GET_TABLE'
    EXPORTING
      archive_handle           = pv_handle
      record_structure         = 'ZSTR_ARCH_REC'
      all_records_of_object    = 'X'
    TABLES
      table                    = lt_arch
    EXCEPTIONS
      end_of_object            = 1
      internal_error           = 2
      wrong_access_to_archive  = 3
      OTHERS                   = 4.
  lv_gt_rc = sy-subrc.

  " RC=1 end_of_object may still contain data in TABLE — do not skip (previously → Restore 0).
  IF lt_arch IS INITIAL.
    " Some ADK stacks: GET_TABLE after PUT_TABLE returns empty TABLE despite data — read sequentially via ZSTR_ARCH_REC.
    DO.
      CLEAR ls_fill.
      CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
        EXPORTING
          archive_handle = pv_handle
        IMPORTING
          record         = ls_fill
        EXCEPTIONS
          end_of_object  = 1
          OTHERS         = 2.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      APPEND ls_fill TO lt_arch.
    ENDDO.
    IF lines( lt_arch ) > 0.
      WRITE: / |Note: primary read returned no rows; reading next records ({ lines( lt_arch ) } row(s)).|.
    ENDIF.
  ENDIF.

  IF lt_arch IS INITIAL.
    WRITE: / |Skipped object: no rows read (code { lv_gt_rc }).|.
    RETURN.
  ENDIF.
  IF lv_gt_rc <> 0 AND lv_gt_rc <> 1.
    WRITE: / |Warning: unexpected read status { lv_gt_rc } with { lines( lt_arch ) } row(s); continuing.|.
  ENDIF.

  " Merge REC_TYPE D (first JSON chunk) + 2 (continuations); old archives = single D only.
  CLEAR: ls_mj-mj_table, ls_mj-mj_keys, ls_mj-mj_json.
  LOOP AT lt_arch INTO ls_arch2.
    IF ls_arch2-rec_type = 'D'.
      IF ls_mj-mj_table IS NOT INITIAL.
        CLEAR ls_disp.
        ls_disp-table_name = ls_mj-mj_table.
        ls_disp-key_vals   = ls_mj-mj_keys.
        ls_disp-data_json  = ls_mj-mj_json.
        lv_mj_ok = abap_true.
        IF p_table IS NOT INITIAL.
          lv_tn_row = ls_disp-table_name.
          CONDENSE lv_tn_row.
          TRANSLATE lv_tn_row TO UPPER CASE.
          lv_tn_cmp = p_table.
          TRANSLATE lv_tn_cmp TO UPPER CASE.
          IF lv_tn_row <> lv_tn_cmp.
            lv_mj_ok = abap_false.
          ENDIF.
        ENDIF.
        IF lv_mj_ok = abap_true.
          APPEND ls_disp TO lt_disp.
        ENDIF.
      ENDIF.
      CLEAR: ls_mj-mj_table, ls_mj-mj_keys, ls_mj-mj_json.
      ls_mj-mj_table = ls_arch2-table_name.
      ls_mj-mj_keys  = ls_arch2-key_vals.
      ls_mj-mj_json  = ls_arch2-data_json.
    ELSEIF ls_arch2-rec_type = '2' AND ls_mj-mj_table IS NOT INITIAL.
      ls_mj-mj_json = |{ ls_mj-mj_json }{ ls_arch2-data_json }|.
    ENDIF.
  ENDLOOP.
  IF ls_mj-mj_table IS NOT INITIAL.
    CLEAR ls_disp.
    ls_disp-table_name = ls_mj-mj_table.
    ls_disp-key_vals   = ls_mj-mj_keys.
    ls_disp-data_json  = ls_mj-mj_json.
    lv_mj_ok = abap_true.
    IF p_table IS NOT INITIAL.
      lv_tn_row = ls_disp-table_name.
      CONDENSE lv_tn_row.
      TRANSLATE lv_tn_row TO UPPER CASE.
      lv_tn_cmp = p_table.
      TRANSLATE lv_tn_cmp TO UPPER CASE.
      IF lv_tn_row <> lv_tn_cmp.
        lv_mj_ok = abap_false.
      ENDIF.
    ENDIF.
    IF lv_mj_ok = abap_true.
      APPEND ls_disp TO lt_disp.
    ENDIF.
  ENDIF.

  IF p_rest = 'X'.
    IF lines( lt_disp ) <= lv_disp0.
      RETURN.
    ENDIF.
    lv_from = lv_disp0 + 1.
    GET TIME STAMP FIELD lv_ts_s.
    CLEAR: lv_ins, lv_ief, lt_tbl_stat, lv_tbl_msg.
    LOOP AT lt_disp INTO ls_disp FROM lv_from.
      lv_tn_row = ls_disp-table_name.
      CONDENSE lv_tn_row.
      TRANSLATE lv_tn_row TO UPPER CASE.
      TRY.
          CREATE DATA gr_dyn TYPE (lv_tn_row).
        CATCH cx_sy_create_data_error.
          ADD 1 TO lv_ief.
          WRITE: / |  Skipped restore: table { lv_tn_row } is not defined in the dictionary.|.
          CONTINUE.
      ENDTRY.
      ASSIGN gr_dyn->* TO FIELD-SYMBOL(<rec_dyn>).
      TRY.
          /ui2/cl_json=>deserialize(
            EXPORTING json = ls_disp-data_json
            CHANGING  data = <rec_dyn> ).
          PERFORM restore_fill_aedat_from_bedat USING gr_dyn.
          PERFORM restore_assign_current_mandt USING gr_dyn.
          MODIFY (lv_tn_row) FROM <rec_dyn>.
          IF sy-subrc = 0.
            ADD 1 TO lv_ins.
            CLEAR ls_tbl_stat.
            READ TABLE lt_tbl_stat INTO ls_tbl_stat WITH KEY table_name = lv_tn_row.
            lv_stat_ix = sy-tabix.
            IF sy-subrc <> 0.
              ls_tbl_stat-table_name = lv_tn_row.
            ENDIF.
            ADD 1 TO ls_tbl_stat-cnt_ok.
            IF lv_stat_ix > 0.
              MODIFY lt_tbl_stat FROM ls_tbl_stat INDEX lv_stat_ix.
            ELSE.
              APPEND ls_tbl_stat TO lt_tbl_stat.
            ENDIF.
          ELSE.
            ADD 1 TO lv_ief.
            CLEAR ls_tbl_stat.
            READ TABLE lt_tbl_stat INTO ls_tbl_stat WITH KEY table_name = lv_tn_row.
            lv_stat_ix = sy-tabix.
            IF sy-subrc <> 0.
              ls_tbl_stat-table_name = lv_tn_row.
            ENDIF.
            ADD 1 TO ls_tbl_stat-cnt_err.
            IF lv_stat_ix > 0.
              MODIFY lt_tbl_stat FROM ls_tbl_stat INDEX lv_stat_ix.
            ELSE.
              APPEND ls_tbl_stat TO lt_tbl_stat.
            ENDIF.
          ENDIF.
        CATCH cx_root.
          ADD 1 TO lv_ief.
          CLEAR ls_tbl_stat.
          READ TABLE lt_tbl_stat INTO ls_tbl_stat WITH KEY table_name = lv_tn_row.
          lv_stat_ix = sy-tabix.
          IF sy-subrc <> 0.
            ls_tbl_stat-table_name = lv_tn_row.
          ENDIF.
          ADD 1 TO ls_tbl_stat-cnt_err.
          IF lv_stat_ix > 0.
            MODIFY lt_tbl_stat FROM ls_tbl_stat INDEX lv_stat_ix.
          ELSE.
            APPEND ls_tbl_stat TO lt_tbl_stat.
          ENDIF.
      ENDTRY.
    ENDLOOP.
    lv_ins_rc = COND #( WHEN lv_ief = 0 THEN 0 ELSE 4 ).
    IF lv_ins > 0.
      COMMIT WORK.
    ENDIF.
    GET TIME STAMP FIELD lv_ts_e.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    SELECT SINGLE config_id FROM zsp26_arch_cfg INTO @ls_log-config_id
      WHERE table_name = @p_table AND is_active = 'X'.
    ls_log-table_name = COND tabname( WHEN p_table IS INITIAL THEN '*' ELSE p_table ).
    ls_log-action     = 'RESTORE'.
    ls_log-rec_count  = lv_ins.
    ls_log-status     = COND #( WHEN lv_ief = 0 THEN 'S' ELSE 'W' ).
    ls_log-start_time = lv_ts_s.
    ls_log-end_time   = lv_ts_e.
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    lv_mode_txt = COND #( WHEN p_table IS INITIAL THEN 'FULL_SESSION' ELSE 'TABLE_ONLY' ).
    lv_doc_txt  = COND #( WHEN p_doc IS INITIAL THEN 'AUTO_PICK' ELSE p_doc ).

    SORT lt_tbl_stat BY table_name.
    LOOP AT lt_tbl_stat INTO ls_tbl_stat.
      lv_tbl_seg = |{ ls_tbl_stat-table_name }:OK={ ls_tbl_stat-cnt_ok },ERR={ ls_tbl_stat-cnt_err }|.
      IF lv_tbl_msg IS INITIAL.
        lv_tbl_msg = lv_tbl_seg.
      ELSEIF strlen( lv_tbl_msg ) + strlen( lv_tbl_seg ) + 2 <= 120.
        lv_tbl_msg = |{ lv_tbl_msg }; { lv_tbl_seg }|.
      ELSE.
        lv_tbl_msg = |{ lv_tbl_msg }; ...|.
        EXIT.
      ENDIF.
    ENDLOOP.

    ls_log-message = |RESTORE { lv_mode_txt } DOC={ lv_doc_txt } OK={ lv_ins } ERR={ lv_ief } RC={ lv_ins_rc } [{ lv_tbl_msg }]|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.
    IF lv_ins > 0.
      MESSAGE |Restored { lv_ins } rows| TYPE 'S'.
    ELSEIF lv_ief > 0.
      MESSAGE |Restore finished with 0 rows inserted; { lv_ief } failed. Check data format or table keys.|
              TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.

ENDFORM.

*----------------------------------------------------------------------*
FORM run_read_legacy_json.
  DATA: lv_arch_h_loc TYPE syst-tabix.

  IF p_doc IS NOT INITIAL.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
      EXPORTING
        object             = 'Z_ARCH_EKK'
        archive_document   = p_doc
      IMPORTING
        archive_handle = lv_arch_h_loc
      EXCEPTIONS OTHERS = 1.
  ELSE.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
      EXPORTING
        object = 'Z_ARCH_EKK'
      IMPORTING
        archive_handle = lv_arch_h_loc
      EXCEPTIONS OTHERS = 1.
  ENDIF.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive for read (legacy).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR lt_disp.
  DO.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_OBJECT'
      EXPORTING
        archive_handle = lv_arch_h_loc
      EXCEPTIONS
        end_of_file    = 1
        OTHERS         = 2.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.

    DO.
      CLEAR ls_arec.
      CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
        EXPORTING
          archive_handle = lv_arch_h_loc
        IMPORTING
          record         = ls_arec
        EXCEPTIONS
          end_of_object  = 1
          OTHERS         = 2.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      CHECK ls_arec-rec_type = 'D'.
      IF p_table IS NOT INITIAL AND ls_arec-table_name <> p_table.
        CONTINUE.
      ENDIF.

      CLEAR ls_disp.
      ls_disp-table_name = ls_arec-table_name.
      ls_disp-key_vals   = ls_arec-key_vals.
      ls_disp-data_json  = ls_arec-data_json.
      APPEND ls_disp TO lt_disp.
    ENDDO.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_arch_h_loc
    EXCEPTIONS
      OTHERS         = 1.

  IF lt_disp IS INITIAL.
    MESSAGE |No legacy JSON records for '{ p_table }'| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA: lo_alv    TYPE REF TO cl_salv_table,
        lo_funcs  TYPE REF TO cl_salv_functions,
        lo_cols   TYPE REF TO cl_salv_columns_table,
        lo_col    TYPE REF TO cl_salv_column_table,
        lo_disp_s TYPE REF TO cl_salv_display_settings,
        lx        TYPE REF TO cx_salv_msg.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_disp ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY. lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
        lo_col->set_long_text( 'Table Name' ). CATCH cx_salv_not_found. ENDTRY.
    TRY. lo_col ?= lo_cols->get_column( 'KEY_VALS' ).
        lo_col->set_long_text( 'Key Values' ). CATCH cx_salv_not_found. ENDTRY.
    TRY. lo_col ?= lo_cols->get_column( 'DATA_JSON' ).
        lo_col->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.

    lo_disp_s = lo_alv->get_display_settings( ).
    lo_disp_s->set_list_header(
      |LEGACY JSON — { p_table } [ { lines( lt_disp ) } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO lx.
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.

  IF p_rest = 'X'.
    DATA: lv_ok   TYPE i VALUE 0,
          lv_err  TYPE i VALUE 0,
          gr_rec  TYPE REF TO data,
          lv_json TYPE string,
          lv_ltab TYPE tabname.

    LOOP AT lt_disp INTO ls_disp.
      lv_ltab = ls_disp-table_name.
      CONDENSE lv_ltab.
      TRANSLATE lv_ltab TO UPPER CASE.
      TRY.
          CREATE DATA gr_rec TYPE (lv_ltab).
        CATCH cx_sy_create_data_error.
          ADD 1 TO lv_err.
          CONTINUE.
      ENDTRY.
      ASSIGN gr_rec->* TO FIELD-SYMBOL(<rec>).
      TRY.
        lv_json = ls_disp-data_json.
        /ui2/cl_json=>deserialize(
          EXPORTING json = lv_json
          CHANGING  data = <rec> ).
        PERFORM restore_fill_aedat_from_bedat USING gr_rec.
        PERFORM restore_assign_current_mandt USING gr_rec.
        MODIFY (lv_ltab) FROM <rec>.
        IF sy-subrc = 0.
          ADD 1 TO lv_ok.
        ELSE.
          ADD 1 TO lv_err.
        ENDIF.
      CATCH cx_root.
        ADD 1 TO lv_err.
      ENDTRY.
    ENDLOOP.

    IF lv_ok > 0. COMMIT WORK. ENDIF.

    DATA: ls_log2 TYPE zsp26_arch_log,
          lv_log_tab TYPE tabname.
    lv_log_tab = p_table.
    IF lv_log_tab IS INITIAL.
      READ TABLE lt_disp INTO ls_disp INDEX 1.
      IF sy-subrc = 0.
        lv_log_tab = ls_disp-table_name.
      ENDIF.
    ENDIF.
    TRY. ls_log2-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    SELECT SINGLE config_id FROM zsp26_arch_cfg INTO @ls_log2-config_id
      WHERE table_name = @lv_log_tab AND is_active = 'X'.
    ls_log2-table_name = lv_log_tab.
    ls_log2-action     = 'RESTORE'.
    ls_log2-rec_count  = lv_ok.
    ls_log2-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log2-exec_user  = sy-uname.
    ls_log2-exec_date  = sy-datum.
    ls_log2-message    = |Legacy RESTORE: { lv_ok } rows. Err={ lv_err }|.
    INSERT zsp26_arch_log FROM ls_log2.
    COMMIT WORK.

    MESSAGE |Restored { lv_ok } records. Errors: { lv_err }| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& After JSON deserialize: force login client so rows appear in SE16 / current mandt.
*&---------------------------------------------------------------------*
FORM restore_assign_current_mandt USING pr_row TYPE REF TO data.
  FIELD-SYMBOLS: <wa> TYPE any,
                <mv> TYPE any.
  IF pr_row IS NOT BOUND.
    RETURN.
  ENDIF.
  ASSIGN pr_row->* TO <wa>.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  ASSIGN COMPONENT 'MANDT' OF STRUCTURE <wa> TO <mv>.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  <mv> = sy-mandt.
ENDFORM.

*&---------------------------------------------------------------------*
*& EKKO-style: AEDAT empty but BEDAT set → copy so ARCH CFG on AEDAT still finds row after RESTORE.
*&---------------------------------------------------------------------*
FORM restore_fill_aedat_from_bedat USING pr_row TYPE REF TO data.
  FIELD-SYMBOLS: <wa> TYPE any,
                 <ae> TYPE any,
                 <be> TYPE any.
  IF pr_row IS NOT BOUND.
    RETURN.
  ENDIF.
  ASSIGN pr_row->* TO <wa>.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  ASSIGN COMPONENT 'AEDAT' OF STRUCTURE <wa> TO <ae>.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  ASSIGN COMPONENT 'BEDAT' OF STRUCTURE <wa> TO <be>.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  IF <ae> IS INITIAL AND NOT <be> IS INITIAL.
    <ae> = <be>.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM handle_ucomm USING r_ucomm TYPE sy-ucomm rs_selfield TYPE slis_selfield.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM F4_ARCH_DOC_USER — F4 for p_doc: admin sees all, user sees own sessions
*&---------------------------------------------------------------------*
FORM f4_arch_doc_user CHANGING cv_doc TYPE admi_run-document.
  TYPES: BEGIN OF ty_doc_f4,
           document   TYPE admi_run-document,
           creat_date TYPE admi_run-creat_date,
           status     TYPE admi_run-status,
           user_name  TYPE admi_run-user_name,
         END OF ty_doc_f4.

  DATA: lt_f4  TYPE TABLE OF ty_doc_f4,
        ls_f4  TYPE ty_doc_f4,
        lt_run TYPE TABLE OF admi_run,
        ls_run TYPE admi_run,
        lt_ret TYPE TABLE OF ddshretval,
        ls_ret TYPE ddshretval,
        lv_obj TYPE arch_obj-object VALUE 'Z_ARCH_EKK',
        lv_is_admin TYPE abap_bool.

  " Check admin via ZSP26_ARCH_ADMIN table
  SELECT SINGLE uname FROM zsp26_arch_admin
    INTO @DATA(lv_u)
    WHERE uname = @sy-uname.
  lv_is_admin = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

  IF lv_is_admin = abap_true.
    SELECT * FROM admi_run
      WHERE object = @lv_obj
      INTO TABLE @lt_run
      UP TO 500 ROWS.
  ELSE.
    SELECT * FROM admi_run
      WHERE object    = @lv_obj
        AND user_name = @sy-uname
      INTO TABLE @lt_run
      UP TO 500 ROWS.
  ENDIF.

  SORT lt_run BY creat_date DESCENDING document DESCENDING.

  LOOP AT lt_run INTO ls_run.
    CLEAR ls_f4.
    ls_f4-document   = ls_run-document.
    ls_f4-creat_date = ls_run-creat_date.
    ls_f4-status     = ls_run-status.
    ls_f4-user_name  = ls_run-user_name.
    APPEND ls_f4 TO lt_f4.
  ENDLOOP.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'DOCUMENT'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'P_DOC'
      window_title = 'Archive Sessions — Select for Restore'
      value_org    = 'S'
    TABLES
      value_tab    = lt_f4
      return_tab   = lt_ret
    EXCEPTIONS
      OTHERS       = 0.

  READ TABLE lt_ret INTO ls_ret INDEX 1.
  IF sy-subrc = 0 AND ls_ret-fieldval IS NOT INITIAL.
    cv_doc = CONV admi_run-document( ls_ret-fieldval ).
  ENDIF.
ENDFORM.

