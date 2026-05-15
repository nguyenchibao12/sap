*&---------------------------------------------------------------------*
*& Report Z_GSP18_SAP15_MAIN
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT Z_GSP18_SAP15_MAIN.
INCLUDE <icon> ##INCL_OK.
INCLUDE Z_GSP18_SAP15_TOP.  " Global Data
INCLUDE Z_GSP18_SAP15_F01.  " Subroutines
INCLUDE Z_GSP18_SAP15_O01.  " PBO Modules
INCLUDE Z_GSP18_SAP15_I01.  " PAI Modules

LOAD-OF-PROGRAM.
  PERFORM zsp26_sync_cfg_active_vs_ddic.

START-OF-SELECTION.
  PERFORM hub_start_entry.

*&---------------------------------------------------------------------*
FORM hub_start_entry.
  DATA lv_start_admin TYPE abap_bool.

  PERFORM is_arch_admin CHANGING lv_start_admin.
  IF lv_start_admin = abap_true.
    gv_hub_allowed = abap_true.
    CALL SCREEN 0100.
  ELSE.
    gv_hub_allowed = abap_false.
    CALL SCREEN 0400.
  ENDIF.
ENDFORM.
