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
DATA: gv_tabname TYPE zsp26_de_tabname. " Khớp DDIC màn 0400 (ROLLNAME) + F4 Search Help chuẩn
" Chỉ cho phép vào hub 0100 sau khi user Continue từ 0400 (tránh TSTC sai DYPNO mở thẳng 0100)
DATA: gv_hub_allowed TYPE abap_bool VALUE abap_false.
DATA: gv_admin_pick_table TYPE xfeld VALUE space. " Admin requested to stay on table-selection screen
DATA: gv_full_restore TYPE xfeld VALUE space. " Admin only: restore all tables in selected session
" Batch archive: tất cả bảng active trong ZSP26_ARCH_CFG (màn 0400)
DATA: gv_batch_all TYPE xfeld VALUE space.
DATA: gt_batch_tabnames TYPE TABLE OF tabname.

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

" Screen 0700 — maintain ZSP26_ARCH_ADMIN (admin only)
DATA: gt_adm_list TYPE TABLE OF zsp26_arch_admin,
      go_alv_700  TYPE REF TO cl_gui_alv_grid,
      go_cont_700 TYPE REF TO cl_gui_custom_container,
      gt_fcat_700 TYPE lvc_t_fcat,
      gv_adm_pick TYPE syuname.

" Screen 0800 — đăng ký bảng mới vào ZSP26_ARCH_CFG (từ [Config])
DATA: gv_reg_table  TYPE tabname,
      gv_reg_datfld TYPE fieldname,
      gv_reg_ret    TYPE char6,
      gv_reg_desc   TYPE char80,
      gv_reg_active TYPE char1.

" Screen 0300 / 0500 — archive / job scheduler (variant, start, spool)
" gv_object = archive object id (AOBJ) — ví dụ Z_ARCH_EKK
" gv_tabname = bảng DDIC đích (preview/write/delete SQL) — bổ sung cho object ở trên
DATA: gv_object     TYPE arch_obj-object,
      gv_variant    TYPE variant, " ID do user nhập (vd VAR_01); tên SAP = {tiền_tố bảng}_{ID}
      gv_prog_write TYPE programm,
      gv_prog_del   TYPE programm,
      gv_start_date TYPE char1,
      gs_btc_start  TYPE tbtcstrt, " BP_START_DATE_EDITOR (Start Time — như SM37)
      gv_spool_set  TYPE char1,
      gv_test_mode  TYPE xfeld VALUE 'X',
      gv_det_log    TYPE char1 VALUE 'X'.

" Screen 0500 / 0600 — status texts (write/delete steps)
DATA: gv_disp_mandt    TYPE mandt,
      gv_disp_uname    TYPE syuname,
      gv_stat_arch_tx  TYPE char40,
      gv_stat_start_tx TYPE char20,
      gv_stat_spool_tx TYPE char20,
      gv_scr600_head   TYPE char80,
      gv_f4_sess       TYPE admi_run-document,
      gv_purge_mode    TYPE xfeld VALUE space,
      gv_del_sess_def  TYPE char1,
      gs_del_admi      TYPE admi_run.

DATA: go_alv_grid    TYPE REF TO cl_gui_alv_grid,
      go_custom_cont TYPE REF TO cl_gui_custom_container,
      gt_fcat        TYPE lvc_t_fcat,
      gs_layout      TYPE lvc_s_layo.

"----------------------------------------------------------------------
" Monitor enhanced — type + globals (Phase 2/3/4)
"----------------------------------------------------------------------
TYPES: BEGIN OF ty_mon_disp,
         table_name  TYPE tabname,
         status_icon TYPE icon_d,       " LED: green / yellow / red (monitor)
         status_txt  TYPE char10,       " Phase 2/3: OVERDUE / WARNING / OK (technical / export)
         live_recs   TYPE i,
         arch_recs   TYPE i,            " Phase 2: records in archive (status=A)
         del_recs    TYPE i,            " Phase 2: records deleted after archive
         pct_saved   TYPE p DECIMALS 1, " Phase 2: % archived vs total
         arch_runs   TYPE i,
         rest_runs   TYPE i,
         del_runs    TYPE i,
         last_action TYPE char10,
         last_date   TYPE d,
         last_arch_d TYPE d,            " Phase 2: last ARCHIVE date
         last_del_d  TYPE d,            " Phase 2: last DELETE date
         last_user   TYPE xubname,
         retention   TYPE i,
         is_active   TYPE char1,
       END OF ty_mon_disp.

DATA: gt_mon_disp TYPE TABLE OF ty_mon_disp,
      go_mon_alv  TYPE REF TO cl_salv_table.

" Hub — Run log: background jobs ZARCH* + SALV handlers
TYPES: BEGIN OF ty_btc_row,
         jobname    TYPE tbtcjob-jobname,
         jobcount   TYPE tbtcjob-jobcount,
         status     TYPE tbtcjob-status,
         status_txt TYPE char24,
         sdluname   TYPE syuname,
         progname   TYPE programm,
         listident  TYPE char14,
         strtdate   TYPE d,
         strttime   TYPE t,
       END OF ty_btc_row.

DATA: gt_btc_rows TYPE TABLE OF ty_btc_row,
      go_btc_alv  TYPE REF TO cl_salv_table.

TYPES: BEGIN OF ty_run_src_hub,
         document   TYPE admi_run-document,
         creat_date TYPE admi_run-creat_date,
         status     TYPE admi_run-status,
         user_name  TYPE admi_run-user_name,
         doc_num    TYPE i,
         grp_ord    TYPE i,
       END OF ty_run_src_hub.

TYPES: BEGIN OF ty_run_view_hub,
         grp_ord       TYPE i,
         line_ord      TYPE i,
         grp_icon      TYPE icon_d,
         session_group TYPE char60,
         session_range TYPE char60,
         is_header     TYPE char1,
         doc_from_n    TYPE i,
         doc_to_n      TYPE i,
       END OF ty_run_view_hub.

DATA: gt_run_src_hub  TYPE TABLE OF ty_run_src_hub,
      gt_run_view_hub TYPE TABLE OF ty_run_view_hub,
      go_run_alv      TYPE REF TO cl_salv_table.

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

" Phase 4: Monitor drill-down handler
CLASS lcl_mon_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_func
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

CLASS lcl_btc_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_func
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
    CLASS-METHODS on_dblclick
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.

CLASS lcl_run_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_func
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
    CLASS-METHODS on_dblclick
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.

" Config SALV — mở popup đăng ký bảng
CLASS lcl_cfg_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_func
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

"  lcl_handler + lcl_mon_handler + lcl_btc_handler + lcl_run_handler in F01
