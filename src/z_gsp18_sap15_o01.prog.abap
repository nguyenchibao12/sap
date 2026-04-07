*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_O01
*&---------------------------------------------------------------------*
MODULE status_0400 OUTPUT.
  SET PF-STATUS 'STATUS_100'.
  SET TITLEBAR 'TITLE_100'.
ENDMODULE.

MODULE status_0100 OUTPUT.
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
  IF gv_test_mode IS INITIAL.
    gv_test_mode = 'X'.
  ENDIF.
  IF gv_det_log IS INITIAL.
    gv_det_log = 'X'.
  ENDIF.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module STATUS_0300 OUTPUT
*&---------------------------------------------------------------------*
MODULE status_0300 OUTPUT.
  SET PF-STATUS 'STATUS_300'.
  SET TITLEBAR 'TITLE_300'.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module INIT_FIELDS_0500 OUTPUT — Client / User / trạng thái Start & Spool
*&---------------------------------------------------------------------*
MODULE init_fields_0500 OUTPUT.
  IF gv_object IS INITIAL.
    gv_object = 'Z_ARCH_EKK'.
  ENDIF.
  IF gv_test_mode IS INITIAL.
    gv_test_mode = 'X'.
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
