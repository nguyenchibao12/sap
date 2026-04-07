*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_TOP
*& Fields / Types / Classes — tương đương "Fields" + "Types" + "Classes"
*& trong cây object của SE80
*&---------------------------------------------------------------------*
"----------------------------------------------------------------------
" OK-Code (mọi screen đều dùng chung)
"----------------------------------------------------------------------
DATA: ok_code TYPE sy-ucomm.

"----------------------------------------------------------------------
" Types — Preview Archive
"----------------------------------------------------------------------
TYPES: BEGIN OF ty_prev,
         key_vals TYPE char100,
         date_val TYPE d,
         age_days TYPE i,
         status   TYPE char10,
         detail   TYPE char60,
       END OF ty_prev.

" Types — Restore preview
TYPES: BEGIN OF ty_arch_row,
         sel         TYPE c,
         arch_id     TYPE zsp26_de_archid,
         data_seq    TYPE i,
         table_name  TYPE tabname,
         key_values  TYPE char255,
         archived_on TYPE d,
         archived_by TYPE xubname,
         arch_status TYPE char1,
         data_json   TYPE string,
       END OF ty_arch_row.

" Types — Monitor summary
TYPES: BEGIN OF ty_arch_stat,
         table_name   TYPE tabname,
         cnt_archived TYPE i,
         cnt_restored TYPE i,
         cnt_active   TYPE i,
         last_arch_on TYPE d,
         last_arch_by TYPE xubname,
         last_action  TYPE char10,
       END OF ty_arch_stat.

" Types — Monitor detail log
TYPES: BEGIN OF ty_log_det,
         table_name TYPE tabname,
         action     TYPE char10,
         rec_count  TYPE i,
         status     TYPE char1,
         exec_user  TYPE xubname,
         exec_date  TYPE d,
         message    TYPE char255,
       END OF ty_log_det.

"----------------------------------------------------------------------
" Fields (Global Data) — tương đương tab "Fields" trong SE80
"----------------------------------------------------------------------

" Screen 0100 — input chính
DATA: gv_tabname TYPE tabname.        " Bảng ZSP26_* đang thao tác
" Chỉ cho phép vào hub 0100 sau khi user Continue từ 0400 (tránh TSTC sai DYPNO mở thẳng 0100)
DATA: gv_hub_allowed TYPE abap_bool VALUE abap_false.

" Archive operation globals
DATA: gs_cfg      TYPE zsp26_arch_cfg,
      gr_all      TYPE REF TO data,
      gr_ready    TYPE REF TO data,
      gv_rdy_cnt  TYPE i,
      gv_skp_cnt  TYPE i.

FIELD-SYMBOLS: <lt_all>   TYPE ANY TABLE,
               <lt_ready> TYPE ANY TABLE.

" Restore globals
DATA: gt_arch_rows TYPE TABLE OF ty_arch_row,
      gv_restored  TYPE i,
      gv_errors    TYPE i.

" Monitor globals
DATA: gt_arch_stat TYPE TABLE OF ty_arch_stat,
      go_alv_200   TYPE REF TO cl_gui_alv_grid,
      go_cont_200  TYPE REF TO cl_gui_custom_container,
      gt_fcat_200  TYPE lvc_t_fcat.

" Screen 0300 / 0500 — SARA scheduler (variant, start, spool)
DATA: gv_object     TYPE arch_obj-object,
      gv_variant    TYPE variant,
      gv_prog_write TYPE programm,
      gv_prog_del   TYPE programm,
      gv_start_date TYPE char1,
      gv_spool_set  TYPE char1,
      gv_test_mode  TYPE char1 VALUE 'X',
      gv_det_log    TYPE char1 VALUE 'X'.

" Screen 0500 — hiển thị giống SARA Create archive file
DATA: gv_disp_mandt    TYPE mandt,
      gv_disp_uname    TYPE syuname,
      gv_stat_start_tx TYPE char20,
      gv_stat_spool_tx TYPE char20.

DATA: go_alv_grid    TYPE REF TO cl_gui_alv_grid,
      go_custom_cont TYPE REF TO cl_gui_custom_container,
      gt_fcat        TYPE lvc_t_fcat,
      gs_layout      TYPE lvc_s_layo.

"----------------------------------------------------------------------
" Classes — Event handler cho SALV custom buttons
" (tương đương tab "Classes" trong SE80)
"----------------------------------------------------------------------
CLASS lcl_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_cmd
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

"  lcl_handler IMPLEMENTATION is in Z_GSP18_SAP15_F01
