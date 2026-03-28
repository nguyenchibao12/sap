*&---------------------------------------------------------------------*
*& Report Z_CONFIG_Z15_EKKO
*& Mục đích : Quản lý cấu hình Archive cho bảng ZEKKO_15
*&   - Hiển thị danh sách cấu hình hiện tại (Display)
*&   - Thêm mới / Cập nhật cấu hình Retention Rule (Maintain)
*&---------------------------------------------------------------------*
REPORT z_config_z15_ekko.

TABLES: zsp26_arch_cfg.

*----------------------------------------------------------------------*
* Kiểu dữ liệu hiển thị
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_cfg,
         table_name  TYPE zsp26_arch_cfg-table_name,
         description TYPE char80,
         retention   TYPE zsp26_arch_cfg-retention,
         data_field  TYPE zsp26_arch_cfg-data_field,
         is_active   TYPE zsp26_arch_cfg-is_active,
         created_by  TYPE zsp26_arch_cfg-created_by,
         created_on  TYPE zsp26_arch_cfg-created_on,
         changed_by  TYPE zsp26_arch_cfg-changed_by,
         changed_on  TYPE zsp26_arch_cfg-changed_on,
       END OF ty_cfg.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS:
    p_displ TYPE c RADIOBUTTON GROUP rad1 DEFAULT 'X',  " Hiển thị danh sách
    p_maint TYPE c RADIOBUTTON GROUP rad1.               " Thêm / cập nhật
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS:
    p_tabnam TYPE zsp26_arch_cfg-table_name  DEFAULT 'ZEKKO_15',
    p_descr  TYPE char80                     DEFAULT 'Archive config for ZEKKO_15',
    p_ret    TYPE zsp26_arch_cfg-retention   DEFAULT '180',
    p_field  TYPE zsp26_arch_cfg-data_field  DEFAULT 'AEDAT',
    p_activ  TYPE zsp26_arch_cfg-is_active   DEFAULT 'X' AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  IF p_maint = 'X'.
    IF p_tabnam IS INITIAL.
      MESSAGE 'Vui lòng nhập Table Name' TYPE 'E'.
    ENDIF.
    IF p_ret IS INITIAL OR p_ret = 0.
      MESSAGE 'Retention phải lớn hơn 0' TYPE 'E'.
    ENDIF.
    IF p_field IS INITIAL.
      MESSAGE 'Vui lòng nhập Date Field (VD: AEDAT)' TYPE 'E'.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  IF p_displ = 'X'.
    PERFORM display_config.
  ELSE.
    PERFORM save_config.
  ENDIF.

*----------------------------------------------------------------------*
FORM display_config.
*----------------------------------------------------------------------*
  DATA: lt_cfg   TYPE TABLE OF ty_cfg,
        lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lo_funcs TYPE REF TO cl_salv_functions.

  SELECT table_name description retention data_field is_active
         created_by created_on changed_by changed_on
    FROM zsp26_arch_cfg
    INTO TABLE lt_cfg
    ORDER BY table_name.

  IF lt_cfg IS INITIAL.
    MESSAGE 'Chưa có cấu hình nào. Chọn "Maintain" để tạo mới.' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_cfg ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
    lo_col->set_long_text( 'Table Name' ).
    lo_col ?= lo_cols->get_column( 'DESCRIPTION' ).
    lo_col->set_long_text( 'Description' ).
    lo_col ?= lo_cols->get_column( 'RETENTION' ).
    lo_col->set_long_text( 'Retention (days)' ).
    lo_col ?= lo_cols->get_column( 'DATA_FIELD' ).
    lo_col->set_long_text( 'Date Field' ).
    lo_col ?= lo_cols->get_column( 'IS_ACTIVE' ).
    lo_col->set_long_text( 'Active' ).
    lo_col ?= lo_cols->get_column( 'CREATED_BY' ).
    lo_col->set_long_text( 'Created By' ).
    lo_col ?= lo_cols->get_column( 'CREATED_ON' ).
    lo_col->set_long_text( 'Created On' ).
    lo_col ?= lo_cols->get_column( 'CHANGED_BY' ).
    lo_col->set_long_text( 'Changed By' ).
    lo_col ?= lo_cols->get_column( 'CHANGED_ON' ).
    lo_col->set_long_text( 'Changed On' ).

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |Archive Configuration List — { lines( lt_cfg ) } record(s)| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
FORM save_config.
*----------------------------------------------------------------------*
  DATA: ls_cfg  TYPE zsp26_arch_cfg,
        lv_uuid TYPE sysuuid_x16.

  " Kiểm tra đã tồn tại config cho bảng này chưa
  SELECT SINGLE *
    FROM zsp26_arch_cfg
    INTO ls_cfg
    WHERE table_name = p_tabnam.

  IF sy-subrc = 0.
    " Cập nhật bản ghi hiện có
    ls_cfg-description = p_descr.
    ls_cfg-retention   = p_ret.
    ls_cfg-data_field  = p_field.
    ls_cfg-is_active   = p_activ.
    ls_cfg-changed_by  = sy-uname.
    ls_cfg-changed_on  = sy-datum.

    UPDATE zsp26_arch_cfg FROM ls_cfg.

    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      MESSAGE |Đã cập nhật cấu hình cho bảng: { p_tabnam }| TYPE 'S'.
    ELSE.
      ROLLBACK WORK.
      MESSAGE 'Lỗi khi cập nhật cấu hình' TYPE 'E'.
    ENDIF.

  ELSE.
    " Tạo bản ghi mới
    TRY.
      lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      MESSAGE 'Lỗi tạo UUID cho Config ID' TYPE 'E'.
      RETURN.
    ENDTRY.

    CLEAR ls_cfg.
    ls_cfg-config_id   = lv_uuid.
    ls_cfg-table_name  = p_tabnam.
    ls_cfg-description = p_descr.
    ls_cfg-retention   = p_ret.
    ls_cfg-data_field  = p_field.
    ls_cfg-is_active   = p_activ.
    ls_cfg-created_by  = sy-uname.
    ls_cfg-created_on  = sy-datum.
    ls_cfg-changed_by  = sy-uname.
    ls_cfg-changed_on  = sy-datum.

    INSERT zsp26_arch_cfg FROM ls_cfg.

    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      MESSAGE |Đã tạo cấu hình mới cho bảng: { p_tabnam } (Retention: { p_ret } ngày)| TYPE 'S'.
    ELSE.
      ROLLBACK WORK.
      MESSAGE 'Lỗi khi tạo cấu hình mới' TYPE 'E'.
    ENDIF.
  ENDIF.
ENDFORM.
