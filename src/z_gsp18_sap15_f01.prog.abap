*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_F01
*& Subroutines + Class Implementation
*&---------------------------------------------------------------------*
INCLUDE z_gsp18_arch_dyn.

"----------------------------------------------------------------------
" Class Implementation (moved from TOP — TOP allows definitions only)
"----------------------------------------------------------------------
CLASS lcl_handler IMPLEMENTATION.
  METHOD on_cmd.
    CASE e_salv_function.
      WHEN 'ARCH_NOW'.
        DATA: lv_dep_ok TYPE abap_bool.
        PERFORM check_dependencies CHANGING lv_dep_ok.
        IF lv_dep_ok = abap_true.
          PERFORM do_archive_via_adk.
        ENDIF.
      WHEN 'RESTORE'.
        PERFORM do_restore_via_adk.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Phase 4 — Monitor drill-down: Detail Log button handler
*&---------------------------------------------------------------------*
CLASS lcl_mon_handler IMPLEMENTATION.
  METHOD on_func.
    CHECK e_salv_function = 'MON_DETAIL'.

    DATA: lo_sels  TYPE REF TO cl_salv_selections,
          lt_rows  TYPE salv_t_row,
          lv_idx   TYPE i,
          lv_tab   TYPE tabname.

    lo_sels = go_mon_alv->get_selections( ).
    lt_rows = lo_sels->get_selected_rows( ).

    IF lt_rows IS INITIAL.
      MESSAGE 'Vui lòng chọn 1 dòng trước khi xem Detail Log.' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    READ TABLE lt_rows INTO lv_idx INDEX 1.
    READ TABLE gt_mon_disp INTO DATA(ls_row) INDEX lv_idx.
    CHECK sy-subrc = 0.

    lv_tab = ls_row-table_name.
    PERFORM show_mon_detail USING lv_tab.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_WRITE — Phase 2+3: Preview & Archive
*& Đọc config → dynamic SELECT → SALV Preview → Archive Now
*&---------------------------------------------------------------------*
FORM do_archive_write.
  " 1. Kiểm tra bảng nhập vs ZSP26_ARCH_CFG + DDIC (FIELDINFO + DATA_FIELD tồn tại)
  DATA: lv_cfg_ok TYPE abap_bool.
  PERFORM validate_table_against_cfg
    USING gv_tabname CHANGING gs_cfg lv_cfg_ok.
  IF lv_cfg_ok = abap_false.
    MESSAGE |Bảng '{ gv_tabname }' không hợp lệ: không có dòng active ZSP26_ARCH_CFG hoặc DATA_FIELD không có trong DDIC.|
            TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 2. Dynamic SELECT toàn bộ bảng
  CREATE DATA gr_all TYPE TABLE OF (gv_tabname).
  ASSIGN gr_all->* TO <lt_all>.
  SELECT * FROM (gv_tabname) INTO TABLE <lt_all>.

  IF <lt_all> IS INITIAL.
    MESSAGE |Không có dữ liệu trong { gv_tabname }| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " 3. Hiển thị SALV Preview
  PERFORM show_archive_preview.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM SHOW_ARCHIVE_PREVIEW — Phân loại READY/TOO NEW, hiển thị SALV
