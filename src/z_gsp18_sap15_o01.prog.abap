*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_O01
*&---------------------------------------------------------------------*
MODULE status_0100 OUTPUT.
  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100'.
ENDMODULE.

MODULE status_0200 OUTPUT.
  SET PF-STATUS 'STATUS_200'.
  PERFORM get_data.
  PERFORM build_fieldcat.
  PERFORM display_alv.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0300 OUTPUT
*&---------------------------------------------------------------------*
MODULE status_0300 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300'.
ENDMODULE.
