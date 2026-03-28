*&---------------------------------------------------------------------*
*& Report Z_ARCHIVE_RESTORE_V2
*& Phase 4: Restore archived records từ ZSP26_ARCH_DATA về bảng nguồn
*&
*& Cách hoạt động:
*&  1. Chọn bảng nguồn (F4 từ ZSP26_ARCH_CFG)
*&  2. Đọc các records đã archive (ARCH_STATUS='A') từ ZSP26_ARCH_DATA
*&  3. Hiển thị Preview ALV: danh sách records với key, ngày archive, người archive
*&  4. Nút "Restore Selected" → deserialize JSON → INSERT vào bảng nguồn
*&     → cập nhật ARCH_STATUS='R' trong ZSP26_ARCH_DATA
*&     → ghi log vào ZSP26_ARCH_LOG
*&---------------------------------------------------------------------*
REPORT z_archive_restore_v2.

*----------------------------------------------------------------------*
* Types & Global data
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_arch_row,
         sel         TYPE c,         " checkbox
         arch_id     TYPE sysuuid_x16,
         data_seq    TYPE i,
         table_name  TYPE tabname,
         key_values  TYPE char255,
         archived_on TYPE d,
         archived_by TYPE xubname,
         arch_status TYPE char1,
         data_json   TYPE string,
       END OF ty_arch_row.

DATA: gt_arch     TYPE TABLE OF ty_arch_row,
      gs_cfg      TYPE zsp26_arch_cfg,
      gv_restored TYPE i,
      gv_errors   TYPE i.

*----------------------------------------------------------------------*
* Event handler — nút Restore
*----------------------------------------------------------------------*
CLASS lcl_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_cmd
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

CLASS lcl_handler IMPLEMENTATION.
  METHOD on_cmd.
    IF e_salv_function = 'RESTORE'.
      PERFORM do_restore.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_tabnam TYPE tabname OBLIGATORY.
  SELECT-OPTIONS: s_archon FOR gs_cfg-retention NO-EXTENSION DEFAULT sy-datum OPTION LE SIGN I.
  SELECTION-SCREEN PUSHBUTTON /1(25) but_prev USER-COMMAND prev.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  but_prev    = '@ Preview Archived Data @'.
  TEXT-001    = 'Archive Restore - ZSP26_*'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_tabnam.
*----------------------------------------------------------------------*
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
      window_title    = 'Select Table to Restore'
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
    PERFORM load_archived_data.
    IF gt_arch IS NOT INITIAL.
      PERFORM show_preview.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  PERFORM load_archived_data.
  IF gt_arch IS INITIAL.
    MESSAGE |Không có records đã archive cho bảng { p_tabnam }| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
  PERFORM show_preview.

*----------------------------------------------------------------------*
FORM load_archived_data.
*----------------------------------------------------------------------*
  CLEAR gt_arch.

  SELECT arch_id data_seq table_name key_values archived_on archived_by arch_status data_json
    FROM zsp26_arch_data
    INTO CORRESPONDING FIELDS OF TABLE gt_arch
    WHERE table_name  = p_tabnam
      AND arch_status = 'A'
    ORDER BY archived_on DESCENDING data_seq ASCENDING.

  IF sy-subrc <> 0.
    MESSAGE |Không tìm thấy records đã archive cho '{ p_tabnam }'| TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