*&---------------------------------------------------------------------*
FORM show_archive_preview.
  DATA: lt_prev TYPE TABLE OF ty_prev,
        ls_prev TYPE ty_prev.

  CREATE DATA gr_ready TYPE TABLE OF (gv_tabname).
  ASSIGN gr_ready->* TO <lt_ready>.
  CLEAR: gv_rdy_cnt, gv_skp_cnt.

  " Lấy key field đầu tiên (để hiển thị)
  DATA: lt_dd   TYPE TABLE OF dfies,
        lv_kfld TYPE string.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = gv_tabname
    TABLES     dfies_tab = lt_dd
    EXCEPTIONS OTHERS    = 1.

  LOOP AT lt_dd INTO DATA(ls_dd)
    WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
    lv_kfld = ls_dd-fieldname. EXIT.
  ENDLOOP.

  " Phân loại từng record
  DATA: lv_rule_pass TYPE abap_bool,
        lv_fail_cnt  TYPE i VALUE 0.

  LOOP AT <lt_all> ASSIGNING FIELD-SYMBOL(<row>).
    CLEAR ls_prev.

    ASSIGN COMPONENT lv_kfld OF STRUCTURE <row> TO FIELD-SYMBOL(<kv>).
    IF <kv> IS ASSIGNED. ls_prev-key_vals = <kv>. ENDIF.

    ASSIGN COMPONENT gs_cfg-data_field OF STRUCTURE <row> TO FIELD-SYMBOL(<dt>).
    IF <dt> IS ASSIGNED.
      ls_prev-date_val = <dt>.
      ls_prev-age_days = sy-datum - ls_prev-date_val.
    ENDIF.

    " Check archive rules first
    PERFORM apply_archive_rules
      USING <row> gs_cfg-config_id gv_tabname
      CHANGING lv_rule_pass.

    IF lv_rule_pass = abap_false.
      ls_prev-status = 'RULE FAIL'.
      ls_prev-detail = 'Does not meet archive criteria'.
      ADD 1 TO lv_fail_cnt.
      ADD 1 TO gv_skp_cnt.
    ELSEIF ls_prev-age_days >= gs_cfg-retention.
      ls_prev-status = 'READY'.
      ls_prev-detail = |Eligible: { ls_prev-age_days } days ≥ { gs_cfg-retention }d|.
      ADD 1 TO gv_rdy_cnt.
      INSERT <row> INTO TABLE <lt_ready>.
    ELSE.
      ls_prev-status = 'TOO NEW'.
      ls_prev-detail = |Only { ls_prev-age_days } / { gs_cfg-retention } days|.
      ADD 1 TO gv_skp_cnt.
    ENDIF.

    APPEND ls_prev TO lt_prev.
  ENDLOOP.

  " SALV Display
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_prev ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    IF gv_rdy_cnt > 0.
      TRY.
        lo_funcs->add_function(
          name     = 'ARCH_NOW'
          icon     = '@2L@'
          text     = 'Archive Now'
          tooltip  = |ADK: archive { gv_rdy_cnt } READY rows to .ARC (Z_ARCH_EKK)|
          position = if_salv_c_function_position=>right_of_salv_functions ).
      CATCH cx_salv_method_not_supported.
      ENDTRY.
      SET HANDLER lcl_handler=>on_cmd FOR lo_alv->get_event( ).
    ENDIF.

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'KEY_VALS' ).
      lo_col->set_long_text( |Key ({ lv_kfld })| ).
      lo_col ?= lo_cols->get_column( 'DATE_VAL' ).
      lo_col->set_long_text( |Date ({ gs_cfg-data_field })| ).
      lo_col ?= lo_cols->get_column( 'AGE_DAYS' ).
      lo_col->set_long_text( 'Age (days)' ).
      lo_col ?= lo_cols->get_column( 'STATUS' ).
      lo_col->set_long_text( 'Archive Status' ).
      lo_col ?= lo_cols->get_column( 'DETAIL' ).
      lo_col->set_long_text( 'Detail / Reason' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |PREVIEW — { gv_tabname }  [ Total: { lines( lt_prev ) } | &&
      |  READY: { gv_rdy_cnt }  TOO NEW: { gv_skp_cnt - lv_fail_cnt }  RULE FAIL: { lv_fail_cnt } | &&
      |/ Retention: { gs_cfg-retention }d / Field: { gs_cfg-data_field } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_existing
        cx_salv_wrong_call
        cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Variant Z_ARCH_EKK_WRITE — phạm vi theo bảng (SAP: một report + nhiều variant)
*& Logic tách bảng: PREFIX từ gv_tabname (arch_variant_tab_prefix) + ID ô nhập → tên VARID.
*& Tên lưu VARID: {tab_prefix}_{logical} ≤14 ký tự, vd BKPF_VAR_01 / EKKO_VAR_01
*& Thông báo/popup: luôn phân biệt ID (ô) vs tên SAP (FORM arch_variant_msg_labels).
*&---------------------------------------------------------------------*
FORM arch_variant_tab_prefix
  USING    iv_tabname TYPE tabname
  CHANGING cv_prefix TYPE string.

  cv_prefix = iv_tabname.
  TRANSLATE cv_prefix TO UPPER CASE.
  CONDENSE cv_prefix NO-GAPS.

  IF strlen( cv_prefix ) >= 6 AND cv_prefix(6) = 'ZSP26_'.
    SHIFT cv_prefix BY 6 PLACES LEFT.
  ENDIF.

  IF strlen( cv_prefix ) > 8.
    cv_prefix = cv_prefix(8).
  ENDIF.
ENDFORM.

FORM arch_build_write_var_tech
  USING    iv_tabname TYPE tabname
           iv_logical TYPE clike
  CHANGING cv_technical TYPE variant
           cv_ok       TYPE abap_bool.

  DATA: lv_pfx  TYPE string,
        lv_log  TYPE string,
        lv_full TYPE string,
        lv_ml   TYPE i,
        lv_mxp  TYPE i,
        lv_plen TYPE i.

  CLEAR: cv_technical, cv_ok.
  cv_ok = abap_false.

  IF iv_tabname IS INITIAL.
    RETURN.
  ENDIF.

  lv_log = CONV string( iv_logical ).
  TRANSLATE lv_log TO UPPER CASE.
  CONDENSE lv_log NO-GAPS.
  IF lv_log IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM arch_variant_tab_prefix USING iv_tabname CHANGING lv_pfx.
  IF lv_pfx IS INITIAL.
    RETURN.
  ENDIF.

  " Nếu user nhập trùng tiền tố bảng (vd EKKO_VAR_02) thì tách thành logical VAR_02
  " để tên VARID = EKKO_VAR_02, tránh EK_EKKO_VAR_02 do giới hạn 14 ký tự.
  lv_plen = strlen( lv_pfx ).
  IF lv_plen > 0 AND strlen( lv_log ) >= lv_plen + 2.
    IF substring( val = lv_log len = lv_plen ) = lv_pfx AND
       substring( val = lv_log len = 1 off = lv_plen ) = '_'.
      lv_log = substring( val = lv_log off = lv_plen + 1 ).
      CONDENSE lv_log NO-GAPS.
    ENDIF.
  ENDIF.
  IF lv_log IS INITIAL.
    RETURN.
  ENDIF.

  lv_ml = strlen( lv_log ).
  lv_mxp = 14 - 1 - lv_ml.
  IF lv_mxp < 1.
    RETURN.
  ENDIF.

  IF strlen( lv_pfx ) > lv_mxp.
    lv_pfx = lv_pfx(lv_mxp).
  ENDIF.

  lv_full = |{ lv_pfx }_{ lv_log }|.
  IF strlen( lv_full ) > 14.
    RETURN.
  ENDIF.

  cv_technical = CONV variant( lv_full ).
  TRANSLATE cv_technical TO UPPER CASE.
  cv_ok = abap_true.
ENDFORM.

*& Một dòng mô tả thống nhất (cùng từ vựng với nhãn dynpro "Variant ID" / VARID).
*& Dùng cho popup/messages và F4 — luôn tách Variant ID (ô) vs tên VARID (SAP, ≤14).
FORM arch_variant_msg_labels
  USING    iv_tabname TYPE tabname
           iv_logical TYPE clike
           iv_sap     TYPE clike
  CHANGING cv_text    TYPE string.

  DATA(lv_tab) = CONV string( iv_tabname ).
  DATA(lv_log) = CONV string( iv_logical ).
  DATA(lv_sap) = CONV string( iv_sap ).
  CONDENSE lv_tab NO-GAPS.
  CONDENSE lv_log NO-GAPS.
  CONDENSE lv_sap NO-GAPS.

  CLEAR cv_text.
  IF lv_tab IS NOT INITIAL.
    cv_text = |Bảng { lv_tab } — variant chỉ theo bảng này. |.
  ENDIF.
  IF lv_sap IS INITIAL OR lv_sap = lv_log.
    cv_text = cv_text && |Variant ID (ô nhập) = Tên VARID: { lv_log }.|.
  ELSE.
    cv_text = cv_text && |Variant ID (ô nhập): { lv_log }. Tên VARID (SAP): { lv_sap }.|.
  ENDIF.
ENDFORM.

FORM arch_log_from_write_var
  USING    iv_tabname TYPE tabname
           iv_technical TYPE clike
  CHANGING cv_logical TYPE variant
           cv_ok      TYPE abap_bool.

  DATA: lv_pfx TYPE string,
        lv_t   TYPE string,
        lv_len TYPE i.

  CLEAR: cv_logical, cv_ok.
  cv_ok = abap_false.

  IF iv_tabname IS INITIAL OR iv_technical IS INITIAL.
    RETURN.
  ENDIF.

  lv_t = CONV string( iv_technical ).
  TRANSLATE lv_t TO UPPER CASE.

  PERFORM arch_variant_tab_prefix USING iv_tabname CHANGING lv_pfx.
  IF lv_pfx IS INITIAL.
    RETURN.
  ENDIF.

  lv_len = strlen( lv_pfx ).
  IF strlen( lv_t ) <= lv_len + 1.
    RETURN.
  ENDIF.

  TRY.
    IF substring( val = lv_t len = 1 off = lv_len ) <> '_'.
      RETURN.
    ENDIF.
    CATCH cx_sy_range_out_of_bounds.
      RETURN.
  ENDTRY.

  cv_logical = substring( val = lv_t off = lv_len + 1 ).
  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*& Ensure write variant exists (auto-create for first edit)
*& RS_CREATE_VARIANT: vari_desc = VARID (không phải chuỗi) — tránh
*& CALL_FUNCTION_CONFLICT_LENG trên một số release với RS_CHANGE_CREATED_VARIANT
*&---------------------------------------------------------------------*
FORM arch_ensure_write_variant
  USING    iv_report  TYPE programm
           iv_vtech   TYPE variant
           iv_tabname TYPE tabname
  CHANGING cv_ok      TYPE abap_bool.

  DATA: ls_varid  TYPE varid,
        lt_varit  TYPE TABLE OF varit,
        ls_varit  TYPE varit,
        lt_params TYPE TABLE OF rsparams,
        ls_param  TYPE rsparams,
        lv_rep    TYPE syrepid.

  cv_ok = abap_false.
  IF iv_report IS INITIAL OR iv_vtech IS INITIAL OR iv_tabname IS INITIAL.
    RETURN.
  ENDIF.

  lv_rep = iv_report.

  CLEAR ls_varid.
  ls_varid-mandt      = sy-mandt.
  ls_varid-report     = lv_rep.
  ls_varid-variant    = iv_vtech.
  ls_varid-environmnt = 'A'.
  ls_varid-aedat      = sy-datum.
  ls_varid-aetime     = sy-uzeit.

  CLEAR ls_varit.
  ls_varit-mandt   = sy-mandt.
  ls_varit-langu   = sy-langu.
  ls_varit-report  = lv_rep.
  ls_varit-variant = iv_vtech.
  ls_varit-vtext   = iv_tabname.
  APPEND ls_varit TO lt_varit.

  CLEAR ls_param.
  ls_param-selname = 'P_TABLE'.
  ls_param-kind    = 'P'.
  ls_param-sign    = 'I'.
  ls_param-option  = 'EQ'.
  ls_param-low     = iv_tabname.
  APPEND ls_param TO lt_params.

  CLEAR ls_param.
  ls_param-selname = 'P_TEST'.
  ls_param-kind    = 'P'.
  ls_param-sign    = 'I'.
  ls_param-option  = 'EQ'.
  IF gv_test_mode = 'X'.
    ls_param-low = 'X'.
  ELSE.
    CLEAR ls_param-low.
  ENDIF.
  APPEND ls_param TO lt_params.

  CALL FUNCTION 'RS_CREATE_VARIANT'
    EXPORTING
      curr_report               = lv_rep
      curr_variant              = iv_vtech
      vari_desc                 = ls_varid
    TABLES
      vari_contents             = lt_params
      vari_text                 = lt_varit
    EXCEPTIONS
      illegal_report_or_variant = 1
      illegal_variantname       = 2
      not_authorized            = 3
      not_executed              = 4
      report_not_existent       = 5
      report_not_supplied       = 6
      variant_exists            = 7
      variant_locked            = 8
      OTHERS                    = 9.

  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
    cv_ok = abap_true.
  ELSEIF sy-subrc = 7.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_VIA_ADK — gọi ADK Write Program (từ lcl_handler)
*&---------------------------------------------------------------------*
FORM do_archive_via_adk.
  " Keep this entry-point for compatibility, but force background scheduling
  " so every execute path is traceable in SM37.
  PERFORM do_archive_write_bg_job.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_WRITE_BG_JOB — schedule ADK Write in SM37
*&---------------------------------------------------------------------*
FORM do_archive_write_bg_job.
  DATA: lv_vtech    TYPE variant,
        lv_vrun     TYPE variant,
        lv_vok      TYPE abap_bool,
        lv_rc_var   TYPE sy-subrc,
        lv_jobname  TYPE tbtcjob-jobname,
        lv_jobcount TYPE tbtcjob-jobcount.

  IF gv_tabname IS INITIAL.
    MESSAGE 'Vui lòng chọn bảng ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gv_variant IS NOT INITIAL.
    PERFORM arch_build_write_var_tech
      USING gv_tabname gv_variant
      CHANGING lv_vtech lv_vok.
    IF lv_vok = abap_false.
      MESSAGE 'Variant không hợp lệ hoặc quá dài (giới hạn tên SAP 14 ký tự).' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    CLEAR lv_vrun.
    CALL FUNCTION 'RS_VARIANT_EXISTS'
      EXPORTING
        report  = 'Z_ARCH_EKK_WRITE'
        variant = lv_vtech
      IMPORTING
        r_c     = lv_rc_var.
    IF lv_rc_var = 0.
      lv_vrun = lv_vtech.
    ELSE.
      CALL FUNCTION 'RS_VARIANT_EXISTS'
        EXPORTING
          report  = 'Z_ARCH_EKK_WRITE'
          variant = gv_variant
        IMPORTING
          r_c     = lv_rc_var.
      IF lv_rc_var = 0.
        lv_vrun = gv_variant.
      ENDIF.
    ENDIF.
  ENDIF.

  lv_jobname = |ZARCH_WR_{ sy-uname }|.

  CALL FUNCTION 'JOB_OPEN'
    EXPORTING
      jobname          = lv_jobname
    IMPORTING
      jobcount         = lv_jobcount
    EXCEPTIONS
      cant_create_job  = 1
      invalid_job_data = 2
      jobname_missing  = 3
      OTHERS           = 4.
  IF sy-subrc <> 0.
    MESSAGE 'Không mở được background job cho Write.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lv_vrun IS NOT INITIAL.
    SUBMIT z_arch_ekk_write
      WITH p_table = gv_tabname
      WITH p_test  = ' '
      USING SELECTION-SET lv_vrun
      VIA JOB lv_jobname NUMBER lv_jobcount
      AND RETURN.
  ELSE.
    SUBMIT z_arch_ekk_write
      WITH p_table = gv_tabname
      WITH p_test  = ' '
      VIA JOB lv_jobname NUMBER lv_jobcount
      AND RETURN.
  ENDIF.
  IF sy-subrc <> 0.
    MESSAGE 'Không add được step Write vào background job.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING
      jobname              = lv_jobname
      jobcount             = lv_jobcount
      strtimmed            = 'X'
    EXCEPTIONS
      cant_start_immediate = 1
      invalid_startdate    = 2
      jobname_missing      = 3
      job_close_failed     = 4
      job_nosteps          = 5
      job_notex            = 6
      lock_failed          = 7
      OTHERS               = 8.
  IF sy-subrc <> 0.
    MESSAGE 'Đã tạo job nhưng không close/start được. Kiểm tra SM37/SM21.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  MESSAGE |Đã schedule WRITE job { lv_jobname }/{ lv_jobcount } (SM37).| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_DELETE_JOB — SUBMIT delete program (ADK delete)
*&---------------------------------------------------------------------*
FORM do_archive_delete_job.
  DATA: lv_rc_var  TYPE sy-subrc,
        lv_sel_doc TYPE admi_run-document.

  IF gv_tabname IS INITIAL.
    MESSAGE 'Vui lòng chọn bảng ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF gv_prog_del IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.
  IF gv_prog_del IS INITIAL.
    MESSAGE 'Chưa cấu hình delete program (AOBJ)' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gv_del_sess_def = 'X'.
    EXPORT del_admi = gs_del_admi TO MEMORY ID 'Z_GSP18_ADMI_DEL'.
    lv_sel_doc = gs_del_admi-document.
  ELSEIF gv_f4_sess IS NOT INITIAL.
    lv_sel_doc = gv_f4_sess.
  ENDIF.

  IF gv_variant IS NOT INITIAL.
    CALL FUNCTION 'RS_VARIANT_EXISTS'
      EXPORTING
        report  = gv_prog_del
        variant = gv_variant
      IMPORTING
        r_c     = lv_rc_var.
  ENDIF.

  IF gv_variant IS NOT INITIAL AND lv_rc_var = 0.
    SUBMIT (gv_prog_del)
      WITH p_table = gv_tabname
      WITH p_test  = gv_test_mode
      WITH p_doc   = lv_sel_doc
      USING SELECTION-SET gv_variant
      AND RETURN.
  ELSE.
    IF gv_variant IS NOT INITIAL AND lv_rc_var <> 0.
      MESSAGE |Variant { gv_variant } không tồn tại trên { gv_prog_del } - chạy với default selection.| TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
    SUBMIT (gv_prog_del)
      WITH p_table = gv_tabname
      WITH p_test  = gv_test_mode
      WITH p_doc   = lv_sel_doc
      AND RETURN.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_DELETE_BG_JOB — schedule ADK Delete in SM37
*&---------------------------------------------------------------------*
FORM do_archive_delete_bg_job.
  DATA: lv_jobname  TYPE tbtcjob-jobname,
        lv_jobcount TYPE tbtcjob-jobcount,
        lv_rc_var   TYPE sy-subrc,
        lv_sel_doc  TYPE admi_run-document.

  IF gv_tabname IS INITIAL.
    MESSAGE 'Vui lòng chọn bảng ở màn trước' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF gv_prog_del IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.
  IF gv_prog_del IS INITIAL.
    MESSAGE 'Chưa cấu hình delete program (AOBJ)' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gv_del_sess_def = 'X'.
    EXPORT del_admi = gs_del_admi TO MEMORY ID 'Z_GSP18_ADMI_DEL'.
    lv_sel_doc = gs_del_admi-document.
  ELSEIF gv_f4_sess IS NOT INITIAL.
    lv_sel_doc = gv_f4_sess.
  ENDIF.

  IF gv_variant IS NOT INITIAL.
    CALL FUNCTION 'RS_VARIANT_EXISTS'
      EXPORTING
        report  = gv_prog_del
        variant = gv_variant
      IMPORTING
        r_c     = lv_rc_var.
  ENDIF.

  lv_jobname = |ZARCH_DEL_{ sy-uname }|.

  CALL FUNCTION 'JOB_OPEN'
    EXPORTING
      jobname          = lv_jobname
    IMPORTING
      jobcount         = lv_jobcount
    EXCEPTIONS
      cant_create_job  = 1
      invalid_job_data = 2
      jobname_missing  = 3
      OTHERS           = 4.
  IF sy-subrc <> 0.
    MESSAGE 'Không mở được background job cho Delete.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF gv_variant IS NOT INITIAL AND lv_rc_var = 0.
    SUBMIT (gv_prog_del)
      WITH p_table = gv_tabname
      WITH p_test  = gv_test_mode
      WITH p_doc   = lv_sel_doc
      USING SELECTION-SET gv_variant
      VIA JOB lv_jobname NUMBER lv_jobcount
      AND RETURN.
  ELSE.
    IF gv_variant IS NOT INITIAL AND lv_rc_var <> 0.
      MESSAGE |Variant { gv_variant } không tồn tại trên { gv_prog_del } - schedule job với default selection.| TYPE 'S' DISPLAY LIKE 'W'.
    ENDIF.
    SUBMIT (gv_prog_del)
      WITH p_table = gv_tabname
      WITH p_test  = gv_test_mode
      WITH p_doc   = lv_sel_doc
      VIA JOB lv_jobname NUMBER lv_jobcount
      AND RETURN.
  ENDIF.
  IF sy-subrc <> 0.
    MESSAGE 'Không add được step Delete vào background job.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING
      jobname              = lv_jobname
      jobcount             = lv_jobcount
      strtimmed            = 'X'
    EXCEPTIONS
      cant_start_immediate = 1
      invalid_startdate    = 2
      jobname_missing      = 3
      job_close_failed     = 4
      job_nosteps          = 5
      job_notex            = 6
      lock_failed          = 7
      OTHERS               = 8.
  IF sy-subrc <> 0.
    MESSAGE 'Đã tạo job nhưng không close/start được. Kiểm tra SM37/SM21.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  MESSAGE |Đã schedule DELETE job { lv_jobname }/{ lv_jobcount } (SM37).| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ARCH_DEL_PICK_SESSION_POPUP — chọn session/file delete (ADMI_RUN, AOBJ)
*&  Popup F4 nội bộ — không gọi transaction SARA
*&---------------------------------------------------------------------*
FORM arch_del_pick_session_popup.
  TYPES: BEGIN OF ty_arch_del_f4,
           document   TYPE admi_run-document,
           creat_date TYPE admi_run-creat_date,
           status     TYPE admi_run-status,
           user_name  TYPE admi_run-user_name,
         END OF ty_arch_del_f4.

  DATA: lt_f4  TYPE TABLE OF ty_arch_del_f4,
        ls_f4  TYPE ty_arch_del_f4,
        lt_run TYPE TABLE OF admi_run,
        lv_obj TYPE arch_obj-object,
        ls_run TYPE admi_run,
        lt_ret TYPE TABLE OF ddshretval,
        ls_ret TYPE ddshretval,
        lv_doc TYPE admi_run-document.

  IF gv_object IS INITIAL.
    gv_object = 'Z_ARCH_EKK'.
  ENDIF.
  lv_obj = gv_object.

  IF gv_prog_del IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.

  SELECT * FROM admi_run
    WHERE client = @sy-mandt
      AND object = @lv_obj
    INTO TABLE @lt_run
    UP TO 500 ROWS.

  IF lt_run IS INITIAL.
    MESSAGE 'Không có session trên ADMI_RUN cho AOBJ này (đã archive/write chưa?).' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  SORT lt_run BY creat_date DESCENDING document DESCENDING.

  LOOP AT lt_run INTO ls_run.
    CLEAR ls_f4.
    ls_f4-document   = ls_run-document.
    ls_f4-creat_date = ls_run-creat_date.
    ls_f4-status     = ls_run-status.
    ls_f4-user_name  = ls_run-user_name.
    APPEND ls_f4 TO lt_f4.
  ENDLOOP.

  " Popup-only return: không bind DYNPROFIELD — bind từ nút bấm thường làm SAP GUI không xác nhận (tick) được.
  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'DOCUMENT'
      window_title = 'Archive Administration: Select Files for Delete Program'
      value_org    = 'S'
    TABLES
      value_tab    = lt_f4
      return_tab   = lt_ret
    EXCEPTIONS
      OTHERS       = 0.

  IF lt_ret IS INITIAL.
    RETURN.
  ENDIF.

  DATA: lv_rp_doc TYPE i,
        lv_dstr   TYPE string,
        lv_fn     TYPE string.

  CLEAR: gs_del_admi, lv_doc, gv_f4_sess, lv_rp_doc.

  " recordpos theo từng cột — không được lấy MAX trên cả return_tab (dễ luôn ra index 1 = session mới nhất).
  " Gộp mọi dòng có FIELDNAME = DOCUMENT: lấy fieldval và recordpos (thường nằm ở các dòng khác nhau).
  LOOP AT lt_ret INTO ls_ret.
    lv_fn = ls_ret-fieldname.
    CONDENSE lv_fn.
    TRANSLATE lv_fn TO UPPER CASE.
    IF lv_fn <> 'DOCUMENT'.
      CONTINUE.
    ENDIF.
    IF ls_ret-fieldval IS NOT INITIAL.
      lv_dstr = ls_ret-fieldval.
      CONDENSE lv_dstr.
      lv_doc = CONV admi_run-document( lv_dstr ).
    ENDIF.
    IF ls_ret-recordpos > 0.
      lv_rp_doc = ls_ret-recordpos.
    ENDIF.
  ENDLOOP.

  IF lv_doc IS INITIAL AND lv_rp_doc = 0.
    LOOP AT lt_ret INTO ls_ret.
      CHECK ls_ret-fieldval IS NOT INITIAL.
      lv_dstr = ls_ret-fieldval.
      CONDENSE lv_dstr.
      lv_doc = CONV admi_run-document( lv_dstr ).
      IF ls_ret-recordpos > 0.
        lv_rp_doc = ls_ret-recordpos.
      ENDIF.
      EXIT.
    ENDLOOP.
  ENDIF.

  IF lv_doc IS NOT INITIAL.
    READ TABLE lt_run INTO gs_del_admi
      WITH KEY client = sy-mandt object = lv_obj document = lv_doc.
    IF sy-subrc <> 0.
      READ TABLE lt_f4 INTO ls_f4 WITH KEY document = lv_doc.
      IF sy-subrc = 0.
        READ TABLE lt_run INTO gs_del_admi INDEX sy-tabix.
      ENDIF.
    ENDIF.
    IF gs_del_admi-document IS INITIAL.
      LOOP AT lt_run INTO ls_run.
        IF ls_run-document = lv_doc.
          gs_del_admi = ls_run.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

  IF gs_del_admi-document IS INITIAL AND lv_rp_doc > 0.
    READ TABLE lt_run INTO gs_del_admi INDEX lv_rp_doc.
  ENDIF.

  IF gs_del_admi-document IS INITIAL.
    MESSAGE 'Không chọn được session từ danh sách.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  gv_f4_sess        = gs_del_admi-document.
  gv_del_sess_def   = 'X'.
  gv_stat_arch_tx   = |Defined ({ gs_del_admi-document })|.

  EXPORT del_admi = gs_del_admi TO MEMORY ID 'Z_GSP18_ADMI_DEL'.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_RESTORE_FROM_HUB — Restore từ archive (xác nhận → ADK + p_rest=X)
*&---------------------------------------------------------------------*
FORM do_restore_from_hub.
  DATA: lv_ans TYPE c LENGTH 1.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Restore from archive'
      text_question         = |Chọn file .ARC ở màn hình tiếp theo. Ghi dữ liệu vào bảng { gv_tabname }?|
      text_button_1         = 'Yes, restore'
      text_button_2         = 'No'
      default_button        = '2'
      display_cancel_button = ' '
    IMPORTING
      answer                = lv_ans
    EXCEPTIONS
      OTHERS                = 1.

  IF lv_ans = '1'.
    PERFORM do_restore_via_adk.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_RESTORE_VIA_ADK — gọi ADK Read Program (p_rest=X → INSERT DB)
*&---------------------------------------------------------------------*
FORM do_restore_via_adk.
  DATA: lv_rtab TYPE tabname.
  lv_rtab = gv_tabname.
  CONDENSE lv_rtab.
  TRANSLATE lv_rtab TO UPPER CASE.
  " Không truyền P_DOC từ hub: ARCHIVE_OPEN_FOR_READ + archive_document thường cần khớp đúng stack;
  " session trên hub có thể mở file sai / EOF → GET_TABLE rỗng → Restore 0. Chọn .ARC ở màn ADK.
  SUBMIT z_arch_ekk_read
    WITH p_table = lv_rtab
    WITH p_rest  = 'X'
    AND RETURN.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE — (legacy, kept for reference — not called anymore)
*&---------------------------------------------------------------------*
FORM do_archive.
  IF NOT <lt_ready> IS ASSIGNED OR <lt_ready> IS INITIAL.
    MESSAGE 'Không có records READY để archive' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA: ls_adata   TYPE zsp26_arch_data,
        ls_alog    TYPE zsp26_arch_log,
        lv_arch_id TYPE zsp26_de_archid,
        lv_log_id  TYPE sysuuid_x16,
        lv_json    TYPE string,
        lv_ok      TYPE i VALUE 0,
        lv_err     TYPE i VALUE 0,
        lv_seq     TYPE i VALUE 0,
        lv_ts_s    TYPE timestampl.

  TRY.
    lv_arch_id = cl_system_uuid=>create_uuid_c32_static( ).
    lv_log_id  = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error.
    MESSAGE 'Lỗi tạo UUID' TYPE 'E'. RETURN.
  ENDTRY.
  GET TIME STAMP FIELD lv_ts_s.

  " Key fields
  DATA: lt_dd  TYPE TABLE OF dfies,
        lt_kfs TYPE TABLE OF string.
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = gv_tabname
    TABLES     dfies_tab = lt_dd
    EXCEPTIONS OTHERS    = 1.
  LOOP AT lt_dd INTO DATA(ls_dd) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
    APPEND ls_dd-fieldname TO lt_kfs.
  ENDLOOP.

  LOOP AT <lt_ready> ASSIGNING FIELD-SYMBOL(<row>).
    ADD 1 TO lv_seq.
    DATA: lv_kv TYPE char255, lv_where TYPE string.
    CLEAR: lv_kv, lv_where.

    LOOP AT lt_kfs INTO DATA(lv_kf).
      ASSIGN COMPONENT lv_kf OF STRUCTURE <row> TO FIELD-SYMBOL(<fv>).
      IF <fv> IS ASSIGNED.
        DATA(lv_fv_str) = CONV string( <fv> ).
        IF lv_kv    IS NOT INITIAL. lv_kv    &&= '|'. ENDIF.
        IF lv_where IS NOT INITIAL. lv_where &&= ' AND '. ENDIF.
        lv_kv    &&= lv_kf && '=' && lv_fv_str.
        lv_where &&= lv_kf && ` EQ '` && lv_fv_str && `'`.
      ENDIF.
    ENDLOOP.
    lv_where = |MANDT EQ '{ sy-mandt }' AND | && lv_where.

    TRY.
      lv_json = /ui2/cl_json=>serialize( data = <row> ).
    CATCH cx_root.
      lv_json = lv_kv.
    ENDTRY.

    CLEAR ls_adata.
    ls_adata-arch_id     = lv_arch_id.
    ls_adata-data_seq    = lv_seq.
    ls_adata-table_name  = gv_tabname.
    ls_adata-key_values  = lv_kv.
    ls_adata-data_json   = lv_json.
    ls_adata-archived_on = sy-datum.
    ls_adata-archived_by = sy-uname.
    ls_adata-arch_status = 'A'.
    INSERT zsp26_arch_data FROM ls_adata.

    IF sy-subrc = 0.
      DELETE FROM (gv_tabname) WHERE (lv_where).
      IF sy-subrc = 0. ADD 1 TO lv_ok. ELSE. ADD 1 TO lv_err. ENDIF.
    ELSE.
      ADD 1 TO lv_err.
    ENDIF.
  ENDLOOP.

  IF lv_ok > 0. COMMIT WORK AND WAIT. ENDIF.

  " Log
  CLEAR ls_alog.
  ls_alog-log_id     = lv_log_id.
  ls_alog-arch_id    = lv_arch_id.
  ls_alog-config_id  = gs_cfg-config_id.
  ls_alog-table_name = gv_tabname.
  ls_alog-action     = 'ARCHIVE'.
  ls_alog-rec_count  = lv_ok.
  ls_alog-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
  ls_alog-start_time = lv_ts_s.
  GET TIME STAMP FIELD ls_alog-end_time.
  ls_alog-message    = |Archived { lv_ok } records. Errors: { lv_err }|.
  ls_alog-exec_user  = sy-uname.
  ls_alog-exec_date  = sy-datum.
  INSERT zsp26_arch_log FROM ls_alog.
  COMMIT WORK AND WAIT.

  MESSAGE |Archive xong: { lv_ok } records từ { gv_tabname } → ZSP26_ARCH_DATA|
          TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_RESTORE_PREVIEW — Phase 4: Mở ADK Read Program
*&---------------------------------------------------------------------*
FORM do_restore_preview.
  DATA: lv_rtab TYPE tabname.
  lv_rtab = gv_tabname.
  CONDENSE lv_rtab.
  TRANSLATE lv_rtab TO UPPER CASE.
  SUBMIT z_arch_ekk_read
    WITH p_table = lv_rtab
    WITH p_rest  = ' '
    AND RETURN.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_RESTORE_NOW — thực hiện restore (gọi từ lcl_handler)
*&---------------------------------------------------------------------*
FORM do_restore_now.
  IF gt_arch_rows IS INITIAL.
    MESSAGE 'Không có records để restore' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA: gr_rec TYPE REF TO data.
  CREATE DATA gr_rec TYPE (gv_tabname).
  ASSIGN gr_rec->* TO FIELD-SYMBOL(<rec>).

  DATA: ls_alog    TYPE zsp26_arch_log,
        lv_log_id  TYPE sysuuid_x16,
        lv_arch_id TYPE zsp26_de_archid,
        lv_ts_s    TYPE timestampl.
  CLEAR: gv_restored, gv_errors.
  GET TIME STAMP FIELD lv_ts_s.

  " Kiểm tra có record nào được tick không
  DATA(lv_any_sel) = abap_false.
  LOOP AT gt_arch_rows ASSIGNING FIELD-SYMBOL(<chk>).
    IF <chk>-sel = 'X'. lv_any_sel = abap_true. EXIT. ENDIF.
  ENDLOOP.

  LOOP AT gt_arch_rows ASSIGNING FIELD-SYMBOL(<arch>).
    IF lv_any_sel = abap_true AND <arch>-sel <> 'X'. CONTINUE. ENDIF.
    IF <arch>-data_json IS INITIAL. ADD 1 TO gv_errors. CONTINUE. ENDIF.

    TRY.
      /ui2/cl_json=>deserialize( EXPORTING json = <arch>-data_json CHANGING data = <rec> ).
    CATCH cx_root.
      ADD 1 TO gv_errors. CONTINUE.
    ENDTRY.

    INSERT (<arch>-table_name) FROM <rec>.
    IF sy-subrc = 0.
      UPDATE zsp26_arch_data SET arch_status = 'R'
        WHERE arch_id  = <arch>-arch_id
          AND data_seq = <arch>-data_seq.
      <arch>-arch_status = 'R'.
      lv_arch_id = <arch>-arch_id.
      ADD 1 TO gv_restored.
    ELSE.
      ADD 1 TO gv_errors.
    ENDIF.
  ENDLOOP.

  IF gv_restored > 0. COMMIT WORK AND WAIT. ENDIF.

  TRY. lv_log_id = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. ENDTRY.

  CLEAR ls_alog.
  ls_alog-log_id     = lv_log_id.
  ls_alog-arch_id    = lv_arch_id.
  ls_alog-table_name = gv_tabname.
  ls_alog-action     = 'RESTORE'.
  ls_alog-rec_count  = gv_restored.
  ls_alog-status     = COND #( WHEN gv_errors = 0 THEN 'S' ELSE 'W' ).
  ls_alog-start_time = lv_ts_s.
  GET TIME STAMP FIELD ls_alog-end_time.
  ls_alog-message    = |Restored { gv_restored } records to { gv_tabname }. Errors: { gv_errors }|.
  ls_alog-exec_user  = sy-uname.
  ls_alog-exec_date  = sy-datum.
  INSERT zsp26_arch_log FROM ls_alog.
  COMMIT WORK AND WAIT.

  MESSAGE |Restore xong: { gv_restored } records về { gv_tabname }. Lỗi: { gv_errors }|
          TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_MONITOR — Storage Analysis & Monitoring (Feature 3)
*& Scans all active configs → counts live+archive stats → ARCH_STAT
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& FORM DO_MONITOR — Storage Analysis & Monitoring (Enhanced)
*&   Phase 1: Fix duplicates  — GROUP BY table_name
*&   Phase 2: Extra columns   — arch_recs, del_recs, pct_saved,
*&                               last_arch_d, last_del_d, status_txt
*&   Phase 3: Traffic light   — OVERDUE(red) / WARNING(yellow) / OK(green)
*&   Phase 4: Detail Log btn  — drill-down to ZSP26_ARCH_LOG per table
*&---------------------------------------------------------------------*
FORM do_monitor.
  DATA: ls_disp   TYPE ty_mon_disp,
        lv_cnt    TYPE i,
        lv_total  TYPE p DECIMALS 1,
        lv_cutoff TYPE d.             " cutoff date for WARNING check (sy-datum - 30)

  CLEAR gt_mon_disp.
  lv_cutoff = sy-datum - 30.          " compute once; sy-datum-30 is integer, not date

  " ── Phase 1: Aggregate config per table — avoid duplicate rows ───────
  TYPES: BEGIN OF ty_cfg_sum,
           table_name TYPE tabname,
           retention  TYPE i,
           is_active  TYPE char1,
         END OF ty_cfg_sum.
  DATA: lt_cfg_sum TYPE TABLE OF ty_cfg_sum.

  SELECT table_name,
         MAX( retention ) AS retention,
         MAX( is_active ) AS is_active
    FROM zsp26_arch_cfg
    GROUP BY table_name
    INTO TABLE @lt_cfg_sum.
  SORT lt_cfg_sum BY table_name.

  IF lt_cfg_sum IS INITIAL.
    MESSAGE 'Chưa có config nào. Chạy ZSP26_LOAD_SAMPLE_DATA.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT lt_cfg_sum INTO DATA(ls_cfg).
    CLEAR ls_disp.
    ls_disp-table_name = ls_cfg-table_name.
    ls_disp-retention  = ls_cfg-retention.
    ls_disp-is_active  = ls_cfg-is_active.

    " Live records in source table (dynamic SQL)
    TRY.
      SELECT COUNT(*) FROM (ls_cfg-table_name) INTO @lv_cnt.
      ls_disp-live_recs = lv_cnt.
    CATCH cx_sy_dynamic_osql_error.
      ls_disp-live_recs = -1.
    ENDTRY.

    " ── Phase 2a: Archived & Deleted record counts ───────────────────
    " SUM(rec_count) từ log — ZSP26_ARCH_DATA chỉ có data khi ADK write thực
    SELECT SUM( rec_count ) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'ARCHIVE'.
    ls_disp-arch_recs = lv_cnt.

    SELECT SUM( rec_count ) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'DELETE'.
    ls_disp-del_recs = lv_cnt.

    " % Archived = arch_recs / (live + arch) * 100
    lv_total = ls_disp-live_recs + ls_disp-arch_recs.
    IF lv_total > 0 AND ls_disp-live_recs >= 0.
      ls_disp-pct_saved = ( ls_disp-arch_recs / lv_total ) * 100.
    ENDIF.

    " Archive / Restore / Delete run counts from log
    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'ARCHIVE'.
    ls_disp-arch_runs = lv_cnt.

    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'RESTORE'.
    ls_disp-rest_runs = lv_cnt.

    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'DELETE'.
    ls_disp-del_runs = lv_cnt.

    " Last activity overall (date + user + action)
    SELECT exec_date, exec_user, action FROM zsp26_arch_log
      INTO (@ls_disp-last_date, @ls_disp-last_user, @ls_disp-last_action)
      WHERE table_name = @ls_cfg-table_name
      ORDER BY exec_date DESCENDING.
      EXIT.
    ENDSELECT.

    " ── Phase 2b: Last ARCHIVE date (separate) ───────────────────────
    SELECT exec_date FROM zsp26_arch_log
      INTO @ls_disp-last_arch_d
      WHERE table_name = @ls_cfg-table_name AND action = 'ARCHIVE'
      ORDER BY exec_date DESCENDING.
      EXIT.
    ENDSELECT.

    " Last DELETE date (separate)
    SELECT exec_date FROM zsp26_arch_log
      INTO @ls_disp-last_del_d
      WHERE table_name = @ls_cfg-table_name AND action = 'DELETE'
      ORDER BY exec_date DESCENDING.
      EXIT.
    ENDSELECT.

    " ── Phase 2c/3: Status text + traffic light (INCLUDE icon in main)
    IF ls_disp-live_recs < 0.
      ls_disp-status_txt  = 'ERROR'.
      ls_disp-status_icon = icon_led_red.
    ELSEIF ls_disp-arch_runs = 0 AND ls_disp-is_active = 'X'.
      ls_disp-status_txt  = 'OVERDUE'.
      ls_disp-status_icon = icon_led_red.
    ELSEIF ls_disp-is_active = 'X'
       AND ls_disp-last_arch_d IS NOT INITIAL
       AND ls_disp-last_arch_d < lv_cutoff.
      ls_disp-status_txt  = 'WARNING'.
      ls_disp-status_icon = icon_led_yellow.
    ELSE.
      ls_disp-status_txt  = 'OK'.
      ls_disp-status_icon = icon_led_green.
    ENDIF.

    APPEND ls_disp TO gt_mon_disp.

    " Snapshot to ZSP26_ARCH_STAT
    DATA: ls_stat TYPE zsp26_arch_stat.
    CLEAR ls_stat.
    TRY. ls_stat-stat_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_stat-table_name = ls_cfg-table_name.
    ls_stat-stat_date  = sy-datum.
    ls_stat-total_recs = ls_disp-live_recs.
    ls_stat-arch_recs  = ls_disp-arch_recs.   " SUM rec_count ARCHIVE
    ls_stat-rest_recs  = ls_disp-rest_runs.
    ls_stat-del_recs   = ls_disp-del_recs.    " SUM rec_count DELETE
    ls_stat-last_user  = ls_disp-last_user.
    INSERT zsp26_arch_stat FROM ls_stat.
  ENDLOOP.

  COMMIT WORK.

  " ── SALV Display ─────────────────────────────────────────────────────
  DATA: lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lo_funcs TYPE REF TO cl_salv_functions.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = go_mon_alv
      CHANGING  t_table      = gt_mon_disp ).

    lo_funcs = go_mon_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    " ── Phase 4: Detail Log custom button ────────────────────────────
    TRY.
      lo_funcs->add_function(
        name     = 'MON_DETAIL'
        icon     = '@2I@'
        text     = 'Detail Log'
        tooltip  = 'Xem log chi tiết cho bảng được chọn'
        position = if_salv_c_function_position=>right_of_salv_functions ).
    CATCH cx_salv_method_not_supported
          cx_salv_wrong_call
          cx_salv_existing. ENDTRY.
    SET HANDLER lcl_mon_handler=>on_func FOR go_mon_alv->get_event( ).

    lo_cols = go_mon_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).  lo_col->set_long_text( 'Table Name' ).
      lo_col ?= lo_cols->get_column( 'STATUS_ICON' ).
      lo_col->set_long_text( 'Status' ).
      lo_col->set_icon( if_salv_c_bool_sap=>true ).
      lo_col ?= lo_cols->get_column( 'STATUS_TXT' ).
      lo_col->set_visible( if_salv_c_bool_sap=>false ).
      lo_col ?= lo_cols->get_column( 'LIVE_RECS' ).   lo_col->set_long_text( 'Live Records' ).
      lo_col ?= lo_cols->get_column( 'ARCH_RECS' ).   lo_col->set_long_text( 'Archived Recs' ).
      lo_col ?= lo_cols->get_column( 'DEL_RECS' ).    lo_col->set_long_text( 'Deleted Recs' ).
      lo_col ?= lo_cols->get_column( 'PCT_SAVED' ).   lo_col->set_long_text( '% Archived' ).
      lo_col ?= lo_cols->get_column( 'ARCH_RUNS' ).   lo_col->set_long_text( 'Archive Runs' ).
      lo_col ?= lo_cols->get_column( 'REST_RUNS' ).   lo_col->set_long_text( 'Restore Runs' ).
      lo_col ?= lo_cols->get_column( 'DEL_RUNS' ).    lo_col->set_long_text( 'Delete Runs' ).
      lo_col ?= lo_cols->get_column( 'LAST_ACTION' ). lo_col->set_long_text( 'Last Action' ).
      lo_col ?= lo_cols->get_column( 'LAST_DATE' ).   lo_col->set_long_text( 'Last Date' ).
      lo_col ?= lo_cols->get_column( 'LAST_ARCH_D' ). lo_col->set_long_text( 'Last Archive' ).
      lo_col ?= lo_cols->get_column( 'LAST_DEL_D' ).  lo_col->set_long_text( 'Last Delete' ).
      lo_col ?= lo_cols->get_column( 'LAST_USER' ).   lo_col->set_long_text( 'Last User' ).
      lo_col ?= lo_cols->get_column( 'RETENTION' ).   lo_col->set_long_text( 'Retention (days)' ).
      lo_col ?= lo_cols->get_column( 'IS_ACTIVE' ).   lo_col->set_long_text( 'Active' ).
    CATCH cx_salv_not_found. ENDTRY.

    lo_disp = go_mon_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |STORAGE ANALYSIS & MONITORING — { lines( gt_mon_disp ) } tables — { sy-datum }| ).
    go_mon_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM SHOW_MON_DETAIL — Phase 4: Detail Log popup for selected table
