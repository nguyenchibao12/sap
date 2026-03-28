*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_TOP
*&---------------------------------------------------------------------*
INCLUDE <icon>.

DATA: ok_code TYPE sy-ucomm.

* Đối tượng ALV
DATA: go_alv_grid    TYPE REF TO cl_gui_alv_grid,
      go_custom_cont TYPE REF TO cl_gui_custom_container.

* Biến nghiệp vụ
DATA: gv_object       TYPE arch_obj-object,
      gv_variant      TYPE variant,
      gv_prog_write   TYPE programm,
      gv_prog_del     TYPE programm.

DATA: gs_print_params TYPE pri_params,   " Spool parameters
      gv_start_date   TYPE char1,        " Trạng thái đã set ngày bắt đầu chưa
      gv_spool_set    TYPE char1,        " Trạng thái đã set Spool chưa
      gv_test_mode    TYPE char1 VALUE 'X',
      gv_det_log      TYPE char1 VALUE 'X'.
* Cấu trúc bảng hiển thị
TYPES: BEGIN OF ty_outtab,
         status TYPE icon_d,
         object TYPE char10,
         sonum  TYPE i,
         text   TYPE char40,
       END OF ty_outtab.

DATA: gt_outtab TYPE TABLE OF ty_outtab,
      gs_layout TYPE lvc_s_layo,
      gt_fcat   TYPE lvc_t_fcat.
