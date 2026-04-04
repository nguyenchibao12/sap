*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_READ
*& ADK Read/Restore Program — Archive Object Z_ARCH_EKK
*& Reads archive file → displays records, optionally restores to DB
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_read.

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

DATA: ls_arec  TYPE ty_arch_rec,
      lt_disp  TYPE TABLE OF ty_disp,
      ls_disp  TYPE ty_disp,
      g_scr_r0(72) TYPE c.

SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME.
SELECTION-SCREEN COMMENT /1(72) g_scr_r0.
PARAMETERS: p_table TYPE tabname DEFAULT 'ZSP26_EKKO',
            p_rest  TYPE c       AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b0.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  g_scr_r0 = 'F4 = tables in ZSP26_ARCH_CFG. P_REST = restore all filtered rows to DB after list.'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
*----------------------------------------------------------------------*
  PERFORM f4_arch_cfg_table.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  " Open archive for read
  CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
    EXPORTING  archiv_obj = 'Z_ARCH_EKK'
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Không mở được archive Z_ARCH_EKK. Chưa có file archive — hãy chạy Write trước qua SARA.'
            TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " Read all records, filter by table if specified
  DO.
    CLEAR ls_arec.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
      IMPORTING  record      = ls_arec
      EXCEPTIONS end_of_file = 1
                 OTHERS      = 2.
    IF sy-subrc = 1. EXIT.
    ELSEIF sy-subrc > 1. CONTINUE. ENDIF.

    CHECK ls_arec-rec_type = 'D'.
    IF p_table IS NOT INITIAL AND ls_arec-table_name <> p_table. CONTINUE. ENDIF.

    CLEAR ls_disp.
    ls_disp-table_name = ls_arec-table_name.
    ls_disp-key_vals   = ls_arec-key_vals.
    ls_disp-data_json  = ls_arec-data_json.
    APPEND ls_disp TO lt_disp.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT' EXCEPTIONS OTHERS = 1.

  IF lt_disp IS INITIAL.
    MESSAGE |No archived records found for '{ p_table }'| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " Display via SALV
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

    " Set column headers
    TRY. lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
         lo_col->set_long_text( 'Table Name' ). CATCH cx_salv_not_found. ENDTRY.
    TRY. lo_col ?= lo_cols->get_column( 'KEY_VALS' ).
         lo_col->set_long_text( 'Key Values' ). CATCH cx_salv_not_found. ENDTRY.
    TRY. lo_col ?= lo_cols->get_column( 'DATA_JSON' ).
         lo_col->set_visible( abap_false ). CATCH cx_salv_not_found. ENDTRY.

    lo_disp_s = lo_alv->get_display_settings( ).
    lo_disp_s->set_list_header(
      |ARCHIVED RECORDS — { p_table }  [ { lines( lt_disp ) } records ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.

  " Restore ALL records if p_rest = 'X'
  " (SALV is display-only — cannot get row selection after display)
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
          WRITE: / |  WARN: insert failed for { ls_disp-key_vals }|.
        ENDIF.
      CATCH cx_root.
        ADD 1 TO lv_err.
        WRITE: / |  ERROR: deserialize failed for { ls_disp-key_vals }|.
      ENDTRY.
    ENDLOOP.

    IF lv_ok > 0. COMMIT WORK. ENDIF.

    " Log
    DATA: ls_log TYPE zsp26_arch_log,
          lv_log_tab TYPE tabname.
    lv_log_tab = p_table.
    IF lv_log_tab IS INITIAL.
      READ TABLE lt_disp INTO ls_disp INDEX 1.
      IF sy-subrc = 0.
        lv_log_tab = ls_disp-table_name.
      ENDIF.
    ENDIF.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-table_name = lv_log_tab.
    ls_log-action     = 'RESTORE'.
    ls_log-rec_count  = lv_ok.
    ls_log-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    ls_log-message    = |ADK Restore: { lv_ok } records restored to { p_table }. Errors: { lv_err }|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.

    MESSAGE |Restored { lv_ok } records to { p_table }. Errors: { lv_err }| TYPE 'S'.
  ENDIF.

*&---------------------------------------------------------------------*
FORM f4_arch_cfg_table.
  DATA: lt_val TYPE TABLE OF help_value,
        ls_val TYPE help_value.

  SELECT DISTINCT table_name FROM zsp26_arch_cfg
    INTO TABLE @DATA(lt_names)
    WHERE is_active = 'X'
    ORDER BY table_name.

  LOOP AT lt_names INTO DATA(ls_nm).
    CLEAR ls_val.
    ls_val-value = ls_nm-table_name.
    APPEND ls_val TO lt_val.
  ENDLOOP.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'VALUE'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_TABLE'
      value_org       = 'S'
    TABLES
      value_tab       = lt_val
    EXCEPTIONS
      OTHERS          = 2.
ENDFORM.