*&---------------------------------------------------------------------*
FORM show_mon_detail USING iv_table TYPE tabname.
  TYPES: BEGIN OF ty_log_row,
           exec_date TYPE d,
           exec_user TYPE xubname,
           action    TYPE char10,
           rec_count TYPE i,
           status    TYPE char1,
           message   TYPE char255,
         END OF ty_log_row.

  DATA: lt_log  TYPE TABLE OF ty_log_row,
        lo_alv  TYPE REF TO cl_salv_table,
        lo_cols TYPE REF TO cl_salv_columns_table,
        lo_col  TYPE REF TO cl_salv_column_table,
        lo_disp TYPE REF TO cl_salv_display_settings.

  SELECT exec_date, exec_user, action, rec_count, status, message
    FROM zsp26_arch_log
    INTO TABLE @lt_log
    WHERE table_name = @iv_table
    ORDER BY exec_date DESCENDING.

  IF lt_log IS INITIAL.
    MESSAGE |Không có log nào cho bảng { iv_table }.| TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_log ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'EXEC_DATE' ).  lo_col->set_long_text( 'Date' ).
      lo_col ?= lo_cols->get_column( 'EXEC_USER' ).  lo_col->set_long_text( 'User' ).
      lo_col ?= lo_cols->get_column( 'ACTION' ).     lo_col->set_long_text( 'Action' ).
      lo_col ?= lo_cols->get_column( 'REC_COUNT' ).  lo_col->set_long_text( 'Records' ).
      lo_col ?= lo_cols->get_column( 'STATUS' ).     lo_col->set_long_text( 'Status' ).
      lo_col ?= lo_cols->get_column( 'MESSAGE' ).    lo_col->set_long_text( 'Message' ).
    CATCH cx_salv_not_found. ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |DETAIL LOG: { iv_table } — { lines( lt_log ) } entries| ).
    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx2).
    MESSAGE lx2->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_CONFIG — Phase 1: Xem & Maintain ZSP26_ARCH_CFG
