*&---------------------------------------------------------------------*
*& Report Z_ARCHIVE_WRITE_V2
*& Phase 2 + 3: Preview dữ liệu & Archive bất kỳ bảng ZSP26_*
*&
*& Cách hoạt động:
*&  1. Đọc config từ ZSP26_ARCH_CFG (retention, date field)
*&  2. Dynamic SELECT từ bảng được chọn
*&  3. Hiển thị Preview ALV: READY / TOO NEW
*&  4. Nút "Archive Now" → serialize JSON → ZSP26_ARCH_DATA + xóa source
*&---------------------------------------------------------------------*
REPORT z_archive_write_v2.

*----------------------------------------------------------------------*
* Global data
*----------------------------------------------------------------------*
DATA: gs_cfg     TYPE zsp26_arch_cfg,
      gr_all     TYPE REF TO data,
      gr_ready   TYPE REF TO data,
      gv_rdy_cnt TYPE i,
      gv_skp_cnt TYPE i.

FIELD-SYMBOLS: <lt_all>   TYPE ANY TABLE,
               <lt_ready> TYPE ANY TABLE.

TYPES: BEGIN OF ty_prev,
         key_vals TYPE char100,
         date_val TYPE d,
         age_days TYPE i,
         status   TYPE char10,
         detail   TYPE char60,
       END OF ty_prev.

*----------------------------------------------------------------------*
* Event handler — nút Archive Now
*----------------------------------------------------------------------*
CLASS lcl_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_cmd
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

CLASS lcl_handler IMPLEMENTATION.
  METHOD on_cmd.
    IF e_salv_function = 'ARCH_NOW'.
      PERFORM do_archive.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_tabnam TYPE tabname OBLIGATORY.
  SELECTION-SCREEN PUSHBUTTON /1(22) but_prev USER-COMMAND prev.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  but_prev = '@ Preview Data @'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_tabnam.
*----------------------------------------------------------------------*
  " F4 Help: danh sách bảng từ ZSP26_ARCH_CFG
  DATA: lt_f4  TYPE TABLE OF zsp26_arch_cfg,
        lt_ret TYPE ddshretval_t,
        ls_ret TYPE ddshretval.

  SELECT * FROM zsp26_arch_cfg INTO TABLE lt_f4
    WHERE is_active = 'X' ORDER BY table_name.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'TABLE_NAME'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_TABNAM'
      window_title    = 'Select Archive Table'
      value_org       = 'S'
    TABLES
      value_tab       = lt_f4
      return_tab      = lt_ret
    EXCEPTIONS OTHERS = 1.

  READ TABLE lt_ret INTO ls_ret INDEX 1.
  IF sy-subrc = 0. p_tabnam = ls_ret-fieldval. ENDIF.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  IF sy-ucomm = 'PREV'.
    PERFORM load_data.
    IF NOT <lt_all> IS INITIAL.
      PERFORM show_preview.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  PERFORM load_data.
  IF <lt_all> IS INITIAL.
    MESSAGE |Không có dữ liệu trong { p_tabnam }| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
  PERFORM show_preview.

*----------------------------------------------------------------------*
FORM load_data.
*----------------------------------------------------------------------*
  " 1. Đọc cấu hình
  SELECT SINGLE * FROM zsp26_arch_cfg INTO gs_cfg
    WHERE table_name = p_tabnam AND is_active = 'X'.

  IF sy-subrc <> 0.
    MESSAGE |Chưa có config cho '{ p_tabnam }'. Hãy chạy Z_CONFIG_Z15_EKKO trước.| TYPE 'S'
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gs_cfg-data_field IS INITIAL.
    MESSAGE |Config cho { p_tabnam } chưa có Data Field (cột ngày)| TYPE 'S'
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 2. Dynamic SELECT — lấy toàn bộ, phân loại sau
  CREATE DATA gr_all TYPE TABLE OF (p_tabnam).
  ASSIGN gr_all->* TO <lt_all>.

  SELECT * FROM (p_tabnam) INTO TABLE <lt_all>.
ENDFORM.

