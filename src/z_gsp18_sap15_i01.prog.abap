*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_I01  — PAI Modules
*&---------------------------------------------------------------------*

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
        gv_hub_allowed = abap_true.
        " Đồng bộ P_TABLE khi mở Z_ARCH_EKK_WRITE (SE38/SARA hoặc SUBMIT chưa truyền WITH)
        EXPORT arch_tabname = gv_tabname TO MEMORY ID 'Z_GSP18_ARCH_TAB'.
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
      gv_hub_allowed = abap_false.
      SET SCREEN 0400.
      LEAVE SCREEN.
    WHEN 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.

    WHEN 'BT_CHG_TAB'.
      gv_hub_allowed = abap_false.
      CLEAR gv_variant.
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

    WHEN 'BT_RESTORE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        PERFORM do_restore_preview.
      ENDIF.

    WHEN 'BT_ADK_DELETE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        SET SCREEN 0600.
        LEAVE SCREEN.
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
  DATA: lv_rc_chk   TYPE sy-subrc,
        lv_ans_chk  TYPE char1,
        lv_vtech_c  TYPE variant,
        lv_vok_c    TYPE abap_bool,
        lv_ok_c     TYPE abap_bool,
        lv_q_c      TYPE string.

  CHECK gv_variant IS NOT INITIAL.
  IF gv_tabname IS INITIAL.
    MESSAGE 'Chọn bảng archive trước khi dùng Variant' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF gv_prog_write IS INITIAL. PERFORM get_archive_programs. ENDIF.

  PERFORM arch_build_write_var_tech
    USING gv_tabname gv_variant
    CHANGING lv_vtech_c lv_vok_c.
  IF lv_vok_c = abap_false.
    MESSAGE 'Tên Variant (ID) không hợp lệ hoặc quá dài so với tên bảng (max 14 ký tự SAP).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      report  = gv_prog_write
      variant = lv_vtech_c
    IMPORTING
      r_c     = lv_rc_chk.

  IF lv_rc_chk <> 0.
    lv_q_c = |Chưa có variant cho bảng { gv_tabname }. Giữ nguyên ô Variant "{ gv_variant }" (không đổi sang tên kỹ thuật). Tên lưu trong SAP: { lv_vtech_c }. Tạo mới?|.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Thông báo'
        text_question         = lv_q_c
        text_button_1         = 'Có'
        text_button_2         = 'Không'
        display_cancel_button = ' '
      IMPORTING
        answer                = lv_ans_chk
      EXCEPTIONS
        OTHERS                = 1.
    IF lv_ans_chk = '1'.
      PERFORM arch_ensure_write_variant
        USING gv_prog_write lv_vtech_c gv_tabname
        CHANGING lv_ok_c.
      IF lv_ok_c = abap_false.
        MESSAGE |Không tạo được variant SAP "{ lv_vtech_c }". Kiểm tra quyền variant cho report { gv_prog_write }.|
          TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      SUBMIT (gv_prog_write)
        WITH p_table = gv_tabname
        USING SELECTION-SET lv_vtech_c
        VIA SELECTION-SCREEN
        AND RETURN.
    ELSE.
      CLEAR gv_variant.
    ENDIF.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0300 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0300 INPUT.
  DATA: lv_rc_300    TYPE sy-subrc,
        lv_ans_300   TYPE char1,
        lv_ucomm     TYPE sy-ucomm,
        lv_vtech_300 TYPE variant,
        lv_vok_300   TYPE abap_bool,
        lv_ok_300    TYPE abap_bool,
        lv_q_300     TYPE string.

  lv_ucomm = ok_code.
  CLEAR ok_code.

  CASE lv_ucomm.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      IF gv_variant IS NOT INITIAL.
        IF gv_tabname IS INITIAL.
          MESSAGE 'Chọn bảng archive trước khi chỉnh Variant' TYPE 'S' DISPLAY LIKE 'E'.
        ELSE.
          IF gv_prog_write IS INITIAL.
            PERFORM get_archive_programs.
          ENDIF.
          PERFORM arch_build_write_var_tech
            USING gv_tabname gv_variant
            CHANGING lv_vtech_300 lv_vok_300.
          IF lv_vok_300 = abap_false.
            MESSAGE 'Tên Variant (ID) không hợp lệ hoặc quá dài.' TYPE 'S' DISPLAY LIKE 'E'.
          ELSE.
            CALL FUNCTION 'RS_VARIANT_EXISTS'
              EXPORTING
                report  = gv_prog_write
                variant = lv_vtech_300
              IMPORTING
                r_c     = lv_rc_300.

            IF lv_rc_300 = 0.
              SUBMIT (gv_prog_write)
                WITH p_table = gv_tabname
                USING SELECTION-SET lv_vtech_300
                VIA SELECTION-SCREEN
                AND RETURN.
            ELSE.
              lv_q_300 = |Variant chưa tồn tại. Ô Variant giữ "{ gv_variant }". Tên trong SAP: { lv_vtech_300 } (chỉ tham khảo). Tạo mới?|.
              CALL FUNCTION 'POPUP_TO_CONFIRM'
                EXPORTING
                  titlebar              = 'Thông báo'
                  text_question         = lv_q_300
                  text_button_1         = 'Có'
                  text_button_2         = 'Không'
                  display_cancel_button = ' '
                IMPORTING
                  answer                = lv_ans_300
                EXCEPTIONS
                  OTHERS                = 1.
              IF lv_ans_300 = '1'.
                PERFORM arch_ensure_write_variant
                  USING gv_prog_write lv_vtech_300 gv_tabname
                  CHANGING lv_ok_300.
                IF lv_ok_300 = abap_false.
                  MESSAGE |Không tạo được variant SAP "{ lv_vtech_300 }". Kiểm tra quyền variant.|
                    TYPE 'S' DISPLAY LIKE 'E'.
                  RETURN.
                ENDIF.
                SUBMIT (gv_prog_write)
                  WITH p_table = gv_tabname
                  USING SELECTION-SET lv_vtech_300
                  VIA SELECTION-SCREEN
                  AND RETURN.
              ELSE.
                CLEAR gv_variant.
              ENDIF.
            ENDIF.
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
  TYPES: ty_varid_name TYPE c LENGTH 14, " VARID-VARIANT / RVARI độ dài chuẩn
         BEGIN OF ty_vf4,
           variant TYPE variant,
         END OF ty_vf4.
  DATA: lt_vf4    TYPE TABLE OF ty_vf4,
        lt_raw    TYPE TABLE OF ty_varid_name,
        ls_vf4    TYPE ty_vf4,
        lv_r      TYPE ty_varid_name,
        lv_s      TYPE string,
        lv_tab_s  TYPE string,
        lv_log    TYPE variant,
        lv_ok     TYPE abap_bool,
        lv_pfx    TYPE string,
        lv_pat    TYPE string,
        lv_tab_up TYPE tabname,
        lv_rep    TYPE programm.

  IF sy-dynnr = '0600'.
    IF gv_prog_del IS INITIAL.
      PERFORM get_archive_programs.
    ENDIF.
    lv_rep = gv_prog_del.
  ELSE.
    IF gv_prog_write IS INITIAL.
      PERFORM get_archive_programs.
    ENDIF.
    lv_rep = gv_prog_write.
  ENDIF.
  CHECK lv_rep IS NOT INITIAL.

  IF gv_tabname IS INITIAL.
    MESSAGE 'Chọn bảng archive trước (F4 Variant theo từng bảng)' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  SELECT variant FROM varid
    WHERE report = @lv_rep
    INTO TABLE @lt_raw
    UP TO 500 ROWS.

  PERFORM arch_variant_tab_prefix USING gv_tabname CHANGING lv_pfx.
  " CP dùng * làm wildcard; không dùng % như SQL LIKE
  lv_pat = |{ lv_pfx }_*|.
  lv_tab_up = gv_tabname.
  TRANSLATE lv_tab_up TO UPPER CASE.
  lv_tab_s = CONV string( lv_tab_up ).
  CONDENSE lv_tab_s NO-GAPS.

  LOOP AT lt_raw INTO lv_r.
    CLEAR ls_vf4.
    lv_s = lv_r.
    CONDENSE lv_s NO-GAPS.

    IF lv_s = lv_tab_s.
      ls_vf4-variant = CONV variant( lv_s ).
      APPEND ls_vf4 TO lt_vf4.
      CONTINUE.
    ENDIF.
    IF NOT lv_s CP lv_pat.
      CONTINUE.
    ENDIF.
    PERFORM arch_log_from_write_var
      USING gv_tabname lv_s
      CHANGING lv_log lv_ok.
    IF lv_ok = abap_true.
      ls_vf4-variant = lv_log.
    ELSE.
      ls_vf4-variant = CONV variant( lv_s ).
    ENDIF.
    APPEND ls_vf4 TO lt_vf4.
  ENDLOOP.

  SORT lt_vf4 BY variant.
  DELETE ADJACENT DUPLICATES FROM lt_vf4 COMPARING variant.

  IF lt_vf4 IS INITIAL.
    MESSAGE 'Chưa có variant cho bảng này (PREFIX_ID trên VARID) hoặc chưa có cho report' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'VARIANT'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'GV_VARIANT'
      window_title = 'Variants (theo bảng hiện tại)'
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
  DATA: lv_rc_500    TYPE sy-subrc,
        lv_ans_500   TYPE char1,
        lv_u5        TYPE sy-ucomm,
        lv_vtech_500 TYPE variant,
        lv_vok_500   TYPE abap_bool,
        lv_ok_500    TYPE abap_bool,
        lv_q_500     TYPE string.

  lv_u5 = ok_code.
  CLEAR ok_code.

  CASE lv_u5.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      IF gv_variant IS NOT INITIAL.
        IF gv_tabname IS INITIAL.
          MESSAGE 'Chọn bảng archive trước khi chỉnh Variant' TYPE 'S' DISPLAY LIKE 'E'.
        ELSE.
          IF gv_prog_write IS INITIAL.
            PERFORM get_archive_programs.
          ENDIF.
          PERFORM arch_build_write_var_tech
            USING gv_tabname gv_variant
            CHANGING lv_vtech_500 lv_vok_500.
          IF lv_vok_500 = abap_false.
            MESSAGE 'Tên Variant (ID) không hợp lệ hoặc quá dài.' TYPE 'S' DISPLAY LIKE 'E'.
          ELSE.
            CALL FUNCTION 'RS_VARIANT_EXISTS'
              EXPORTING
                report  = gv_prog_write
                variant = lv_vtech_500
              IMPORTING
                r_c     = lv_rc_500.

            IF lv_rc_500 = 0.
              SUBMIT (gv_prog_write)
                WITH p_table = gv_tabname
                USING SELECTION-SET lv_vtech_500
                VIA SELECTION-SCREEN
                AND RETURN.
            ELSE.
              lv_q_500 = |Variant chưa tồn tại. Ô Variant giữ "{ gv_variant }". Tên trong SAP: { lv_vtech_500 } (chỉ tham khảo). Tạo mới?|.
              CALL FUNCTION 'POPUP_TO_CONFIRM'
                EXPORTING
                  titlebar              = 'Thông báo'
                  text_question         = lv_q_500
                  text_button_1         = 'Có'
                  text_button_2         = 'Không'
                  display_cancel_button = ' '
                IMPORTING
                  answer                = lv_ans_500
                EXCEPTIONS
                  OTHERS                = 1.
              IF lv_ans_500 = '1'.
                PERFORM arch_ensure_write_variant
                  USING gv_prog_write lv_vtech_500 gv_tabname
                  CHANGING lv_ok_500.
                IF lv_ok_500 = abap_false.
                  MESSAGE |Không tạo được variant SAP "{ lv_vtech_500 }". Kiểm tra quyền variant.|
                    TYPE 'S' DISPLAY LIKE 'E'.
                  RETURN.
                ENDIF.
                SUBMIT (gv_prog_write)
                  WITH p_table = gv_tabname
                  USING SELECTION-SET lv_vtech_500
                  VIA SELECTION-SCREEN
                  AND RETURN.
              ELSE.
                CLEAR gv_variant.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'BT_START' OR 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'BT_SPOOL' OR 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.

    WHEN 'BT_PREVIEW' OR 'ONLI'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_start_date <> 'X'.
        MESSAGE 'Chưa maintain Start Date. Vào Start Date để khai báo trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_spool_set <> 'X'.
        MESSAGE 'Chưa maintain Spool Parameters. Vào Spool Parameters trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
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

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0600 INPUT — SARA-style Delete (archive DB)
*&---------------------------------------------------------------------*
MODULE user_command_0600 INPUT.
  DATA: lv_rc_600  TYPE sy-subrc,
        lv_ans_600 TYPE char1,
        lv_u6      TYPE sy-ucomm.

  lv_u6 = ok_code.
  CLEAR ok_code.

  CASE lv_u6.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      IF gv_variant IS NOT INITIAL.
        IF gv_prog_del IS INITIAL.
          PERFORM get_archive_programs.
        ENDIF.
        IF gv_prog_del IS INITIAL.
          RETURN.
        ENDIF.
        CALL FUNCTION 'RS_VARIANT_EXISTS'
          EXPORTING
            report  = gv_prog_del
            variant = gv_variant
          IMPORTING
            r_c     = lv_rc_600.

        IF lv_rc_600 = 0.
          SUBMIT (gv_prog_del) VIA SELECTION-SCREEN
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
              answer                = lv_ans_600
            EXCEPTIONS
              OTHERS                = 1.
          IF lv_ans_600 = '1'.
            SUBMIT (gv_prog_del) VIA SELECTION-SCREEN AND RETURN.
          ELSE.
            CLEAR gv_variant.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'BT_ARCH_SEL'.
      PERFORM arch_del_pick_session_popup.

    WHEN 'BT_START' OR 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'BT_SPOOL' OR 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.

    WHEN 'BT_RUN_DELETE'.
      PERFORM do_archive_delete_job.

    WHEN 'BACK'.
      SET SCREEN 0100.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.
