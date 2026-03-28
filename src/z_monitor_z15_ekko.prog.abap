*&---------------------------------------------------------------------*
*& Report Z_MONITOR_Z15_EKKO
*& Mục đích : Giám sát và Báo cáo Archive cho ZEKKO_15
*&   - Summary: Thống kê theo Company Code + Doc. Type
*&   - Detail : Chi tiết từng PO với trạng thái Archive eligibility
*&---------------------------------------------------------------------*
REPORT z_monitor_z15_ekko.

TABLES: zekko_15.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_summary,
         bukrs     TYPE zekko_15-bukrs,
         bsart     TYPE zekko_15-bsart,
         cnt_total TYPE i,
         cnt_ready TYPE i,
         cnt_new   TYPE i,
         pct_ready TYPE p LENGTH 4 DECIMALS 1,
         min_date  TYPE d,
         max_date  TYPE d,
       END OF ty_summary.

TYPES: BEGIN OF ty_detail,
         ebeln     TYPE zekko_15-ebeln,
         bukrs     TYPE zekko_15-bukrs,
         bsart     TYPE zekko_15-bsart,
         lifnr     TYPE zekko_15-lifnr,
         aedat     TYPE zekko_15-aedat,
         age_days  TYPE i,
         eligible  TYPE char10,
       END OF ty_detail.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS:
    s_bukrs FOR zekko_15-bukrs,
    s_aedat FOR zekko_15-aedat,
    s_bsart FOR zekko_15-bsart.
  PARAMETERS:
    p_ret TYPE i DEFAULT 180.  " Ngưỡng Retention (ngày)
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS:
    p_sum TYPE c RADIOBUTTON GROUP rpt DEFAULT 'X',  " Summary
    p_det TYPE c RADIOBUTTON GROUP rpt.               " Detail
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  s_aedat-low    = '00010101'.
  s_aedat-high   = sy-datum.
  s_aedat-sign   = 'I'.
  s_aedat-option = 'BT'.
  APPEND s_aedat.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  IF p_ret <= 0.
    MESSAGE 'Retention phải lớn hơn 0 ngày' TYPE 'E'.
  ENDIF.

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
  DATA: lt_raw  TYPE TABLE OF zekko_15,
        ls_raw  TYPE zekko_15,
        lt_sum  TYPE TABLE OF ty_summary,
        lv_total_all TYPE i.

  SELECT * FROM zekko_15
    INTO TABLE lt_raw
    WHERE bukrs IN s_bukrs
      AND aedat IN s_aedat
      AND bsart IN s_bsart.

  IF lt_raw IS INITIAL.
    MESSAGE 'Không có dữ liệu trong khoảng thời gian đã chọn' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT lt_raw INTO ls_raw.
    READ TABLE lt_sum ASSIGNING FIELD-SYMBOL(<sum>)
      WITH KEY bukrs = ls_raw-bukrs bsart = ls_raw-bsart.

    IF sy-subrc <> 0.
      APPEND INITIAL LINE TO lt_sum ASSIGNING <sum>.
      <sum>-bukrs    = ls_raw-bukrs.
      <sum>-bsart    = ls_raw-bsart.
      <sum>-min_date = ls_raw-aedat.
      <sum>-max_date = ls_raw-aedat.
    ENDIF.

    <sum>-cnt_total = <sum>-cnt_total + 1.

    IF sy-datum - ls_raw-aedat >= p_ret.
      <sum>-cnt_ready = <sum>-cnt_ready + 1.
    ELSE.
      <sum>-cnt_new   = <sum>-cnt_new + 1.
    ENDIF.

    IF ls_raw-aedat < <sum>-min_date. <sum>-min_date = ls_raw-aedat. ENDIF.
    IF ls_raw-aedat > <sum>-max_date. <sum>-max_date = ls_raw-aedat. ENDIF.

    IF <sum>-cnt_total > 0.
      <sum>-pct_ready = <sum>-cnt_ready * 100 / <sum>-cnt_total.
    ENDIF.

    lv_total_all = lv_total_all + 1.
  ENDLOOP.

  " Hiển thị SALV
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lo_funcs TYPE REF TO cl_salv_functions.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_sum ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'BUKRS' ).
      lo_col->set_long_text( 'Company Code' ).
      lo_col ?= lo_cols->get_column( 'BSART' ).
      lo_col->set_long_text( 'Doc. Type' ).
      lo_col ?= lo_cols->get_column( 'CNT_TOTAL' ).
      lo_col->set_long_text( 'Total Records' ).
      lo_col ?= lo_cols->get_column( 'CNT_READY' ).
      lo_col->set_long_text( |READY (>={ p_ret }d)| ).
      lo_col ?= lo_cols->get_column( 'CNT_NEW' ).
      lo_col->set_long_text( 'Too New' ).
      lo_col ?= lo_cols->get_column( 'PCT_READY' ).
      lo_col->set_long_text( '% Ready' ).
      lo_col ?= lo_cols->get_column( 'MIN_DATE' ).
      lo_col->set_long_text( 'Oldest Record' ).
      lo_col ?= lo_cols->get_column( 'MAX_DATE' ).
      lo_col->set_long_text( 'Newest Record' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |ARCHIVE MONITOR — ZEKKO_15 | &&
      |[ Total: { lv_total_all } POs | &&
      | / Retention: { p_ret } days ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
FORM show_detail.
*----------------------------------------------------------------------*
  DATA: lt_raw  TYPE TABLE OF zekko_15,
        ls_raw  TYPE zekko_15,
        lt_det  TYPE TABLE OF ty_detail,
        ls_det  TYPE ty_detail.

  SELECT * FROM zekko_15
    INTO TABLE lt_raw
    WHERE bukrs IN s_bukrs
      AND aedat IN s_aedat
      AND bsart IN s_bsart
    ORDER BY bukrs aedat DESCENDING.

  IF lt_raw IS INITIAL.
    MESSAGE 'Không có dữ liệu' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT lt_raw INTO ls_raw.
    CLEAR ls_det.
    ls_det-ebeln    = ls_raw-ebeln.
    ls_det-bukrs    = ls_raw-bukrs.
    ls_det-bsart    = ls_raw-bsart.
    ls_det-lifnr    = ls_raw-lifnr.
    ls_det-aedat    = ls_raw-aedat.
    ls_det-age_days = sy-datum - ls_raw-aedat.

    IF ls_det-age_days >= p_ret.
      ls_det-eligible = 'READY'.
    ELSE.
      ls_det-eligible = 'TOO NEW'.
    ENDIF.

    APPEND ls_det TO lt_det.
  ENDLOOP.

  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lo_funcs TYPE REF TO cl_salv_functions,
        lv_ready TYPE i,
        lv_new   TYPE i.

  LOOP AT lt_det INTO ls_det.
    IF ls_det-eligible = 'READY'. ADD 1 TO lv_ready.
    ELSE.                         ADD 1 TO lv_new. ENDIF.
  ENDLOOP.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_det ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'EBELN' ).
      lo_col->set_long_text( 'Purchase Order' ).
      lo_col ?= lo_cols->get_column( 'BUKRS' ).
      lo_col->set_long_text( 'Company Code' ).
      lo_col ?= lo_cols->get_column( 'BSART' ).
      lo_col->set_long_text( 'Doc. Type' ).
      lo_col ?= lo_cols->get_column( 'LIFNR' ).
      lo_col->set_long_text( 'Supplier' ).
      lo_col ?= lo_cols->get_column( 'AEDAT' ).
      lo_col->set_long_text( 'Entry Date' ).
      lo_col ?= lo_cols->get_column( 'AGE_DAYS' ).
      lo_col->set_long_text( 'Age (days)' ).
      lo_col ?= lo_cols->get_column( 'ELIGIBLE' ).
      lo_col->set_long_text( 'Archive Status' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |DETAIL REPORT — ZEKKO_15 | &&
      |[ Total: { lines( lt_det ) }  | &&
      |READY: { lv_ready }  TOO NEW: { lv_new } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
