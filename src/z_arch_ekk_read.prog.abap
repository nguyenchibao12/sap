REPORT z_arch_ekk_read.
*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_READ
*& ADK Read / Restore — Archive Object Z_ARCH_EKK
*& Default: OPEN_FOR_READ → ARCHIVE_READ_OBJECT → ARCHIVE_GET_TABLE
*& Display: REUSE_ALV_LIST_DISPLAY I_STRUCTURE_NAME (no manual fieldcat)
*& Restore: INSERT (tab) FROM TABLE <dyn> + ZSP26_ARCH_LOG
*& P_JSON: legacy ty_arch_rec + GET_NEXT_RECORD + SALV on flat ty_disp
*&---------------------------------------------------------------------*

TYPES: BEGIN OF ty_arch_rec,
         rec_type   TYPE c LENGTH 1,
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_arch_rec.

TYPES: BEGIN OF ty_disp,
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_disp.

DATA: ls_arec    TYPE ty_arch_rec,
      lt_disp    TYPE TABLE OF ty_disp,
      ls_disp    TYPE ty_disp,
      g_scr_r0(72) TYPE c,
      lv_arch_h  TYPE syst-tabix,
      lv_obj     TYPE arch_obj-object VALUE 'Z_ARCH_EKK',
      gr_dyn     TYPE REF TO data.

FIELD-SYMBOLS: <lt_dyn> TYPE ANY TABLE.

PARAMETERS: p_table TYPE tabname DEFAULT 'ZSP26_EKKO'.
PARAMETERS: p_rest  TYPE c       AS CHECKBOX DEFAULT ' '.
PARAMETERS: p_json  TYPE c       AS CHECKBOX DEFAULT ' '.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  g_scr_r0 = 'F4 = ZSP26_ARCH_CFG. P_REST restores after list. P_JSON = old JSON archive format.'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
*----------------------------------------------------------------------*
  PERFORM f4_arch_cfg_table.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  IF p_json = 'X'.
    PERFORM run_read_legacy_json.
    EXIT.
  ENDIF.

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
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive Z_ARCH_EKK for read (SARA / file selection).'
            TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA: lv_any TYPE abap_bool VALUE abap_false,
        lv_ts_s TYPE timestampl,
        lv_ts_e TYPE timestampl.

  WHILE abap_true.
    CALL FUNCTION 'ARCHIVE_READ_OBJECT'
      EXPORTING
        archive_handle = lv_arch_h
        object         = lv_obj
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

    DATA(lv_tab) = p_table.
    IF lv_tab IS INITIAL.
      MESSAGE 'P_TABLE required for GET_TABLE read path.' TYPE 'S' DISPLAY LIKE 'E'.
      CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT' EXCEPTIONS OTHERS = 1.
      RETURN.
    ENDIF.

    TRY.
        CREATE DATA gr_dyn TYPE TABLE OF (lv_tab).
      CATCH cx_sy_create_data_error.
        MESSAGE |Invalid table name { lv_tab }| TYPE 'S' DISPLAY LIKE 'E'.
        CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT' EXCEPTIONS OTHERS = 1.
        RETURN.
    ENDTRY.
    ASSIGN gr_dyn->* TO <lt_dyn>.
    REFRESH <lt_dyn>.

    CALL FUNCTION 'ARCHIVE_GET_TABLE'
      EXPORTING
        archive_handle           = lv_arch_h
        record_structure         = lv_tab
        all_records_of_object    = 'X'
      TABLES
        table                    = <lt_dyn>
      EXCEPTIONS
        end_of_object            = 1
        internal_error           = 2
        wrong_access_to_archive  = 3
        OTHERS                   = 4.

    IF sy-subrc <> 0 OR <lt_dyn> IS INITIAL.
      WRITE: / |SKIP OBJECT: GET_TABLE { lv_tab } RC={ sy-subrc }|.
      CONTINUE.
    ENDIF.

    lv_any = abap_true.

    CALL FUNCTION 'REUSE_ALV_LIST_DISPLAY'
      EXPORTING
        i_structure_name       = lv_tab
        i_callback_program     = sy-repid
        i_callback_user_command = 'HANDLE_UCOMM'
      TABLES
        t_outtab               = <lt_dyn>
      EXCEPTIONS
        program_error        = 1
        OTHERS               = 2.

    IF p_rest = 'X'.
      DATA: lv_ins    TYPE i VALUE 0,
            lv_ief    TYPE i VALUE 0,
            lv_ins_rc TYPE i,
            ls_log    TYPE zsp26_arch_log.
      GET TIME STAMP FIELD lv_ts_s.
      INSERT (lv_tab) FROM TABLE <lt_dyn>.
      lv_ins_rc = sy-subrc.
      IF lv_ins_rc = 0.
        lv_ins = lines( <lt_dyn> ).
      ELSE.
        lv_ief = 1.
      ENDIF.
      IF lv_ins > 0.
        COMMIT WORK.
      ENDIF.
      GET TIME STAMP FIELD lv_ts_e.
      TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error. ENDTRY.
      SELECT SINGLE config_id FROM zsp26_arch_cfg INTO @ls_log-config_id
        WHERE table_name = @lv_tab AND is_active = 'X'.
      ls_log-table_name = lv_tab.
      ls_log-action     = 'RESTORE'.
      ls_log-rec_count  = lv_ins.
      ls_log-status     = COND #( WHEN lv_ief = 0 THEN 'S' ELSE 'W' ).
      ls_log-start_time = lv_ts_s.
      ls_log-end_time   = lv_ts_e.
      ls_log-exec_user  = sy-uname.
      ls_log-exec_date  = sy-datum.
      ls_log-message    = |RESTORE INSERT FROM TABLE { lv_tab }: { lv_ins } rows. RC={ lv_ins_rc }|.
      INSERT zsp26_arch_log FROM ls_log.
      COMMIT WORK.
      MESSAGE |Restored { lv_ins } rows into { lv_tab }| TYPE 'S'.
    ENDIF.
  ENDWHILE.

  CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT' EXCEPTIONS OTHERS = 1.

  IF lv_any = abap_false.
    MESSAGE |No data for { p_table } (PUT_TABLE format). Try P_JSON for legacy.| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.

