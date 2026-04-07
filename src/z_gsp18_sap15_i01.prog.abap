*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_I01  — PAI Modules
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Module F4_TABNAME INPUT — màn 0400 (search help ZSP26_SH_TABLES)
*&---------------------------------------------------------------------*
MODULE f4_tabname INPUT.
  DATA: lt_return TYPE TABLE OF ddshretval.

  CALL FUNCTION 'F4IF_FIELD_VALUE_REQUEST'
    EXPORTING
      searchhelp    = 'ZSP26_SH_TABLES'
      tabname       = 'ZSP26_ARCH_CFG'
      fieldname     = 'TABLE_NAME'
      shlpparam     = 'TABLE_NAME'
      dynpprog      = sy-repid
      dynpnr        = sy-dynnr
      dynprofield   = 'GV_TABNAME'
    TABLES
      return_tab    = lt_return
    EXCEPTIONS
      OTHERS        = 1.

  READ TABLE lt_return INTO DATA(ls_ret) INDEX 1.
  IF sy-subrc = 0.
    gv_tabname = CONV tabname( ls_ret-fieldval ).
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0400 INPUT — chọn bảng → Continue → 0100
*&---------------------------------------------------------------------*
MODULE user_command_0400 INPUT.
  DATA: lv_cmd_400 TYPE sy-ucomm.
  lv_cmd_400 = ok_code.
  CLEAR ok_code.

  CONDENSE gv_tabname.
  TRANSLATE gv_tabname TO UPPER CASE.

  CASE lv_cmd_400.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.
    WHEN 'BT_CONTINUE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        SET SCREEN 0100.
        LEAVE SCREEN.
      ENDIF.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0100 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0100 INPUT.
  DATA: lv_cmd TYPE sy-ucomm.
  lv_cmd = ok_code.
  CLEAR ok_code.

  CONDENSE gv_tabname.
  TRANSLATE gv_tabname TO UPPER CASE.

  CASE lv_cmd.
    WHEN 'BACK'.
      SET SCREEN 0400.
      LEAVE SCREEN.
    WHEN 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.

    WHEN 'BT_CHG_TAB'.
      SET SCREEN 0400.
      LEAVE SCREEN.

    WHEN 'BT_WRITE'.
      IF gv_tabname IS INITIAL.
        " TYPE S + DISPLAY LIKE E: cảnh báo giống lỗi nhưng không 'khóa' dynpro như MESSAGE E
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        SET SCREEN 0500.
        LEAVE SCREEN.
      ENDIF.

    WHEN 'BT_DELETE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        PERFORM do_restore_preview.
      ENDIF.

    WHEN 'BT_MONITOR'.
      PERFORM do_monitor.

    WHEN 'BT_MANAGE'.
      PERFORM do_config.

  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0200 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0200 INPUT.
  DATA: lv_cmd_200 TYPE sy-ucomm.
  lv_cmd_200 = ok_code.
  CLEAR ok_code.

  CASE lv_cmd_200.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      IF go_cont_200 IS BOUND.
        go_cont_200->free( ).
        CLEAR: go_cont_200, go_alv_200.
      ENDIF.
      CLEAR gt_arch_stat.
      SET SCREEN 0100. LEAVE SCREEN.

    WHEN 'BT_REFRESH'.
      CLEAR: gt_arch_stat, go_cont_200, go_alv_200.
      PERFORM get_data.
      PERFORM build_fieldcat.
      PERFORM display_alv.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module EXIT_COMMAND INPUT
*&---------------------------------------------------------------------*
MODULE exit_command INPUT.
  CASE sy-ucomm.
    WHEN 'BACK'.
      SET SCREEN 0100. LEAVE SCREEN.
    WHEN 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module CHECK_VARIANT_0300 INPUT
