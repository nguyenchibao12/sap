*&---------------------------------------------------------------------*
*& Report Z_GSP18_SAP15_MAIN
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT Z_GSP18_SAP15_MAIN.
INCLUDE Z_GSP18_SAP15_TOP.  " Global Data
INCLUDE Z_GSP18_SAP15_F01.  " Subroutines
INCLUDE Z_GSP18_SAP15_O01.  " PBO Modules
INCLUDE Z_GSP18_SAP15_I01.  " PAI Modules

START-OF-SELECTION.
  CALL SCREEN 0400.
