*&---------------------------------------------------------------------*
*& Report Z_GSP18_SAP15_MAIN
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT Z_GSP18_SAP15_MAIN.
INCLUDE <icon>.
INCLUDE Z_GSP18_SAP15_TOP.  " Global Data
INCLUDE Z_GSP18_SAP15_F01.  " Subroutines
INCLUDE Z_GSP18_SAP15_O01.  " PBO Modules
INCLUDE Z_GSP18_SAP15_I01.  " PAI Modules

START-OF-SELECTION.
  DATA: lv_start_admin TYPE abap_bool.

  PERFORM is_arch_admin CHANGING lv_start_admin.
  IF lv_start_admin = abap_true.
    gv_hub_allowed = abap_true.
    CALL SCREEN 0100.
  ELSE.
    gv_hub_allowed = abap_false.
    CALL SCREEN 0400.
  ENDIF.