*&---------------------------------------------------------------------*
FORM do_config.
  DATA: lt_cfg   TYPE TABLE OF zsp26_arch_cfg,
        lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_funcs TYPE REF TO cl_salv_functions,
        lo_disp  TYPE REF TO cl_salv_display_settings.

  SELECT * FROM zsp26_arch_cfg INTO TABLE lt_cfg ORDER BY table_name.

  IF lt_cfg IS INITIAL.
    MESSAGE 'Chưa có config nào. Chạy ZSP26_LOAD_SAMPLE_DATA để tạo.' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_cfg ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).
    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'CONFIG_ID' ).   lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'MANDT' ).        lo_col->set_visible( abap_false ).
      lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
      lo_col->set_long_text( 'Table Name' ).
      lo_col ?= lo_cols->get_column( 'DESCRIPTION' ).
      lo_col->set_long_text( 'Description' ).
      lo_col ?= lo_cols->get_column( 'RETENTION' ).
      lo_col->set_long_text( 'Retention (days)' ).
      lo_col ?= lo_cols->get_column( 'DATA_FIELD' ).
      lo_col->set_long_text( 'Date Field' ).
      lo_col ?= lo_cols->get_column( 'IS_ACTIVE' ).
      lo_col->set_long_text( 'Active' ).
    CATCH cx_salv_not_found.
    ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |ARCHIVE CONFIG — { lines( lt_cfg ) } entries | &&
      |/ Để sửa: chạy Z_CONFIG_Z15_EKKO (SE38)| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM GET_DATA — đọc thống kê cho screen 0200 ALV
