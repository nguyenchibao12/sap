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
         sel        TYPE c LENGTH 1,
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_disp.

DATA: ls_arec  TYPE ty_arch_rec,
      lt_disp  TYPE TABLE OF ty_disp,
      ls_disp  TYPE ty_disp.

PARAMETERS: p_table TYPE tabname  DEFAULT 'ZSP26_EKKO',
            p_rest  TYPE c        AS CHECKBOX DEFAULT ' '.

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
      IMPORTING  record     = ls_arec
      EXCEPTIONS end_of_file = 1
                 OTHERS      = 2.
    IF sy-subrc = 1. EXIT.
    ELSEIF sy-subrc > 1. CONTINUE. ENDIF.

    CHECK ls_arec-rec_type = 'D'.
    IF p_table IS NOT INITIAL AND ls_arec-table_name <> p_table. CONTINUE. ENDIF.

    CLEAR ls_disp.
    ls_disp-sel        = ' '.
    ls_disp-table_name = ls_arec-table_name.
    ls_disp-key_vals   = ls_arec-key_vals.
    ls_disp-data_json  = ls_arec-data_json.
    APPEND ls_disp TO lt_disp.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT' EXCEPTIONS OTHERS = 1.

  IF lt_disp IS INITIAL.
    MESSAGE |Không có records trong archive cho '{ p_table }'| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " Display via SALV
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp_s TYPE REF TO cl_salv_display_settings,
        lo_sel   TYPE REF TO cl_salv_selections.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_disp ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_sel = lo_alv->get_selections( ).
    lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'DATA_JSON' ).
      lo_col->set_visible( abap_false ).
    CATCH cx_salv_not_found. ENDTRY.

    lo_disp_s = lo_alv->get_display_settings( ).
    lo_disp_s->set_list_header(
      |ARCHIVED RECORDS — { p_table }  [ { lines( lt_disp ) } records ]| ).

    lo_alv->display( ).
  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.

  " Restore selected records if checkbox ticked
  IF p_rest = 'X'.
    DATA: lv_ok  TYPE i VALUE 0,
          lv_err TYPE i VALUE 0,
          gr_rec TYPE REF TO data,
          lv_any_sel TYPE abap_bool VALUE abap_false.

    LOOP AT lt_disp TRANSPORTING NO FIELDS WHERE sel = 'X'.
      lv_any_sel = abap_true.
      EXIT.
    ENDLOOP.
    IF lv_any_sel = abap_false.
      LOOP AT lt_disp ASSIGNING FIELD-SYMBOL(<ls_row>).
        <ls_row>-sel = 'X'.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_disp INTO ls_disp WHERE sel = 'X'.
      CREATE DATA gr_rec TYPE (ls_disp-table_name).
      ASSIGN gr_rec->* TO FIELD-SYMBOL(<rec>).
      TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json = ls_disp-data_json
          CHANGING  data = <rec> ).
        INSERT (ls_disp-table_name) FROM <rec>.
        IF sy-subrc = 0. ADD 1 TO lv_ok. ELSE. ADD 1 TO lv_err. ENDIF.
      CATCH cx_root.
        ADD 1 TO lv_err.
      ENDTRY.
    ENDLOOP.

    IF lv_ok > 0. COMMIT WORK. ENDIF.

    " Log
    DATA: ls_log TYPE zsp26_arch_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-action    = 'RESTORE'.
    ls_log-rec_count = lv_ok.
    ls_log-status    = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-exec_user = sy-uname.
    ls_log-exec_date = sy-datum.
    ls_log-message   = |ADK Restore: { lv_ok } records restored to { p_table }. Errors: { lv_err }|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.

    MESSAGE |Restored { lv_ok } records. Errors: { lv_err }| TYPE 'S'.
  ENDIF.
