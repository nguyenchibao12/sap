*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_O01
*&---------------------------------------------------------------------*
MODULE status_0400 OUTPUT.
  DATA lv_adm_0400 TYPE abap_bool ##NEEDED.

  PERFORM is_arch_admin CHANGING lv_adm_0400.
  IF lv_adm_0400 = abap_true AND gv_admin_pick_table IS INITIAL.
    gv_hub_allowed = abap_true.
    SET SCREEN 0100.
    LEAVE SCREEN.
  ENDIF.

  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100' ##TITL_UNDEF.
ENDMODULE.

MODULE status_0100 OUTPUT.
  DATA lv_adm_0100 TYPE abap_bool ##NEEDED.

  IF gv_hub_allowed <> abap_true.
    SET SCREEN 0400.
    LEAVE SCREEN.
  ENDIF.

  PERFORM is_arch_admin CHANGING lv_adm_0100.

  LOOP AT SCREEN.
    CASE screen-name.
      WHEN 'GV_TABNAME'.
        screen-input = 0.
        screen-output = 1.
        MODIFY SCREEN.
      WHEN 'WRITE_BUTTON'
        OR 'DELETE_BUTTON'.
        IF gv_tabname IS INITIAL.
          screen-active = 0.
        ELSE.
          screen-active = 1.
        ENDIF.
        MODIFY SCREEN.
      WHEN 'MANAGE_BUTTON'
        OR 'ADMIN_BTN'.
        IF lv_adm_0100 = abap_true.
          screen-active = 1.
        ELSE.
          screen-active = 0.
        ENDIF.
        MODIFY SCREEN.
    ENDCASE.
  ENDLOOP.

  SET CURSOR FIELD 'CHANGE_TAB_BTN'.

  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100' ##TITL_UNDEF.
ENDMODULE.

MODULE status_0200 OUTPUT.
  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100' ##TITL_UNDEF.
  IF gv_s200_mode = 'CFG'.
    IF gt_cfg_data IS INITIAL.
      SELECT DISTINCT table_name, description, retention, data_field, is_active
        FROM zsp26_arch_cfg
        INTO CORRESPONDING FIELDS OF TABLE @gt_cfg_data
        ORDER BY table_name.
    ENDIF.
  ELSE.
    IF gt_arch_stat IS INITIAL.
      PERFORM get_data.
      PERFORM build_fieldcat.
    ENDIF.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module DISPLAY_ALV_0200 OUTPUT
*&---------------------------------------------------------------------*
MODULE display_alv_0200 OUTPUT.
  IF gv_s200_mode = 'CFG'.
    PERFORM display_cfg_alv.
  ELSE.
    PERFORM display_alv.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0700 OUTPUT — manage ZSP26_ARCH_ADMIN
*&---------------------------------------------------------------------*
MODULE status_0700 OUTPUT.
  DATA lv_adm_700 TYPE abap_bool ##NEEDED.

  PERFORM is_arch_admin CHANGING lv_adm_700.
  IF lv_adm_700 = abap_false.
    " Do not raise MESSAGE in PBO; it causes status-line flicker on every roundtrip.
    SET SCREEN 0100.
    LEAVE SCREEN.
  ENDIF.

  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300' ##TITL_UNDEF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module DISPLAY_ALV_0700 OUTPUT
*&---------------------------------------------------------------------*
MODULE display_alv_0700 OUTPUT.
  PERFORM arch_admin_load_list.
  IF go_cont_700 IS NOT BOUND.
    PERFORM arch_admin_build_fieldcat.
    PERFORM arch_admin_display_alv.
  ELSE.
    IF go_alv_700 IS BOUND.
      go_alv_700->refresh_table_display( ).
    ENDIF.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module INIT_FIELDS_0300 OUTPUT
*&---------------------------------------------------------------------*
MODULE init_fields_0300 OUTPUT.
  " Default values for Write Job screen
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
  DATA lt_excl_300 TYPE TABLE OF sy-ucomm ##NEEDED.
  DATA lv_excl_300 TYPE sy-ucomm ##NEEDED.

  " Edit Variant screen: disable Execute/F8 and hide Preview action
  lv_excl_300 = 'ONLI'.       APPEND lv_excl_300 TO lt_excl_300.
  lv_excl_300 = 'BT_PREVIEW'. APPEND lv_excl_300 TO lt_excl_300.

  SET PF-STATUS 'STATUS_300' EXCLUDING lt_excl_300.
  SET TITLEBAR 'TITLE_300' ##TITL_UNDEF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module INIT_FIELDS_0500 OUTPUT — Client / User / Start & Spool status
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

  IF gv_start_date = 'X'.
    gv_stat_start_tx = 'Defined' ##NO_TEXT.
  ELSE.
    gv_stat_start_tx = 'Not Defined' ##NO_TEXT.
  ENDIF.
  IF gv_spool_set = 'X'.
    gv_stat_spool_tx = 'Defined' ##NO_TEXT.
  ELSE.
    gv_stat_spool_tx = 'Not Defined' ##NO_TEXT.
  ENDIF.

  IF gv_prog_write IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.

  PERFORM refresh_var_tech_display.

  LOOP AT SCREEN.
    IF screen-name = 'GV_VAR_TECH'
       OR screen-name = 'GV_DISP_UNAME'
       OR screen-name = 'GV_DISP_MANDT'.
      screen-input = 0.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0500 OUTPUT