*&---------------------------------------------------------------------*
FORM get_data.
  DATA: lv_cnt     TYPE i,
        lv_tabname TYPE zsp26_arch_log-table_name.

  CLEAR gt_arch_stat.

  SELECT DISTINCT table_name FROM zsp26_arch_log
    INTO TABLE @DATA(lt_tables).

  LOOP AT lt_tables INTO DATA(ls_tab).
    lv_tabname = ls_tab-table_name.
    APPEND INITIAL LINE TO gt_arch_stat ASSIGNING FIELD-SYMBOL(<stat>).
    <stat>-table_name = lv_tabname.

    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @lv_tabname AND action = 'ARCHIVE'.
    <stat>-cnt_archived = lv_cnt.

    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @lv_tabname AND action = 'RESTORE'.
    <stat>-cnt_restored = lv_cnt.

    SELECT COUNT(*) FROM zsp26_arch_data INTO @lv_cnt
      WHERE table_name = @lv_tabname AND arch_status = 'A'.
    <stat>-cnt_active = lv_cnt.

    SELECT exec_date, exec_user, action FROM zsp26_arch_log
      INTO (@<stat>-last_arch_on, @<stat>-last_arch_by, @<stat>-last_action)
      WHERE table_name = @lv_tabname ORDER BY exec_date DESCENDING.
      EXIT.
    ENDSELECT.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM BUILD_FIELDCAT — cột cho ALV screen 0200
