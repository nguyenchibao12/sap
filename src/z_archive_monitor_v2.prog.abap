*&---------------------------------------------------------------------*
*& Report Z_ARCHIVE_MONITOR_V2
*& Phase 5: Monitor & Report — Thống kê archive cho tất cả ZSP26_* tables
*&
*& Cách hoạt động:
*&  1. Chọn chế độ: Summary (theo bảng) hoặc Detail (từng record)
*&  2. Lọc theo bảng, người thực hiện, ngày archive
*&  3. Hiển thị kết quả ALV với nút Refresh
*&---------------------------------------------------------------------*
REPORT z_archive_monitor_v2.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_summary,
         table_name   TYPE tabname,
         cnt_archived TYPE i,
         cnt_restored TYPE i,
         cnt_active   TYPE i,
         last_arch_on TYPE d,
         last_arch_by TYPE xubname,
         last_action  TYPE char10,
       END OF ty_summary.

TYPES: BEGIN OF ty_detail,
         log_id     TYPE sysuuid_x16,
         arch_id    TYPE sysuuid_x16,
         table_name TYPE tabname,
         action     TYPE char10,
         rec_count  TYPE i,
         status     TYPE char1,
         exec_user  TYPE xubname,
         exec_date  TYPE d,
         message    TYPE char255,
         start_time TYPE timestampl,
       END OF ty_detail.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_sum  RADIOBUTTON GROUP g1 DEFAULT 'X' USER-COMMAND umod,
              p_det  RADIOBUTTON GROUP g1.
  SELECTION-SCREEN SKIP.
  SELECT-OPTIONS: s_table FOR zsp26_arch_log-table_name,
                  s_user  FOR zsp26_arch_log-exec_user,
                  s_date  FOR zsp26_arch_log-exec_date.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  TEXT-001 = 'Archive Monitor — ZSP26_*'.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  IF p_sum = 'X'.
    PERFORM show_summary.
  ELSE.
    PERFORM show_detail.
  ENDIF.

