*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_O01
*&---------------------------------------------------------------------*
MODULE status_0400 OUTPUT.
  DATA: lv_adm_0400 TYPE abap_bool.

  PERFORM is_arch_admin CHANGING lv_adm_0400.
  IF lv_adm_0400 = abap_true.
    gv_hub_allowed = abap_true.
    SET SCREEN 0100.
    LEAVE SCREEN.
    RETURN.
  ENDIF.

  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100'.
ENDMODULE.

MODULE status_0100 OUTPUT.
  DATA: lv_adm_0100 TYPE abap_bool.

  IF gv_hub_allowed <> abap_true.
    SET SCREEN 0400.
    LEAVE SCREEN.
  ENDIF.

  PERFORM is_arch_admin CHANGING lv_adm_0100.
  CLEAR gv_full_restore.

  LOOP AT SCREEN.
    CASE screen-name.
      WHEN 'MANAGE_BUTTON'.
        IF lv_adm_0100 = abap_true.
          screen-active = 1.
        ELSE.
          screen-active = 0.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'LBL_FULL_RESTORE'
        OR 'GV_FULL_RESTORE'.
        screen-active = 0.
        MODIFY SCREEN.
    ENDCASE.
  ENDLOOP.

  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100'.
ENDMODULE.

MODULE status_0200 OUTPUT.
  " STATUS_200 không tồn tại trong CUA — dùng lại STATUS_100
  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100'.
  " Load và build field catalog nếu chưa có dữ liệu
  IF gt_arch_stat IS INITIAL.
    PERFORM get_data.
    PERFORM build_fieldcat.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module DISPLAY_ALV_0200 OUTPUT
*&---------------------------------------------------------------------*
MODULE display_alv_0200 OUTPUT.
  PERFORM display_alv.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module INIT_FIELDS_0300 OUTPUT
*&---------------------------------------------------------------------*
MODULE init_fields_0300 OUTPUT.
  " Giá trị mặc định cho màn hình Write Job
  IF gv_object IS INITIAL.
    gv_object = 'Z_ARCH_EKK'.
  ENDIF.
  IF gv_det_log IS INITIAL.
    gv_det_log = 'X'.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0300 OUTPUT
*&---------------------------------------------------------------------*
MODULE status_0300 OUTPUT.
  DATA: lt_excl_300 TYPE TABLE OF sy-ucomm,
        lv_excl_300 TYPE sy-ucomm.

  " Màn Edit Variant: không cho Execute/F8 và không hiện action Preview
  lv_excl_300 = 'ONLI'.       APPEND lv_excl_300 TO lt_excl_300.
  lv_excl_300 = 'BT_PREVIEW'. APPEND lv_excl_300 TO lt_excl_300.

  SET PF-STATUS 'STATUS_300' EXCLUDING lt_excl_300.
  SET TITLEBAR 'TITLE_300'.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module INIT_FIELDS_0500 OUTPUT — Client / User / trạng thái Start & Spool
*&---------------------------------------------------------------------*
MODULE init_fields_0500 OUTPUT.
  IF gv_object IS INITIAL.
    gv_object = 'Z_ARCH_EKK'.
  ENDIF.
  IF gv_det_log IS INITIAL.
    gv_det_log = 'X'.
  ENDIF.

  gv_disp_mandt = sy-mandt.
  gv_disp_uname = sy-uname.

  gv_stat_start_tx = COND #( WHEN gv_start_date = 'X' THEN 'Defined' ELSE 'Not Defined' ).
  gv_stat_spool_tx = COND #( WHEN gv_spool_set = 'X' THEN 'Defined' ELSE 'Not Defined' ).

  IF gv_prog_write IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0500 OUTPUT
*&---------------------------------------------------------------------*
MODULE status_0500 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300'.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module INIT_FIELDS_0600 OUTPUT — ADK delete from DB
*&---------------------------------------------------------------------*
MODULE init_fields_0600 OUTPUT.
  IF gv_object IS INITIAL.
    gv_object = 'Z_ARCH_EKK'.
  ENDIF.
  IF gv_det_log IS INITIAL.
    gv_det_log = 'X'.
  ENDIF.

  gv_disp_mandt = sy-mandt.
  IF gv_disp_uname IS INITIAL.
    gv_disp_uname = sy-uname.
  ENDIF.

  gv_scr600_head = |Archive for { gv_object }|.

  IF gv_del_sess_def = 'X' AND gs_del_admi-document IS NOT INITIAL.
    gv_stat_arch_tx = |Defined ({ gs_del_admi-document })|.
  ELSEIF gv_del_sess_def = 'X' OR gv_variant IS NOT INITIAL.
    gv_stat_arch_tx = 'Defined'.
  ELSE.
    gv_stat_arch_tx = 'Not Defined'.
  ENDIF.
  gv_stat_start_tx = COND #( WHEN gv_start_date = 'X' THEN 'Defined' ELSE 'Not Defined' ).
  gv_stat_spool_tx = COND #( WHEN gv_spool_set = 'X' THEN 'Defined' ELSE 'Not Defined' ).

  IF gv_prog_del IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0600 OUTPUT — toolbar giống hub (Back/Exit)
*&---------------------------------------------------------------------*
MODULE status_0600 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300'.
ENDMODULE.