*&---------------------------------------------------------------------*
FORM build_fieldcat.
  DATA: ls_fc TYPE lvc_s_fcat.
  CLEAR gt_fcat_200.

  DEFINE m_col.
    CLEAR ls_fc.
    ls_fc-fieldname = &1.
    ls_fc-coltext   = &2.
    ls_fc-outputlen = &3.
    APPEND ls_fc TO gt_fcat_200.
  END-OF-DEFINITION.

  m_col 'TABLE_NAME'   'Table Name'         20.
  m_col 'CNT_ARCHIVED' 'Total Archived'     14.
  m_col 'CNT_RESTORED' 'Total Restored'     14.
  m_col 'CNT_ACTIVE'   'Active in Archive'  18.
  m_col 'LAST_ARCH_ON' 'Last Activity Date' 18.
  m_col 'LAST_ARCH_BY' 'Last By'            12.
  m_col 'LAST_ACTION'  'Last Action'        12.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DISPLAY_ALV — hiển thị ALV trong container screen 0200
*&---------------------------------------------------------------------*
FORM display_alv.
  IF go_cont_200 IS BOUND.
    go_cont_200->free( ).
    CLEAR: go_cont_200, go_alv_200.
  ENDIF.

  CREATE OBJECT go_cont_200
    EXPORTING container_name = 'ALV_CONTAINER'
    EXCEPTIONS OTHERS        = 1.

  IF sy-subrc <> 0.
    MESSAGE 'Lỗi tạo container ALV' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CREATE OBJECT go_alv_200
    EXPORTING i_parent = go_cont_200
    EXCEPTIONS OTHERS  = 1.
  IF sy-subrc <> 0. RETURN. ENDIF.

  CALL METHOD go_alv_200->set_table_for_first_display
    CHANGING it_outtab       = gt_arch_stat
             it_fieldcatalog = gt_fcat_200.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM GET_ARCHIVE_PROGRAMS — đọc Write/Delete program từ ARCH_OBJ
*&---------------------------------------------------------------------*
FORM get_archive_programs.
  SELECT SINGLE reorga_prg, delete_prg FROM arch_obj
    INTO (@gv_prog_write, @gv_prog_del)
    WHERE object = @gv_object.

  IF sy-subrc <> 0.
    CLEAR: gv_prog_write, gv_prog_del.
    MESSAGE 'Archiving Object không hợp lệ hoặc chưa cấu hình trong AOBJ'
            TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM MAINTENANCE_SPOOL_PARAMS
