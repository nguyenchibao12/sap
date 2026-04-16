*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_I01  — PAI Modules
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0400 INPUT — chọn bảng → Continue → 0100
*&---------------------------------------------------------------------*
MODULE user_command_0400 INPUT.
  DATA: lv_cmd_400    TYPE sy-ucomm,
        lv_adm_0400_i TYPE abap_bool.
  lv_cmd_400 = ok_code.
  CLEAR ok_code.

  CONDENSE gv_tabname.
  TRANSLATE gv_tabname TO UPPER CASE.
  PERFORM is_arch_admin CHANGING lv_adm_0400_i.

  CASE lv_cmd_400.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0400.
      LEAVE SCREEN.
    WHEN 'BT_CONTINUE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        gv_hub_allowed = abap_true.
        IF lv_adm_0400_i = abap_true.
          CLEAR gv_admin_pick_table.
        ENDIF.
        EXPORT arch_tabname = gv_tabname TO MEMORY ID 'Z_GSP18_ARCH_TAB'.
        SET SCREEN 0100.
        LEAVE SCREEN.
      ENDIF.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module F4_GV_TABNAME INPUT — POV màn 0400: hiện nút F4 + cùng nguồn ZSP26_ARCH_CFG
*&---------------------------------------------------------------------*
MODULE f4_gv_tabname INPUT.
  PERFORM f4_gv_tabname_dynp.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0100 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0100 INPUT.
  DATA: lv_cmd      TYPE sy-ucomm,
        lv_is_admin TYPE abap_bool.
  lv_cmd = ok_code.
  CLEAR ok_code.

  CONDENSE gv_tabname.
  TRANSLATE gv_tabname TO UPPER CASE.
  PERFORM is_arch_admin CHANGING lv_is_admin.
  CLEAR gv_full_restore.

  CASE lv_cmd.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0100.
      LEAVE SCREEN.
    WHEN 'BACK'.
      gv_hub_allowed = abap_false.
      SET SCREEN 0400.
      LEAVE SCREEN.
    WHEN 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.

    WHEN 'BT_CHG_TAB'.
      gv_hub_allowed = abap_false.
      CLEAR gv_variant.
      IF lv_is_admin = abap_true.
        gv_admin_pick_table = 'X'.
      ENDIF.
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
      IF gv_tabname IS INITIAL AND lv_is_admin = abap_false.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        PERFORM do_restore_menu.
      ENDIF.

    WHEN 'BT_ADK_DELETE'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        SET SCREEN 0600.
        LEAVE SCREEN.
      ENDIF.

    WHEN 'BT_MONITOR'.
      PERFORM do_monitor_menu.

    WHEN 'BT_MANAGE'.
      IF lv_is_admin = abap_true.
        PERFORM do_config.
      ELSE.
        MESSAGE 'Chỉ admin mới được mở Config.' TYPE 'S' DISPLAY LIKE 'E'.
      ENDIF.

    WHEN 'BT_ADMIN'.
      IF lv_is_admin = abap_true.
        CLEAR gv_adm_pick.
        SET SCREEN 0700.
        LEAVE SCREEN.
      ELSE.
        MESSAGE 'Chỉ admin mới được mở quản lý Admin.' TYPE 'S' DISPLAY LIKE 'E'.
      ENDIF.

    WHEN 'BT_RUN_LOG'.
      PERFORM show_hub_run_diagnostics.

    WHEN 'BT_RUN_SESS'.
      PERFORM show_hub_admi_session_groups.

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

  DATA lv_vlog_chk TYPE string.
  lv_vlog_chk = gv_variant.
  TRANSLATE lv_vlog_chk TO UPPER CASE.
  CONDENSE lv_vlog_chk NO-GAPS.
  IF lv_vlog_chk = 'DEFAULT'.
    MESSAGE |"DEFAULT" là tên dành cho variant hệ thống. Dùng tên khác (vd VAR_01).| TYPE 'S' DISPLAY LIKE 'W'.
    CLEAR gv_variant.
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

  IF lv_rc_chk = 0.
    DATA: lt_vc_chk TYPE TABLE OF rsparams.
    FIELD-SYMBOLS <vc_chk> TYPE rsparams.
    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report  = gv_prog_write
        variant = lv_vtech_c
      TABLES
        valutab = lt_vc_chk
      EXCEPTIONS
        OTHERS  = 99.
    IF sy-subrc = 0.
      READ TABLE lt_vc_chk ASSIGNING <vc_chk> WITH KEY selname = 'P_TABLE'.
      IF sy-subrc = 0 AND <vc_chk>-low IS NOT INITIAL.
        DATA lv_vc_tab TYPE tabname.
        lv_vc_tab = <vc_chk>-low.
        CONDENSE lv_vc_tab.
        TRANSLATE lv_vc_tab TO UPPER CASE.
        DATA lv_vc_cur TYPE tabname.
        lv_vc_cur = gv_tabname.
        CONDENSE lv_vc_cur.
        TRANSLATE lv_vc_cur TO UPPER CASE.
        IF lv_vc_tab <> lv_vc_cur.
          MESSAGE |Variant { lv_vtech_c } chứa P_TABLE={ lv_vc_tab } nhưng bảng hiện tại là { lv_vc_cur }. Kiểm tra lại.| TYPE 'S' DISPLAY LIKE 'E'.
          CLEAR gv_variant.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_rc_chk <> 0.
    lv_q_c = |Chưa có variant { lv_vtech_c } cho bảng { gv_tabname }. Tạo mới?|.
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
      PERFORM arch_submit_wvar_ss USING lv_vtech_c.
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
    WHEN 'BT_REFRESH'.
      SET SCREEN 0300.
      LEAVE SCREEN.
    WHEN 'ONLI'.
      MESSAGE 'Execute (F8) chỉ dùng ở màn Write.' TYPE 'S' DISPLAY LIKE 'W'.

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
              PERFORM arch_submit_wvar_ss USING lv_vtech_300.
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
                PERFORM arch_submit_wvar_ss USING lv_vtech_300.
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
        lv_log    TYPE variant,
        lv_ok     TYPE abap_bool,
        lv_rep    TYPE programm,
        lv_off    TYPE i,
        lv_vtech  TYPE variant.

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

  LOOP AT lt_raw INTO lv_r.
    CLEAR ls_vf4.
    lv_s = lv_r.
    CONDENSE lv_s NO-GAPS.
    TRANSLATE lv_s TO UPPER CASE.
    IF lv_s IS INITIAL.
      CONTINUE.
    ENDIF.

    FIND FIRST OCCURRENCE OF '_' IN lv_s MATCH OFFSET lv_off.
    IF sy-subrc <> 0 OR lv_off <= 0 OR lv_off >= strlen( lv_s ) - 1.
      CONTINUE.
    ENDIF.

    lv_log = substring( val = lv_s off = lv_off + 1 ).
    PERFORM arch_build_write_var_tech
      USING gv_tabname lv_log
      CHANGING lv_vtech lv_ok.
    IF lv_ok = abap_false OR lv_vtech <> lv_s.
      CONTINUE.
    ENDIF.

    ls_vf4-variant = lv_log.
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
*& Module USER_COMMAND_0500 INPUT — ADK create archive file (session UI)
*&---------------------------------------------------------------------*
MODULE user_command_0500 INPUT.
  DATA lv_u5 TYPE sy-ucomm.

  lv_u5 = ok_code.
  CLEAR ok_code.

  CASE lv_u5.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0500.
      LEAVE SCREEN.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      PERFORM zsp26_hub_edit_wvar_0500.

    WHEN 'BT_START' OR 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'BT_SPOOL' OR 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.

    WHEN 'BT_PREVIEW'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_start_date <> 'X'.
        MESSAGE 'Chưa maintain Start Date. Vào Start Date để khai báo trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_spool_set <> 'X'.
        MESSAGE 'Chưa maintain Spool Parameters. Vào Spool Parameters trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        PERFORM do_archive_write.
      ENDIF.

    WHEN 'ONLI'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_start_date <> 'X'.
        MESSAGE 'Chưa maintain Start Date. Vào Start Date để khai báo trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_spool_set <> 'X'.
        MESSAGE 'Chưa maintain Spool Parameters. Vào Spool Parameters trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        PERFORM do_archive_write_bg_job.
        SET SCREEN 0100.
        LEAVE SCREEN.
      ENDIF.

    WHEN 'BACK'.
      SET SCREEN 0100.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0600 INPUT — ADK delete from DB (archive session)