FORM show_preview.
*----------------------------------------------------------------------*
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lo_sel   TYPE REF TO cl_salv_selections.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = gt_arch ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    " Nút Restore
    TRY.
      lo_funcs->add_function(
        name     = 'RESTORE'
        icon     = '@49@'
        text     = 'Restore Selected'
        tooltip  = |Restore records được chọn về { p_tabnam }|
        position = if_salv_c_function_position=>right_of_salv_functions ).
    CATCH cx_salv_method_not_supported.
    ENDTRY.

    DATA(lo_ev) = lo_alv->get_event( ).
    SET HANDLER lcl_handler=>on_cmd FOR lo_ev.

    " Bật checkbox
    lo_sel = lo_alv->get_selections( ).
    lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'SEL' ).
      lo_col->set_long_text( 'Select' ).
      lo_col->set_medium_text( 'Sel' ).
      lo_col->set_short_text( 'S' ).

      lo_col ?= lo_cols->get_column( 'ARCH_ID' ).
      lo_col->set_visible( abap_false ).

      lo_col ?= lo_cols->get_column( 'DATA_JSON' ).
      lo_col->set_visible( abap_false ).

      lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
      lo_col->set_long_text( 'Source Table' ).

      lo_col ?= lo_cols->get_column( 'KEY_VALUES' ).
      lo_col->set_long_text( 'Key Values' ).

      lo_col ?= lo_cols->get_column( 'DATA_SEQ' ).
      lo_col->set_long_text( 'Seq #' ).

      lo_col ?= lo_cols->get_column( 'ARCHIVED_ON' ).
      lo_col->set_long_text( 'Archived On' ).

      lo_col ?= lo_cols->get_column( 'ARCHIVED_BY' ).
      lo_col->set_long_text( 'Archived By' ).

      lo_col ?= lo_cols->get_column( 'ARCH_STATUS' ).
      lo_col->set_long_text( 'Status' ).

    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |ARCHIVED RECORDS — { p_tabnam }  [ Total: { lines( gt_arch ) } records ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
FORM do_restore.
*----------------------------------------------------------------------*
  IF gt_arch IS INITIAL.
    MESSAGE 'Không có records để restore' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " Lấy bảng đích (target table type cho deserialization)
  DATA: gr_rec      TYPE REF TO data,
        ls_alog     TYPE zsp26_arch_log,
        lv_log_id   TYPE sysuuid_x16,
        lv_arch_id  TYPE sysuuid_x16,
        lv_ts_s     TYPE timestampl.

  TRY.
    lv_log_id  = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error.
    MESSAGE 'Lỗi tạo UUID' TYPE 'E'. RETURN.
  ENDTRY.
  GET TIME STAMP FIELD lv_ts_s.

  " Tạo instance của row-type để deserialize vào
  CREATE DATA gr_rec TYPE (p_tabnam).
  ASSIGN gr_rec->* TO FIELD-SYMBOL(<rec>).

  CLEAR: gv_restored, gv_errors.

  LOOP AT gt_arch ASSIGNING FIELD-SYMBOL(<arch>).
    " Chỉ restore records đã được chọn (SEL = 'X') HOẶC tất cả nếu không có gì được chọn
    " Logic: nếu user không tích gì → restore tất cả; nếu có tích → chỉ restore tích
    DATA(lv_any_sel) = abap_false.
    LOOP AT gt_arch ASSIGNING FIELD-SYMBOL(<chk>).
      IF <chk>-sel = 'X'. lv_any_sel = abap_true. EXIT. ENDIF.
    ENDLOOP.

    IF lv_any_sel = abap_true AND <arch>-sel <> 'X'.
      CONTINUE.
    ENDIF.

    IF <arch>-data_json IS INITIAL.
      ADD 1 TO gv_errors.
      CONTINUE.
    ENDIF.

    " Deserialize JSON → structure
    TRY.
      /ui2/cl_json=>deserialize(
        EXPORTING json = <arch>-data_json
        CHANGING  data = <rec> ).
    CATCH cx_root.
      ADD 1 TO gv_errors.
      CONTINUE.
    ENDTRY.

    " Insert vào bảng nguồn (INSERT … ACCEPTING DUPLICATE KEYS để không dump nếu đã có)
    INSERT (<arch>-table_name) FROM <rec>.

    IF sy-subrc = 0.
      " Cập nhật ARCH_STATUS → 'R' (Restored)
      UPDATE zsp26_arch_data
        SET arch_status = 'R'
        WHERE arch_id  = <arch>-arch_id
          AND data_seq = <arch>-data_seq.

      <arch>-arch_status = 'R'.
      ADD 1 TO gv_restored.
      lv_arch_id = <arch>-arch_id.   " lưu arch_id cuối để log
    ELSE.
      ADD 1 TO gv_errors.
    ENDIF.

  ENDLOOP.

  IF gv_restored > 0. COMMIT WORK AND WAIT. ENDIF.

  " Ghi log
  CLEAR ls_alog.
  TRY.
    lv_log_id = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error.
  ENDTRY.

  ls_alog-log_id     = lv_log_id.
  ls_alog-arch_id    = lv_arch_id.
  ls_alog-table_name = p_tabnam.
  ls_alog-action     = 'RESTORE'.
  ls_alog-rec_count  = gv_restored.
  ls_alog-status     = COND #( WHEN gv_errors = 0 THEN 'S' ELSE 'W' ).
  ls_alog-start_time = lv_ts_s.
  GET TIME STAMP FIELD ls_alog-end_time.
  ls_alog-message    = |Restored { gv_restored } records to { p_tabnam }. Errors: { gv_errors }|.
  ls_alog-exec_user  = sy-uname.
  ls_alog-exec_date  = sy-datum.
  INSERT zsp26_arch_log FROM ls_alog.
  COMMIT WORK AND WAIT.

  MESSAGE |Restore xong: { gv_restored } records về { p_tabnam }. Lỗi: { gv_errors }|
          TYPE 'S'.
ENDFORM.