*&  (ARCHIVE_ADMIN_SET_PRINT_PARAMS không tồn tại trên hầu hết hệ thống)
*&  Dùng GET_PRINT_PARAMETERS (SAPLSPRI) — hộp thoại spool + archive list.
*&---------------------------------------------------------------------*
FORM maintenance_spool_params.
  DATA: ls_pri   TYPE pri_params,
        ls_arc   TYPE arc_params,
        lv_valid TYPE char1,
        lv_rep   TYPE programm.

  lv_rep = COND #(
    WHEN sy-dynnr = '0600' AND gv_prog_del IS NOT INITIAL
    THEN gv_prog_del
    WHEN gv_prog_write IS NOT INITIAL
    THEN gv_prog_write
    ELSE sy-repid ).

  CALL FUNCTION 'GET_PRINT_PARAMETERS'
    EXPORTING
      report    = lv_rep
      ar_object = gv_object
    IMPORTING
      out_parameters         = ls_pri
      out_archive_parameters = ls_arc
      valid                  = lv_valid
    EXCEPTIONS
      archive_info_not_found = 1
      OTHERS                 = 2.

  IF sy-subrc <> 0.
    CLEAR: ls_pri, ls_arc, lv_valid.
    CALL FUNCTION 'GET_PRINT_PARAMETERS'
      EXPORTING
        report = lv_rep
      IMPORTING
        out_parameters = ls_pri
        valid            = lv_valid
      EXCEPTIONS
        OTHERS = 2.
  ENDIF.

  IF sy-subrc = 0 AND lv_valid = 'X'.
    gv_spool_set = 'X'.
    MESSAGE 'Đã thiết lập tham số máy in (Spool)' TYPE 'S'.
  ELSEIF sy-subrc = 0.
    MESSAGE 'Đã hủy hoặc tham số spool không hợp lệ' TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    MESSAGE 'Không gọi được GET_PRINT_PARAMETERS' TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM MAINTENANCE_START_DATE
*&  Chuẩn SAP: BP_START_DATE_EDITOR — cùng hộp thoại "Start Time" như
*&  job scheduling (Immediate / Date/Time / After job / Event / …).
*&  Không dùng POPUP_GET_VALUES + SYST-DATUM (dễ hỏng format F4 / hiển thị).
*&---------------------------------------------------------------------*
FORM maintenance_start_date.
  CONSTANTS:
    gc_btc_yes            TYPE c LENGTH 1 VALUE 'Y', " BTC_YES
    gc_btc_edit_startdate TYPE i VALUE 14.           " BTC_EDIT_STARTDATE (SE37 / type pool BTC)

  DATA: lv_mod TYPE i.

  " STDT_TITLE không có trên một số bản kernel / FM — gây CALL_FUNCTION_PARM_UNKNOWN.
  CALL FUNCTION 'BP_START_DATE_EDITOR'
    EXPORTING
      stdt_dialog = gc_btc_yes
      stdt_opcode = gc_btc_edit_startdate
      stdt_input  = gs_btc_start
    IMPORTING
      stdt_output      = gs_btc_start
      stdt_modify_type = lv_mod
    EXCEPTIONS
      OTHERS           = 1.

  IF sy-subrc <> 0.
    MESSAGE 'Không mở được hộp thoại Start Time (BP_START_DATE_EDITOR).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  gv_start_date = 'X'.
  MESSAGE 'Đã thiết lập thời gian bắt đầu (chuẩn lập lịch job)' TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM CHECK_DEPENDENCIES — Feature 2: Dependency Check
*& Reads ZSP26_ARCH_DEP for the current table, counts child records,
*& and shows a confirmation popup if dependent data exists.
*& cv_ok = abap_false if the user cancels → archive is skipped.
*&---------------------------------------------------------------------*
FORM check_dependencies
  CHANGING cv_ok TYPE abap_bool.

  cv_ok = abap_true.

  DATA: lt_dep       TYPE TABLE OF zsp26_arch_dep,
        ls_dep       TYPE zsp26_arch_dep,
        lv_child_cnt TYPE i,
        lv_total     TYPE i VALUE 0,
        lv_dep_info  TYPE string,
        lv_answer    TYPE c.

  SELECT * FROM zsp26_arch_dep INTO TABLE @lt_dep
    WHERE parent_table = @gv_tabname.

  IF lt_dep IS INITIAL.
    RETURN.     " no dependencies configured → always proceed
  ENDIF.

  LOOP AT lt_dep INTO ls_dep.
    CLEAR lv_child_cnt.
    TRY.
      SELECT COUNT(*) FROM (ls_dep-child_table) INTO @lv_child_cnt.
      IF lv_child_cnt > 0.
        ADD lv_child_cnt TO lv_total.
        lv_dep_info &&= |{ ls_dep-child_table }: { lv_child_cnt } records  |.
      ENDIF.
    CATCH cx_sy_dynamic_osql_error.
      " Child table may not exist in this system — skip
    ENDTRY.
  ENDLOOP.

  IF lv_total = 0.
    RETURN.     " no child records → safe to proceed
  ENDIF.

  " Warn user — let them decide
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Dependency Check Warning'
      text_question         = |{ gv_tabname } has dependent child records ({ lv_total } total). Archive anyway?|
      text_button_1         = 'Yes, Archive'
      text_button_2         = 'No'
      default_button        = '2'
      display_cancel_button = ' '
    IMPORTING
      answer                = lv_answer
    EXCEPTIONS
      OTHERS                = 1.

  IF lv_answer <> '1'.
    cv_ok = abap_false.
    MESSAGE |Archive cancelled. Dependent records exist: { lv_dep_info }|
            TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM F4_GV_TABNAME_DYNP — F4 ô GV_TABNAME (dynpro 0400), khớp ZSP26_SH_TABLES
*&---------------------------------------------------------------------*
FORM f4_gv_tabname_dynp.
  TYPES: BEGIN OF ty_sht_f4,
           table_name  TYPE tabname,
           description TYPE char80,
           is_active   TYPE zsp26_de_xflag,
         END OF ty_sht_f4.
  DATA lt_sht TYPE STANDARD TABLE OF ty_sht_f4 WITH DEFAULT KEY.

  SELECT table_name, description, is_active
    FROM zsp26_arch_cfg
    WHERE is_active = 'X'
    INTO CORRESPONDING FIELDS OF TABLE @lt_sht
    UP TO 999 ROWS.
  IF lt_sht IS INITIAL.
    SELECT table_name, description, is_active
      FROM zsp26_arch_cfg
      INTO CORRESPONDING FIELDS OF TABLE @lt_sht
      UP TO 999 ROWS.
  ENDIF.
  SORT lt_sht BY table_name.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'TABLE_NAME'
      window_title = 'Tables in ZSP26_ARCH_CFG'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'GV_TABNAME'
      value_org    = 'S'
    TABLES
      value_tab    = lt_sht
    EXCEPTIONS
      OTHERS       = 0.
ENDFORM.