*&---------------------------------------------------------------------*
MODULE check_variant_0300 INPUT.
  DATA: lv_rc_chk  TYPE sy-subrc,
        lv_ans_chk TYPE char1.

  CHECK gv_variant IS NOT INITIAL.
  IF gv_prog_write IS INITIAL. PERFORM get_archive_programs. ENDIF.

  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      report  = gv_prog_write
      variant = gv_variant
    IMPORTING
      r_c     = lv_rc_chk.

  IF lv_rc_chk <> 0.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Thông báo'
        text_question         = 'Variant chưa tồn tại. Tạo mới?'
        text_button_1         = 'Có'
        text_button_2         = 'Không'
        display_cancel_button = ' '
      IMPORTING
        answer                = lv_ans_chk
      EXCEPTIONS
        OTHERS                = 1.
    IF lv_ans_chk = '1'.
      SUBMIT (gv_prog_write) VIA SELECTION-SCREEN AND RETURN.
    ELSE.
      CLEAR gv_variant.
    ENDIF.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0300 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0300 INPUT.
  DATA: lv_rc_300  TYPE sy-subrc,
        lv_ans_300 TYPE char1,
        lv_ucomm   TYPE sy-ucomm.

  lv_ucomm = ok_code.
  CLEAR ok_code.

  CASE lv_ucomm.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      IF gv_variant IS NOT INITIAL.
        CALL FUNCTION 'RS_VARIANT_EXISTS'
          EXPORTING
            report  = gv_prog_write
            variant = gv_variant
          IMPORTING
            r_c     = lv_rc_300.

        IF lv_rc_300 = 0.
          SUBMIT (gv_prog_write) VIA SELECTION-SCREEN
            USING SELECTION-SET gv_variant AND RETURN.
        ELSE.
          CALL FUNCTION 'POPUP_TO_CONFIRM'
            EXPORTING
              titlebar              = 'Thông báo'
              text_question         = 'Variant chưa tồn tại. Tạo mới?'
              text_button_1         = 'Có'
              text_button_2         = 'Không'
              display_cancel_button = ' '
            IMPORTING
              answer                = lv_ans_300
            EXCEPTIONS
              OTHERS                = 1.
          IF lv_ans_300 = '1'.
            SUBMIT (gv_prog_write) VIA SELECTION-SCREEN AND RETURN.
          ELSE.
            CLEAR gv_variant.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'BT_START' OR 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'BT_SPOOL' OR 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.
    WHEN 'BACK'.
      SET SCREEN 0100. LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module F4_GV_VARIANT INPUT — F4 variant theo report write (AOBJ)
*&---------------------------------------------------------------------*
MODULE f4_gv_variant INPUT.
  TYPES: BEGIN OF ty_vf4,
           variant TYPE rvari,
         END OF ty_vf4.
  DATA: lt_vf4 TYPE TABLE OF ty_vf4.

  IF gv_prog_write IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.
  CHECK gv_prog_write IS NOT INITIAL.

  SELECT variant FROM varid
    WHERE report = @gv_prog_write
    INTO TABLE @lt_vf4
    UP TO 500 ROWS.

  IF lt_vf4 IS INITIAL.
    MESSAGE 'No saved variants for this archive write program' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'VARIANT'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'GV_VARIANT'
      window_title = 'Variants'
      value_org    = 'S'
    TABLES
      value_tab    = lt_vf4
    EXCEPTIONS
      OTHERS       = 0.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0500 INPUT — SARA-style Create archive file
*&---------------------------------------------------------------------*
MODULE user_command_0500 INPUT.
  DATA: lv_rc_500  TYPE sy-subrc,
        lv_ans_500 TYPE char1,
        lv_u5      TYPE sy-ucomm.

  lv_u5 = ok_code.
  CLEAR ok_code.

  CASE lv_u5.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      IF gv_variant IS NOT INITIAL.
        CALL FUNCTION 'RS_VARIANT_EXISTS'
          EXPORTING
            report  = gv_prog_write
            variant = gv_variant
          IMPORTING
            r_c     = lv_rc_500.

        IF lv_rc_500 = 0.
          SUBMIT (gv_prog_write) VIA SELECTION-SCREEN
            USING SELECTION-SET gv_variant AND RETURN.
        ELSE.
          CALL FUNCTION 'POPUP_TO_CONFIRM'
            EXPORTING
              titlebar              = 'Thông báo'
              text_question         = 'Variant chưa tồn tại. Tạo mới?'
              text_button_1         = 'Có'
              text_button_2         = 'Không'
              display_cancel_button = ' '
            IMPORTING
              answer                = lv_ans_500
            EXCEPTIONS
              OTHERS                = 1.
          IF lv_ans_500 = '1'.
            SUBMIT (gv_prog_write) VIA SELECTION-SCREEN AND RETURN.
          ELSE.
            CLEAR gv_variant.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'BT_START' OR 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'BT_SPOOL' OR 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.

    WHEN 'BT_PREVIEW'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        PERFORM do_archive_write.
        SET SCREEN 0100.
        LEAVE SCREEN.
      ENDIF.

    WHEN 'BACK'.
      SET SCREEN 0100.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.