*----------------------------------------------------------------------*
FORM show_summary.
*----------------------------------------------------------------------*
  DATA: lt_log   TYPE TABLE OF zsp26_arch_log,
        lt_sum   TYPE TABLE OF ty_summary,
        ls_sum   TYPE ty_summary.

  SELECT * FROM zsp26_arch_log INTO TABLE lt_log
    WHERE table_name IN s_table
      AND exec_user  IN s_user
      AND exec_date  IN s_date
    ORDER BY table_name exec_date DESCENDING.

  LOOP AT lt_log INTO DATA(ls_log).
    READ TABLE lt_sum ASSIGNING FIELD-SYMBOL(<sum>)
      WITH KEY table_name = ls_log-table_name.
    IF sy-subrc <> 0.
      APPEND INITIAL LINE TO lt_sum ASSIGNING <sum>.
      <sum>-table_name = ls_log-table_name.
    ENDIF.

    CASE ls_log-action.
      WHEN 'ARCHIVE'.
        <sum>-cnt_archived = <sum>-cnt_archived + ls_log-rec_count.
      WHEN 'RESTORE'.
        <sum>-cnt_restored = <sum>-cnt_restored + ls_log-rec_count.
    ENDCASE.

    " Luôn cập nhật last action (log đã sort desc date → đầu tiên = mới nhất)
    IF <sum>-last_arch_on IS INITIAL.
      <sum>-last_arch_on = ls_log-exec_date.
      <sum>-last_arch_by = ls_log-exec_user.
      <sum>-last_action  = ls_log-action.
    ENDIF.
  ENDLOOP.

  " Tính cnt_active = archived - restored từ ZSP26_ARCH_DATA
  LOOP AT lt_sum ASSIGNING FIELD-SYMBOL(<s>).
    SELECT COUNT(*) FROM zsp26_arch_data INTO DATA(lv_cnt)
      WHERE table_name = <s>-table_name AND arch_status = 'A'.
    <s>-cnt_active = lv_cnt.
  ENDLOOP.

  IF lt_sum IS INITIAL.
    MESSAGE 'Không có dữ liệu archive nào phù hợp với điều kiện lọc' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " ── SALV Display ──────────────────────────────────────────────────
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_sum ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
      lo_col->set_long_text( 'Table Name' ).

      lo_col ?= lo_cols->get_column( 'CNT_ARCHIVED' ).
      lo_col->set_long_text( 'Total Archived' ).

      lo_col ?= lo_cols->get_column( 'CNT_RESTORED' ).
      lo_col->set_long_text( 'Total Restored' ).

      lo_col ?= lo_cols->get_column( 'CNT_ACTIVE' ).
      lo_col->set_long_text( 'Active in Archive' ).

      lo_col ?= lo_cols->get_column( 'LAST_ARCH_ON' ).
      lo_col->set_long_text( 'Last Activity Date' ).

      lo_col ?= lo_cols->get_column( 'LAST_ARCH_BY' ).
      lo_col->set_long_text( 'Last By' ).

      lo_col ?= lo_cols->get_column( 'LAST_ACTION' ).
      lo_col->set_long_text( 'Last Action' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |ARCHIVE SUMMARY — { lines( lt_sum ) } tables | &&
      |[ Filtered: Table: { s_table[] } / User: { s_user[] } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
FORM show_detail.
*----------------------------------------------------------------------*
  DATA: lt_log  TYPE TABLE OF zsp26_arch_log,
        lt_det  TYPE TABLE OF ty_detail,
        ls_det  TYPE ty_detail.

  SELECT * FROM zsp26_arch_log INTO TABLE lt_log
    WHERE table_name IN s_table
      AND exec_user  IN s_user
      AND exec_date  IN s_date
    ORDER BY exec_date DESCENDING.

  LOOP AT lt_log INTO DATA(ls_log).
    CLEAR ls_det.
    ls_det-log_id     = ls_log-log_id.
    ls_det-arch_id    = ls_log-arch_id.
    ls_det-table_name = ls_log-table_name.
    ls_det-action     = ls_log-action.
    ls_det-rec_count  = ls_log-rec_count.
    ls_det-status     = ls_log-status.
    ls_det-exec_user  = ls_log-exec_user.
    ls_det-exec_date  = ls_log-exec_date.
    ls_det-message    = ls_log-message.
    ls_det-start_time = ls_log-start_time.
    APPEND ls_det TO lt_det.
  ENDLOOP.

  IF lt_det IS INITIAL.
    MESSAGE 'Không có log archive nào phù hợp với điều kiện lọc' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " ── SALV Display ──────────────────────────────────────────────────
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_det ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'LOG_ID' ).
      lo_col->set_visible( abap_false ).

      lo_col ?= lo_cols->get_column( 'ARCH_ID' ).
      lo_col->set_visible( abap_false ).

      lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
      lo_col->set_long_text( 'Table' ).

      lo_col ?= lo_cols->get_column( 'ACTION' ).
      lo_col->set_long_text( 'Action' ).

      lo_col ?= lo_cols->get_column( 'REC_COUNT' ).
      lo_col->set_long_text( 'Records' ).

      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_long_text( 'Status' ).

      lo_col ?= lo_cols->get_column( 'EXEC_USER' ).
      lo_col->set_long_text( 'Executed By' ).

      lo_col ?= lo_cols->get_column( 'EXEC_DATE' ).
      lo_col->set_long_text( 'Date' ).

      lo_col ?= lo_cols->get_column( 'MESSAGE' ).
      lo_col->set_long_text( 'Message' ).

      lo_col ?= lo_cols->get_column( 'START_TIME' ).
      lo_col->set_long_text( 'Start Timestamp' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |ARCHIVE LOG DETAIL — { lines( lt_det ) } entries | &&
      |[ Filtered: Table: { s_table[] } / User: { s_user[] } / Date: { s_date[] } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