*&---------------------------------------------------------------------*
*& Màn 0500 — Edit variant: Create / Change / Delete / Copy (chỉ POPUP_TO_CONFIRM).
*& Tên form đổi để tránh trùng bản cũ trên SAP còn gọi POPUP_TO_DECIDE.
*&---------------------------------------------------------------------*
FORM zsp26_hub_edit_wvar_0500.
  DATA: lv_vtech TYPE variant,
        lv_vok   TYPE abap_bool,
        lv_rc    TYPE sy-subrc,
        lv_run   TYPE variant,
        lv_ans   TYPE char1,
        lv_ans2  TYPE char1,
        lv_ok    TYPE abap_bool,
        lv_msg   TYPE string.

  IF gv_variant IS INITIAL.
    MESSAGE 'Vui lòng nhập Variant ID' TYPE 'I'.
    RETURN.
  ENDIF.
  IF gv_tabname IS INITIAL.
    MESSAGE 'Chọn bảng archive trước khi chỉnh Variant' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF gv_prog_write IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.
  IF gv_prog_write IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM arch_build_write_var_tech
    USING gv_tabname gv_variant
    CHANGING lv_vtech lv_vok.
  IF lv_vok = abap_false.
    MESSAGE 'Variant ID không hợp lệ hoặc quá dài (tên VARID tối đa 14 ký tự, gồm tiền tố bảng).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR lv_run.
  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      report  = gv_prog_write
      variant = lv_vtech
    IMPORTING
      r_c     = lv_rc.
  IF lv_rc = 0.
    lv_run = lv_vtech.
  ELSE.
    CALL FUNCTION 'RS_VARIANT_EXISTS'
      EXPORTING
        report  = gv_prog_write
        variant = gv_variant
      IMPORTING
        r_c     = lv_rc.
    IF lv_rc = 0.
      lv_run = gv_variant.
    ENDIF.
  ENDIF.

  IF lv_run IS INITIAL.
    PERFORM arch_variant_msg_labels
      USING gv_tabname gv_variant lv_vtech
      CHANGING lv_msg.
    lv_msg = lv_msg && | Chưa tồn tại. Tạo variant SAP?|.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Create Variant'
        text_question         = lv_msg
        text_button_1         = 'Create Variant'
        text_button_2         = 'Cancel'
        display_cancel_button = ' '
      IMPORTING
        answer                = lv_ans
      EXCEPTIONS
        OTHERS                = 1.
    IF lv_ans <> '1'.
      RETURN.
    ENDIF.
    PERFORM arch_ensure_write_variant
      USING gv_prog_write lv_vtech gv_tabname
      CHANGING lv_ok.
    IF lv_ok = abap_false.
      PERFORM arch_variant_msg_labels
        USING gv_tabname gv_variant lv_vtech
        CHANGING lv_msg.
      MESSAGE |Không tạo được variant. { lv_msg } Kiểm tra quyền variant.| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    SUBMIT (gv_prog_write)
      WITH p_table = gv_tabname
      USING SELECTION-SET lv_vtech
      VIA SELECTION-SCREEN
      AND RETURN.
    RETURN.
  ENDIF.

  PERFORM arch_variant_msg_labels
    USING gv_tabname gv_variant lv_run
    CHANGING lv_msg.
  lv_msg = lv_msg && | Mở màn selection để sửa?|.
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Variant'
      text_question         = lv_msg
      text_button_1         = 'Change'
      text_button_2         = 'Other actions'
      display_cancel_button = ' '
    IMPORTING
      answer                = lv_ans
    EXCEPTIONS
      OTHERS                = 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  IF lv_ans = '1'.
    SUBMIT (gv_prog_write)
      WITH p_table = gv_tabname
      USING SELECTION-SET lv_run
      VIA SELECTION-SCREEN
      AND RETURN.
    RETURN.
  ENDIF.

  PERFORM arch_variant_msg_labels
    USING gv_tabname gv_variant lv_run
    CHANGING lv_msg.
  lv_msg = lv_msg && | Xóa variant này?|.
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Variant'
      text_question         = lv_msg
      text_button_1         = 'Delete'
      text_button_2         = 'Skip'
      display_cancel_button = ' '
    IMPORTING
      answer                = lv_ans
    EXCEPTIONS
      OTHERS                = 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  IF lv_ans = '1'.
    IF lv_run = gv_variant.
      lv_msg = |Xóa vĩnh viễn VARID: { lv_run }? Không hoàn tác.|.
    ELSE.
      lv_msg = |Xóa vĩnh viễn VARID: { lv_run } (Variant ID ô nhập: { gv_variant })? Không hoàn tác.|.
    ENDIF.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Delete Variant'
        text_question         = lv_msg
        text_button_1         = 'Delete'
        text_button_2         = 'Cancel'
        display_cancel_button = ' '
      IMPORTING
        answer                = lv_ans2
      EXCEPTIONS
        OTHERS                = 1.
    IF lv_ans2 = '1'.
      CALL FUNCTION 'RS_VARIANT_DELETE'
        EXPORTING
          report             = gv_prog_write
          variant            = lv_run
          flag_confirmscreen = 'X'
        EXCEPTIONS
          OTHERS             = 9.
      IF sy-subrc = 0.
        COMMIT WORK AND WAIT.
        CLEAR gv_variant.
        MESSAGE |Deleted variant { lv_run }.| TYPE 'S'.
      ELSE.
        MESSAGE |Could not delete variant { lv_run }.| TYPE 'S' DISPLAY LIKE 'E'.
      ENDIF.
    ENDIF.
    RETURN.
  ENDIF.

  PERFORM arch_variant_msg_labels
    USING gv_tabname gv_variant lv_run
    CHANGING lv_msg.
  lv_msg = lv_msg && | Copy sang ID variant mới?|.
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Variant'
      text_question         = lv_msg
      text_button_1         = 'Copy'
      text_button_2         = 'Cancel'
      display_cancel_button = ' '
    IMPORTING
      answer                = lv_ans
    EXCEPTIONS
      OTHERS                = 1.
  IF sy-subrc <> 0 OR lv_ans <> '1'.
    RETURN.
  ENDIF.

  PERFORM arch_copy_write_variant_dialog
    USING gv_prog_write gv_tabname lv_run.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ARCH_COPY_WRITE_VARIANT_DIALOG — nhập tên logical mới → copy
*&---------------------------------------------------------------------*
FORM arch_copy_write_variant_dialog
  USING    iv_report  TYPE programm
           iv_tabname TYPE tabname
           iv_src     TYPE variant.

  DATA: lt_fields TYPE TABLE OF sval,
        ls_field  TYPE sval,
        lv_new    TYPE string,
        lv_tgt    TYPE variant,
        lv_ok     TYPE abap_bool,
        lv_rc     TYPE sy-subrc.

  CLEAR ls_field.
  ls_field-tabname   = '*'.
  ls_field-fieldname = 'NEWVAR'.
  ls_field-fieldtext = 'Variant ID (new, screen field)'.
  CLEAR ls_field-value.
  APPEND ls_field TO lt_fields.

  CALL FUNCTION 'POPUP_TO_GET_VALUES'
    EXPORTING
      popup_title = 'Copy variant (new Variant ID → new VARID)'
    TABLES
      fields = lt_fields
    EXCEPTIONS
      OTHERS = 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  READ TABLE lt_fields INTO ls_field INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  lv_new = ls_field-value.
  CONDENSE lv_new.
  IF lv_new IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM arch_build_write_var_tech
    USING iv_tabname lv_new
    CHANGING lv_tgt lv_ok.
  IF lv_ok = abap_false.
    MESSAGE 'Variant ID đích không hợp lệ hoặc quá dài.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      report  = iv_report
      variant = lv_tgt
    IMPORTING
      r_c     = lv_rc.
  IF lv_rc = 0.
    MESSAGE 'Variant đích đã tồn tại.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM arch_copy_write_variant
    USING iv_report iv_src lv_tgt iv_tabname
    CHANGING lv_ok.
  IF lv_ok = abap_false.
    MESSAGE |Copy failed for { lv_tgt }.| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  gv_variant = CONV variant( lv_new ).
  CONDENSE gv_variant NO-GAPS.
  TRANSLATE gv_variant TO UPPER CASE.
  MESSAGE |Đã copy. Variant ID (ô): { lv_new }. Tên VARID: { lv_tgt }.| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ARCH_COPY_WRITE_VARIANT — RS_VARIANT_CONTENTS → RS_CREATE_VARIANT
*&---------------------------------------------------------------------*
FORM arch_copy_write_variant
  USING    iv_report  TYPE programm
           iv_src     TYPE variant
           iv_tgt     TYPE variant
           iv_tabname TYPE tabname
  CHANGING cv_ok      TYPE abap_bool.

  DATA: lt_params TYPE TABLE OF rsparams,
        ls_varid  TYPE varid,
        lt_varit  TYPE TABLE OF varit,
        ls_varit  TYPE varit,
        lv_rep    TYPE syrepid,
        lv_hit    TYPE abap_bool,
        ls_param  TYPE rsparams.

  FIELD-SYMBOLS <p> TYPE rsparams.

  cv_ok = abap_false.
  IF iv_report IS INITIAL OR iv_src IS INITIAL OR iv_tgt IS INITIAL OR iv_tabname IS INITIAL.
    RETURN.
  ENDIF.
  lv_rep = iv_report.

  CALL FUNCTION 'RS_VARIANT_CONTENTS'
    EXPORTING
      report  = lv_rep
      variant = iv_src
    TABLES
      valutab = lt_params
    EXCEPTIONS
      OTHERS  = 99.
  IF sy-subrc <> 0 OR lt_params IS INITIAL.
    RETURN.
  ENDIF.

  lv_hit = abap_false.
  LOOP AT lt_params ASSIGNING <p> WHERE selname = 'P_TABLE'.
    lv_hit = abap_true.
    <p>-kind   = 'P'.
    <p>-sign   = 'I'.
    <p>-option = 'EQ'.
    <p>-low    = iv_tabname.
  ENDLOOP.
  IF lv_hit = abap_false.
    CLEAR ls_param.
    ls_param-selname = 'P_TABLE'.
    ls_param-kind    = 'P'.
    ls_param-sign    = 'I'.
    ls_param-option  = 'EQ'.
    ls_param-low     = iv_tabname.
    APPEND ls_param TO lt_params.
  ENDIF.

  lv_hit = abap_false.
  LOOP AT lt_params ASSIGNING <p> WHERE selname = 'P_TEST'.
    lv_hit = abap_true.
    <p>-kind   = 'P'.
    <p>-sign   = 'I'.
    <p>-option = 'EQ'.
    IF gv_test_mode = 'X'.
      <p>-low = 'X'.
    ELSE.
      CLEAR <p>-low.
    ENDIF.
  ENDLOOP.
  IF lv_hit = abap_false.
    CLEAR ls_param.
    ls_param-selname = 'P_TEST'.
    ls_param-kind    = 'P'.
    ls_param-sign    = 'I'.
    ls_param-option  = 'EQ'.
    IF gv_test_mode = 'X'.
      ls_param-low = 'X'.
    ENDIF.
    APPEND ls_param TO lt_params.
  ENDIF.

  CLEAR ls_varid.
  ls_varid-mandt      = sy-mandt.
  ls_varid-report     = lv_rep.
  ls_varid-variant    = iv_tgt.
  ls_varid-environmnt = 'A'.
  ls_varid-aedat      = sy-datum.
  ls_varid-aetime     = sy-uzeit.

  CLEAR ls_varit.
  ls_varit-mandt   = sy-mandt.
  ls_varit-langu   = sy-langu.
  ls_varit-report  = lv_rep.
  ls_varit-variant = iv_tgt.
  ls_varit-vtext   = |{ iv_tabname } /C { iv_src }|.
  APPEND ls_varit TO lt_varit.

  CALL FUNCTION 'RS_CREATE_VARIANT'
    EXPORTING
      curr_report               = lv_rep
      curr_variant              = iv_tgt
      vari_desc                 = ls_varid
    TABLES
      vari_contents             = lt_params
      vari_text                 = lt_varit
    EXCEPTIONS
      illegal_report_or_variant = 1
      illegal_variantname       = 2
      not_authorized            = 3
      not_executed              = 4
      report_not_existent       = 5
      report_not_supplied       = 6
      variant_exists            = 7
      variant_locked            = 8
      OTHERS                    = 9.

  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.