*&---------------------------------------------------------------------*
MODULE user_command_0600 INPUT.
  DATA: lv_rc_600  TYPE sy-subrc,
        lv_u6      TYPE sy-ucomm.

  lv_u6 = ok_code.
  CLEAR ok_code.

  CASE lv_u6.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0600.
      LEAVE SCREEN.
    WHEN 'BT_EDIT' OR 'EDIT_BTN'.
      IF gv_variant IS NOT INITIAL.
        IF gv_tabname IS INITIAL.
          MESSAGE 'Chọn bảng archive trước khi chỉnh Variant' TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        IF gv_prog_del IS INITIAL.
          PERFORM get_archive_programs.
        ENDIF.
        IF gv_prog_del IS INITIAL.
          RETURN.
        ENDIF.

        DATA: lv_vtech_600 TYPE variant,
              lv_vok_600   TYPE abap_bool,
              lv_ok_600    TYPE abap_bool.
        PERFORM arch_build_write_var_tech
          USING gv_tabname gv_variant
          CHANGING lv_vtech_600 lv_vok_600.
        IF lv_vok_600 = abap_false.
          MESSAGE 'Tên Variant (ID) không hợp lệ hoặc quá dài.' TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.

        CALL FUNCTION 'RS_VARIANT_EXISTS'
          EXPORTING
            report  = gv_prog_del
            variant = lv_vtech_600
          IMPORTING
            r_c     = lv_rc_600.

        IF lv_rc_600 = 0.
          EXPORT zsp26_no_ss_exec = 'X' TO MEMORY ID 'Z_GSP18_WR_SS'.
          SUBMIT (gv_prog_del)
            WITH p_table = gv_tabname
            USING SELECTION-SET lv_vtech_600
            VIA SELECTION-SCREEN
            AND RETURN.
          FREE MEMORY ID 'Z_GSP18_WR_SS'.
        ELSE.
          DATA: lv_ans_600 TYPE char1,
                lv_msg_600 TYPE string.
          lv_msg_600 = |Variant { lv_vtech_600 } chưa tồn tại cho Delete program. Tạo mới?|.
          CALL FUNCTION 'POPUP_TO_CONFIRM'
            EXPORTING
              titlebar              = 'Create Delete Variant'
              text_question         = lv_msg_600
              text_button_1         = 'Tạo'
              text_button_2         = 'Hủy'
              display_cancel_button = ' '
            IMPORTING
              answer                = lv_ans_600
            EXCEPTIONS
              OTHERS                = 1.
          IF lv_ans_600 = '1'.
            PERFORM arch_ensure_write_variant
              USING gv_prog_del lv_vtech_600 gv_tabname
              CHANGING lv_ok_600.
            IF lv_ok_600 = abap_true.
              EXPORT zsp26_no_ss_exec = 'X' TO MEMORY ID 'Z_GSP18_WR_SS'.
              SUBMIT (gv_prog_del)
                WITH p_table = gv_tabname
                USING SELECTION-SET lv_vtech_600
                VIA SELECTION-SCREEN
                AND RETURN.
              FREE MEMORY ID 'Z_GSP18_WR_SS'.
            ELSE.
              MESSAGE |Không tạo được variant { lv_vtech_600 }.| TYPE 'S' DISPLAY LIKE 'E'.
            ENDIF.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'BT_ARCH_SEL'.
      IF gv_purge_mode = 'X'.
        MESSAGE 'Purge-only mode không cần chọn Archive Selection.' TYPE 'S'.
      ELSE.
        PERFORM arch_del_pick_session_popup USING 'D'.
      ENDIF.

    WHEN 'BT_START' OR 'START_BTN'.
      PERFORM maintenance_start_date.
    WHEN 'BT_SPOOL' OR 'SPOOL_BTN'.
      PERFORM maintenance_spool_params.

    WHEN 'BT_RUN_DELETE'.
      PERFORM do_archive_delete_job.

    WHEN 'ONLI'.
      IF gv_tabname IS INITIAL.
        MESSAGE 'Vui lòng nhập Table Name ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_start_date <> 'X'.
        MESSAGE 'Chưa maintain Start Date. Vào Start Date để khai báo trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_spool_set <> 'X'.
        MESSAGE 'Chưa maintain Spool Parameters. Vào Spool Parameters trước khi Execute.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSEIF gv_purge_mode = 'X'.
        PERFORM do_purge_only_direct.
      ELSEIF gv_del_sess_def IS INITIAL AND gv_variant IS INITIAL.
        MESSAGE 'Chưa chọn Archive Selection (session) hoặc Variant cho delete.' TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        IF gv_test_mode = 'X'.
          MESSAGE 'Đang ở Test Mode: job Delete chỉ mô phỏng, không xóa dữ liệu DB.' TYPE 'S' DISPLAY LIKE 'W'.
        ENDIF.
        PERFORM do_archive_delete_bg_job.
        SET SCREEN 0100.
        LEAVE SCREEN.
      ENDIF.

    WHEN 'BACK'.
      SET SCREEN 0100.
      LEAVE SCREEN.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0700 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0700 INPUT.
  DATA: lv_c7 TYPE sy-ucomm.

  lv_c7 = ok_code.
  CLEAR ok_code.

  CASE lv_c7.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0700.
      LEAVE SCREEN.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      IF go_cont_700 IS BOUND.
        go_cont_700->free( ).
        CLEAR: go_cont_700, go_alv_700, gt_fcat_700.
      ENDIF.
      CLEAR: gt_adm_list, gv_adm_pick.
      SET SCREEN 0100.
      LEAVE SCREEN.

    WHEN 'BT_ADM_ADD'.
      PERFORM arch_admin_do_add.

    WHEN 'BT_ADM_DEL'.
      PERFORM arch_admin_do_remove.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0800 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0800 INPUT.
  DATA: lv_c8 TYPE sy-ucomm.

  lv_c8 = ok_code.
  CLEAR ok_code.

  CASE lv_c8.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0800.
      LEAVE SCREEN.
    WHEN 'BT_REG_SAVE'.
      PERFORM do_reg_validate_and_save.

    " CANC = nút Cancel dynpro (FCODE CANC) → xử lý như Exit: không kiểm tra chuyển đổi field
    WHEN 'BT_REG_CANCEL' OR 'BACK' OR 'EXIT' OR 'CANC'.
      CLEAR: gv_reg_table, gv_reg_datfld, gv_reg_ret, gv_reg_desc, gv_reg_active.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& F4 screen 0800 (PAI include — VALUE-REQUEST)
*&---------------------------------------------------------------------*
MODULE f4_reg_table INPUT.
  PERFORM f4_reg_table.
ENDMODULE.

MODULE f4_reg_datfld INPUT.
  PERFORM f4_reg_datfld.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0810 INPUT
*&---------------------------------------------------------------------*
MODULE user_command_0810 INPUT.
  DATA: lv_c81 TYPE sy-ucomm.

  lv_c81 = ok_code.
  CLEAR ok_code.

  CASE lv_c81.
    WHEN 'BT_REFRESH'.
      SET SCREEN 0810.
      LEAVE SCREEN.
    WHEN 'BT_CFG_REG'.
      CLEAR: gv_reg_table, gv_reg_datfld, gv_reg_desc.
      gv_reg_ret    = '365'.
      gv_reg_active = 'X'.
      CALL SCREEN 0800 STARTING AT 12 6 ENDING AT 88 20.
      LEAVE TO SCREEN 0.

    WHEN 'BT_CFG_LIST' OR 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.