*----------------------------------------------------------------------*
FORM show_preview.
*----------------------------------------------------------------------*
  DATA: lt_prev TYPE TABLE OF ty_prev,
        ls_prev TYPE ty_prev.

  " READY table — cùng kiểu với source
  CREATE DATA gr_ready TYPE TABLE OF (p_tabnam).
  ASSIGN gr_ready->* TO <lt_ready>.
  CLEAR: gv_rdy_cnt, gv_skp_cnt.

  " Lấy tên key field đầu (để hiển thị trong cột Key)
  DATA: lt_dd   TYPE TABLE OF dfies,
        lv_kfld TYPE string.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = p_tabnam
    TABLES     dfies_tab = lt_dd
    EXCEPTIONS OTHERS    = 1.

  LOOP AT lt_dd INTO DATA(ls_dd)
    WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
    lv_kfld = ls_dd-fieldname.
    EXIT.
  ENDLOOP.

  " Phân loại từng record
  LOOP AT <lt_all> ASSIGNING FIELD-SYMBOL(<row>).
    CLEAR ls_prev.

    ASSIGN COMPONENT lv_kfld OF STRUCTURE <row> TO FIELD-SYMBOL(<kv>).
    IF <kv> IS ASSIGNED. ls_prev-key_vals = <kv>. ENDIF.

    ASSIGN COMPONENT gs_cfg-data_field OF STRUCTURE <row> TO FIELD-SYMBOL(<dt>).
    IF <dt> IS ASSIGNED.
      ls_prev-date_val = <dt>.
      ls_prev-age_days = sy-datum - ls_prev-date_val.
    ENDIF.

    IF ls_prev-age_days >= gs_cfg-retention.
      ls_prev-status = 'READY'.
      ls_prev-detail = |Eligible: { ls_prev-age_days } days ≥ { gs_cfg-retention }d|.
      ADD 1 TO gv_rdy_cnt.
      INSERT <row> INTO TABLE <lt_ready>.
    ELSE.
      ls_prev-status = 'TOO NEW'.
      ls_prev-detail = |Only { ls_prev-age_days } / { gs_cfg-retention } days|.
      ADD 1 TO gv_skp_cnt.
    ENDIF.

    APPEND ls_prev TO lt_prev.
  ENDLOOP.

  " ── SALV Display ──────────────────────────────────────────────────
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_prev ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    " Chỉ hiện nút Archive Now nếu có records READY
    IF gv_rdy_cnt > 0.
      TRY.
        lo_funcs->add_function(
          name     = 'ARCH_NOW'
          icon     = '@2L@'
          text     = 'Archive Now'
          tooltip  = |Move { gv_rdy_cnt } READY records → ZSP26_ARCH_DATA|
          position = if_salv_c_function_position=>right_of_salv_functions ).
      CATCH cx_salv_method_not_supported.
      ENDTRY.
      DATA(lo_ev) = lo_alv->get_event( ).
      SET HANDLER lcl_handler=>on_cmd FOR lo_ev.
    ENDIF.

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'KEY_VALS' ).
      lo_col->set_long_text( |Key ({ lv_kfld })| ).
      lo_col ?= lo_cols->get_column( 'DATE_VAL' ).
      lo_col->set_long_text( |Date ({ gs_cfg-data_field })| ).
      lo_col ?= lo_cols->get_column( 'AGE_DAYS' ).
      lo_col->set_long_text( 'Age (days)' ).
      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_long_text( 'Archive Status' ).
      lo_col ?= lo_cols->get_column( 'DETAIL' ).
      lo_col->set_long_text( 'Detail / Reason' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |PREVIEW — { p_tabnam }  [ Total: { lines( lt_prev ) } | &&
      |  READY: { gv_rdy_cnt }  TOO NEW: { gv_skp_cnt } | &&
      |/ Retention: { gs_cfg-retention }d / Field: { gs_cfg-data_field } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
FORM do_archive.
*----------------------------------------------------------------------*
  IF NOT <lt_ready> IS ASSIGNED OR <lt_ready> IS INITIAL.
    MESSAGE 'Không có records READY' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA: ls_adata   TYPE zsp26_arch_data,
        ls_alog    TYPE zsp26_arch_log,
        lv_arch_id TYPE sysuuid_x16,
        lv_log_id  TYPE sysuuid_x16,
        lv_json    TYPE string,
        lv_ok      TYPE i VALUE 0,
        lv_err     TYPE i VALUE 0,
        lv_seq     TYPE i VALUE 0,
        lv_ts_s    TYPE timestampl.

  TRY.
    lv_arch_id = cl_system_uuid=>create_uuid_x16_static( ).
    lv_log_id  = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error.
    MESSAGE 'Lỗi tạo UUID' TYPE 'E'. RETURN.
  ENDTRY.
  GET TIME STAMP FIELD lv_ts_s.

  " Lấy danh sách key fields
  DATA: lt_dd  TYPE TABLE OF dfies,
        lt_kfs TYPE TABLE OF string.
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = p_tabnam
    TABLES     dfies_tab = lt_dd
    EXCEPTIONS OTHERS    = 1.
  LOOP AT lt_dd INTO DATA(ls_dd) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
    APPEND ls_dd-fieldname TO lt_kfs.
  ENDLOOP.

  LOOP AT <lt_ready> ASSIGNING FIELD-SYMBOL(<row>).
    ADD 1 TO lv_seq.

    " Build key_values (FIELD=VALUE|...)
    DATA: lv_kv TYPE char255, lv_where TYPE string.
    CLEAR: lv_kv, lv_where.
    LOOP AT lt_kfs INTO DATA(lv_kf).
      ASSIGN COMPONENT lv_kf OF STRUCTURE <row> TO FIELD-SYMBOL(<fv>).
      IF <fv> IS ASSIGNED.
        DATA(lv_fv_str) = CONV string( <fv> ).
        IF lv_kv IS NOT INITIAL.   lv_kv    &&= '|'. ENDIF.
        IF lv_where IS NOT INITIAL. lv_where &&= ' AND '. ENDIF.
        lv_kv    &&= lv_kf && '=' && lv_fv_str.
        lv_where &&= lv_kf && ` EQ '` && lv_fv_str && `'`.
      ENDIF.
    ENDLOOP.
    " Thêm MANDT vào WHERE
    lv_where = |MANDT EQ '{ sy-mandt }' AND | && lv_where.

    " Serialize sang JSON
    TRY.
      lv_json = /ui2/cl_json=>serialize( data = <row> ).
    CATCH cx_root.
      lv_json = lv_kv.  " Fallback: chỉ lưu key
    ENDTRY.

    " Insert vào ZSP26_ARCH_DATA
    CLEAR ls_adata.
    ls_adata-arch_id     = lv_arch_id.
    ls_adata-data_seq    = lv_seq.
    ls_adata-table_name  = p_tabnam.
    ls_adata-key_values  = lv_kv.
    ls_adata-data_json   = lv_json.
    ls_adata-archived_on = sy-datum.
    ls_adata-archived_by = sy-uname.
    ls_adata-arch_status = 'A'.
    INSERT zsp26_arch_data FROM ls_adata.

    IF sy-subrc = 0.
      " Xóa khỏi bảng nguồn
      DELETE FROM (p_tabnam) WHERE (lv_where).
      IF sy-subrc = 0.
        ADD 1 TO lv_ok.
      ELSE.
        ADD 1 TO lv_err.
      ENDIF.
    ELSE.
      ADD 1 TO lv_err.
    ENDIF.
  ENDLOOP.

  IF lv_ok > 0. COMMIT WORK AND WAIT. ENDIF.

  " Ghi log
  CLEAR ls_alog.
  ls_alog-log_id     = lv_log_id.
  ls_alog-arch_id    = lv_arch_id.
  ls_alog-config_id  = gs_cfg-config_id.
  ls_alog-table_name = p_tabnam.
  ls_alog-action     = 'ARCHIVE'.
  ls_alog-rec_count  = lv_ok.
  ls_alog-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
  ls_alog-start_time = lv_ts_s.
  GET TIME STAMP FIELD ls_alog-end_time.
  ls_alog-message    = |Archived { lv_ok } records. Errors: { lv_err }|.
  ls_alog-exec_user  = sy-uname.
  ls_alog-exec_date  = sy-datum.
  INSERT zsp26_arch_log FROM ls_alog.
  COMMIT WORK AND WAIT.

  MESSAGE |Archive xong: { lv_ok } records từ { p_tabnam } → ZSP26_ARCH_DATA|
          TYPE 'S'.
ENDFORM.
