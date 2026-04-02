*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_I01  — PAI Modules
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Module F4_TABNAME INPUT  (value request — màn 0100)
*&---------------------------------------------------------------------*
MODULE f4_tabname INPUT.
  DATA: lt_return TYPE TABLE OF ddshretval.

  CALL FUNCTION 'F4IF_FIELD_VALUE_REQUEST'
    EXPORTING
      searchhelp    = 'ZSP26_SH_TABLES'
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
*& Module USER_COMMAND_0100 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0100 INPUT.
  DATA: lv_cmd TYPE sy-ucomm.
  lv_cmd = ok_code.
  CLEAR ok_code.

  CONDENSE gv_tabname.
  TRANSLATE gv_tabname TO UPPER CASE.

  CASE lv_cmd.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.

    WHEN 'BT_WRITE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'E'.
      ELSE.
        PERFORM do_archive_write.
      ENDIF.

    WHEN 'BT_DELETE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'E'.
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
        answer                = lv_ans_chk.
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
    WHEN 'EDIT_BTN'.
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
              answer                = lv_ans_300.
          IF lv_ans_300 = '1'.
            SUBMIT (gv_prog_write) VIA SELECTION-SCREEN AND RETURN.
          ELSE.
            CLEAR gv_variant.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.
    WHEN 'BACK'.
      SET SCREEN 0100. LEAVE SCREEN.
  ENDCASE.
ENDMODULE.