*&---------------------------------------------------------------------*
MODULE status_0500 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300' ##TITL_UNDEF.
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

  gv_disp_mandt  = sy-mandt.
  gv_disp_uname  = sy-uname.

  gv_scr600_head = |Archive for { gv_object }| ##NO_TEXT.

  IF gv_purge_mode = 'X'.
    gv_stat_arch_tx = 'N/A (Purge-only)' ##NO_TEXT.
  ELSEIF gv_del_sess_def = 'X' AND gs_del_admi-document IS NOT INITIAL.
    gv_stat_arch_tx = |Defined ({ gs_del_admi-document })| ##NO_TEXT.
  ELSEIF gv_del_sess_def = 'X' OR gv_variant IS NOT INITIAL.
    gv_stat_arch_tx = 'Defined' ##NO_TEXT.
  ELSE.
    gv_stat_arch_tx = 'Not Defined' ##NO_TEXT.
  ENDIF.
  IF gv_start_date = 'X'.
    gv_stat_start_tx = 'Defined' ##NO_TEXT.
  ELSE.
    gv_stat_start_tx = 'Not Defined' ##NO_TEXT.
  ENDIF.
  IF gv_spool_set = 'X'.
    gv_stat_spool_tx = 'Defined' ##NO_TEXT.
  ELSE.
    gv_stat_spool_tx = 'Not Defined' ##NO_TEXT.
  ENDIF.

  IF gv_prog_del IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.

  PERFORM refresh_var_tech_display.

  LOOP AT SCREEN.
    IF screen-name = 'GV_VAR_TECH'
       OR screen-name = 'GV_DISP_UNAME'
       OR screen-name = 'GV_DISP_MANDT'.
      screen-input = 0.
      MODIFY SCREEN.
    ELSEIF screen-name = 'ARCH_SEL_BTN_C6'.
      IF gv_purge_mode = 'X'.
        screen-invisible = 1.
        screen-active    = 0.
      ELSE.
        screen-invisible = 0.
        screen-active    = 1.
      ENDIF.
      MODIFY SCREEN.
    ELSEIF screen-name = 'ELIGIBLE_BTN_C6'.
      IF gv_purge_mode = 'X'.
        screen-invisible = 0.
        screen-active    = 1.
      ELSE.
        screen-invisible = 1.
        screen-active    = 0.
      ENDIF.
      MODIFY SCREEN.
    ELSEIF screen-name = 'GV_STAT_ARCH_TX'.
      IF gv_purge_mode = 'X'.
        screen-invisible = 1.
        screen-active    = 0.
      ELSE.
        screen-invisible = 0.
        screen-active    = 1.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0600 OUTPUT — toolbar same as hub (Back/Exit)
*&---------------------------------------------------------------------*
MODULE status_0600 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300' ##TITL_UNDEF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& F4 screen 0700 — select user from USR02
*&---------------------------------------------------------------------*
MODULE f4_gv_adm_pick INPUT.
  PERFORM arch_admin_f4_usr02.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Screen 0800 — register table into ZSP26_ARCH_CFG
*&---------------------------------------------------------------------*
MODULE status_0800 OUTPUT.
  DATA ls_exist TYPE zsp26_arch_cfg.
  DATA lv_already TYPE abap_bool.

  " New registrations are always active; field is output-only (no INPUT_FLD in screen).
  gv_reg_active = 'X'.
  IF gv_reg_ret IS INITIAL OR gv_reg_ret CO space.
    gv_reg_ret = '365'.
  ENDIF.

  " Auto-fill from existing config when table is already registered as active.
  CLEAR lv_already.
  IF gv_reg_table IS NOT INITIAL.
    SELECT SINGLE * FROM zsp26_arch_cfg
      INTO @ls_exist
      WHERE table_name = @gv_reg_table
        AND is_active  = 'X'.
    IF sy-subrc = 0.
      lv_already = abap_true.
      IF gv_reg_datfld IS INITIAL.
        gv_reg_datfld = ls_exist-data_field.
      ENDIF.
      IF gv_reg_ret IS INITIAL OR gv_reg_ret = '365'.
        gv_reg_ret = CONV char6( ls_exist-retention ).
      ENDIF.
      IF gv_reg_desc IS INITIAL.
        gv_reg_desc = ls_exist-description.
      ENDIF.
    ENDIF.
  ENDIF.

  " Lock GV_REG_TABLE when table is already active — prevent re-registration.
  LOOP AT SCREEN.
    IF screen-name = 'GV_REG_TABLE' AND lv_already = abap_true.
      screen-input = 0.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300' ##TITL_UNDEF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Screen 0810 — choose: view config list or register table (Fiori hides custom SALV buttons)
*&---------------------------------------------------------------------*
MODULE status_0810 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300' ##TITL_UNDEF.
ENDMODULE.