*----------------------------------------------------------------------*
FORM run_read_legacy_json.
  DATA: lv_arch_h_loc TYPE syst-tabix.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
    EXPORTING
      object = 'Z_ARCH_EKK'
    IMPORTING
      archive_handle = lv_arch_h_loc
    EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive for read (legacy).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR lt_disp.
  DO.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_OBJECT'
      EXPORTING
        archive_handle = gv_arch_handle
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
          archive_handle = gv_arch_handle
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
      archive_handle = gv_arch_handle
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
        lo_disp_s TYPE REF TO cl_salv_display_settings.

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

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.

  IF p_rest = 'X'.
    DATA: lv_ok   TYPE i VALUE 0,
          lv_err  TYPE i VALUE 0,
          gr_rec  TYPE REF TO data,
          lv_json TYPE string.

    LOOP AT lt_disp INTO ls_disp.
      CREATE DATA gr_rec TYPE (ls_disp-table_name).
      ASSIGN gr_rec->* TO FIELD-SYMBOL(<rec>).
      TRY.
        lv_json = CONV string( ls_disp-data_json ).
        /ui2/cl_json=>deserialize(
          EXPORTING json = lv_json
          CHANGING  data = <rec> ).
        INSERT (ls_disp-table_name) FROM <rec>.
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
FORM handle_ucomm USING r_ucomm TYPE sy-ucomm rs_selfield TYPE slis_selfield.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f4_arch_cfg_table.
  TYPES: BEGIN OF ty_sht_f4,
           table_name  TYPE tabname,
           description TYPE char80,
         END OF ty_sht_f4.
  DATA lt_sht TYPE STANDARD TABLE OF ty_sht_f4 WITH DEFAULT KEY.

  SELECT table_name, description
    FROM zsp26_arch_cfg
    WHERE is_active = 'X'
    INTO CORRESPONDING FIELDS OF TABLE @lt_sht
    UP TO 999 ROWS.
  IF lt_sht IS INITIAL.
    SELECT table_name, description
      FROM zsp26_arch_cfg
      INTO CORRESPONDING FIELDS OF TABLE @lt_sht
      UP TO 999 ROWS.
  ENDIF.
  SORT lt_sht BY table_name.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'TABLE_NAME'
      window_title = 'Tables in ZSP26_ARCH_CFG'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'P_TABLE'
      value_org    = 'S'
    TABLES
      value_tab    = lt_sht
    EXCEPTIONS
      OTHERS       = 0.

  DATA: lt_df TYPE TABLE OF dynpread,
        ls_df TYPE dynpread.
  CLEAR lt_df.
  ls_df-fieldname = 'P_TABLE'.
  APPEND ls_df TO lt_df.
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING
      dyname     = sy-repid
      dynumb     = sy-dynnr
    TABLES
      dynpfields = lt_df
    EXCEPTIONS
      OTHERS     = 1.
  READ TABLE lt_df INTO ls_df INDEX 1.
  IF sy-subrc = 0 AND ls_df-fieldvalue IS NOT INITIAL.
    p_table = CONV tabname( ls_df-fieldvalue ).
    CONDENSE p_table.
    TRANSLATE p_table TO UPPER CASE.
  ENDIF.
ENDFORM.
