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
      USING <row> gs_cfg-config_id
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
*& Variant Z_ARCH_EKK_WRITE — tách theo bảng (SAP chỉ có report+variant)
*& Tên lưu VARID: {tab_prefix}_{logical} ≤14 ký tự, vd BKPF_VAR_01 / EKKO_VAR_01
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
        lv_mxp  TYPE i.

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

  IF sy-subrc = 0 OR sy-subrc = 7.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_VIA_ADK — gọi ADK Write Program (từ lcl_handler)
*&---------------------------------------------------------------------*
FORM do_archive_via_adk.
  DATA: lv_vtech TYPE variant,
        lv_vok   TYPE abap_bool.

  IF gv_variant IS NOT INITIAL.
    PERFORM arch_build_write_var_tech
      USING gv_tabname gv_variant
      CHANGING lv_vtech lv_vok.
    IF lv_vok = abap_false.
      MESSAGE 'Variant không hợp lệ hoặc quá dài (giới hạn tên SAP 14 ký tự).' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    SUBMIT z_arch_ekk_write
      WITH p_table = gv_tabname
      WITH p_test  = ' '
      USING SELECTION-SET lv_vtech
      AND RETURN.
  ELSE.
    SUBMIT z_arch_ekk_write
      WITH p_table = gv_tabname
      WITH p_test  = ' '
      AND RETURN.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_ARCHIVE_DELETE_JOB — SUBMIT delete program (ADK delete)
*&---------------------------------------------------------------------*
FORM do_archive_delete_job.
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
  ENDIF.

  IF gv_variant IS NOT INITIAL.
    SUBMIT (gv_prog_del)
      WITH p_table = gv_tabname
      WITH p_test  = gv_test_mode
      USING SELECTION-SET gv_variant
      AND RETURN.
  ELSE.
    SUBMIT (gv_prog_del)
      WITH p_table = gv_tabname
      WITH p_test  = gv_test_mode
      AND RETURN.
  ENDIF.
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
        lt_df  TYPE TABLE OF dynpread,
        ls_df  TYPE dynpread.

  IF gv_object IS INITIAL.
    gv_object = 'Z_ARCH_EKK'.
  ENDIF.
  lv_obj = gv_object.

  IF gv_prog_del IS INITIAL.
    PERFORM get_archive_programs.
  ENDIF.

  CLEAR: gv_f4_sess, gv_del_sess_def, gs_del_admi.

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

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'DOCUMENT'
      window_title = 'Archive Administration: Select Files for Delete Program'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'GV_F4_SESS'
      value_org    = 'S'
    TABLES
      value_tab    = lt_f4
    EXCEPTIONS
      OTHERS       = 0.

  CLEAR lt_df.
  ls_df-fieldname = 'GV_F4_SESS'.
  APPEND ls_df TO lt_df.
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING
      dyname     = sy-repid
      dynumb     = sy-dynnr
    TABLES
      dynpfields = lt_df
    EXCEPTIONS
      OTHERS     = 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  READ TABLE lt_df INTO ls_df INDEX 1.
  IF sy-subrc = 0.
    gv_f4_sess = ls_df-fieldvalue.
  ENDIF.
  CONDENSE gv_f4_sess.
  IF gv_f4_sess IS INITIAL.
    RETURN.
  ENDIF.

  READ TABLE lt_run INTO gs_del_admi
    WITH KEY client = sy-mandt object = lv_obj document = gv_f4_sess.
  IF sy-subrc <> 0.
    CLEAR gs_del_admi.
    MESSAGE 'Không khớp session đã chọn với ADMI_RUN.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  gv_del_sess_def = 'X'.

  EXPORT del_admi = gs_del_admi TO MEMORY ID 'Z_GSP18_ADMI_DEL'.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM DO_RESTORE_VIA_ADK — gọi ADK Read Program (từ lcl_handler)
*&---------------------------------------------------------------------*
FORM do_restore_via_adk.
  SUBMIT z_arch_ekk_read
    WITH p_table = gv_tabname
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
  " Launch ADK Read/Restore program — shows archived records from file
  SUBMIT z_arch_ekk_read
    WITH p_table = gv_tabname
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
FORM do_monitor.
  TYPES: BEGIN OF ty_stat_disp,
           table_name  TYPE tabname,
           live_recs   TYPE i,
           arch_runs   TYPE i,
           rest_runs   TYPE i,
           del_runs    TYPE i,
           last_action TYPE char10,
           last_date   TYPE d,
           last_user   TYPE xubname,
           retention   TYPE i,
           is_active   TYPE char1,
         END OF ty_stat_disp.

  DATA: lt_disp TYPE TABLE OF ty_stat_disp,
        ls_disp TYPE ty_stat_disp,
        lt_cfg  TYPE TABLE OF zsp26_arch_cfg,
        lv_cnt  TYPE i.

  SELECT * FROM zsp26_arch_cfg INTO TABLE @lt_cfg ORDER BY table_name.
  IF lt_cfg IS INITIAL.
    MESSAGE 'Chưa có config nào. Chạy ZSP26_LOAD_SAMPLE_DATA.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  LOOP AT lt_cfg INTO DATA(ls_cfg).
    CLEAR ls_disp.
    ls_disp-table_name = ls_cfg-table_name.
    ls_disp-retention  = ls_cfg-retention.
    ls_disp-is_active  = ls_cfg-is_active.

    " Live records in source table
    TRY.
      SELECT COUNT(*) FROM (ls_cfg-table_name) INTO @lv_cnt.
      ls_disp-live_recs = lv_cnt.
    CATCH cx_sy_dynamic_osql_error.
      ls_disp-live_recs = -1.
    ENDTRY.

    " Archive/Restore/Delete runs from log
    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'ARCHIVE'.
    ls_disp-arch_runs = lv_cnt.

    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'RESTORE'.
    ls_disp-rest_runs = lv_cnt.

    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @ls_cfg-table_name AND action = 'DELETE'.
    ls_disp-del_runs = lv_cnt.

    " Last activity
    SELECT exec_date, exec_user, action FROM zsp26_arch_log
      INTO (@ls_disp-last_date, @ls_disp-last_user, @ls_disp-last_action)
      WHERE table_name = @ls_cfg-table_name
      ORDER BY exec_date DESCENDING.
      EXIT.
    ENDSELECT.

    APPEND ls_disp TO lt_disp.

    " Write snapshot to ZSP26_ARCH_STAT
    DATA: ls_stat TYPE zsp26_arch_stat.
    CLEAR ls_stat.
    TRY. ls_stat-stat_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_stat-table_name = ls_cfg-table_name.
    ls_stat-stat_date  = sy-datum.
    ls_stat-total_recs = ls_disp-live_recs.
    ls_stat-arch_recs  = ls_disp-arch_runs.
    ls_stat-rest_recs  = ls_disp-rest_runs.
    ls_stat-del_recs   = ls_disp-del_runs.
    ls_stat-last_user  = ls_disp-last_user.
    INSERT zsp26_arch_stat FROM ls_stat.
  ENDLOOP.

  COMMIT WORK.

  " SALV Display
  DATA: lo_alv  TYPE REF TO cl_salv_table,
        lo_cols TYPE REF TO cl_salv_columns_table,
        lo_col  TYPE REF TO cl_salv_column_table,
        lo_disp TYPE REF TO cl_salv_display_settings.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_disp ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
      lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).  lo_col->set_long_text( 'Table Name' ).
      lo_col ?= lo_cols->get_column( 'LIVE_RECS' ).   lo_col->set_long_text( 'Live Records' ).
      lo_col ?= lo_cols->get_column( 'ARCH_RUNS' ).   lo_col->set_long_text( 'Archive Runs' ).
      lo_col ?= lo_cols->get_column( 'REST_RUNS' ).   lo_col->set_long_text( 'Restore Runs' ).
      lo_col ?= lo_cols->get_column( 'DEL_RUNS' ).    lo_col->set_long_text( 'Delete Runs' ).
      lo_col ?= lo_cols->get_column( 'LAST_ACTION' ). lo_col->set_long_text( 'Last Action' ).
      lo_col ?= lo_cols->get_column( 'LAST_DATE' ).   lo_col->set_long_text( 'Last Date' ).
      lo_col ?= lo_cols->get_column( 'LAST_USER' ).   lo_col->set_long_text( 'Last User' ).
      lo_col ?= lo_cols->get_column( 'RETENTION' ).   lo_col->set_long_text( 'Retention (days)' ).
      lo_col ?= lo_cols->get_column( 'IS_ACTIVE' ).   lo_col->set_long_text( 'Active' ).
    CATCH cx_salv_not_found. ENDTRY.

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |STORAGE ANALYSIS & MONITORING — { lines( lt_disp ) } tables — { sy-datum }| ).
    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
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
*&  SARA (lập lịch job: Immediate / Date/Time / After job / Event / …).
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
      titlebar       = 'Dependency Check Warning'
      text_question  = |{ gv_tabname } has dependent child records ({ lv_total } total). Archive anyway?|
      text_button_1  = 'Yes, Archive'
      text_button_2  = 'Cancel'
      default_button = '2'
      icon_button_1  = 'ICON_OKAY'
      icon_button_2  = 'ICON_CANCEL'
    IMPORTING
      answer         = lv_answer
    EXCEPTIONS
      OTHERS         = 1.

  IF lv_answer <> '1'.
    cv_ok = abap_false.
    MESSAGE |Archive cancelled. Dependent records exist: { lv_dep_info }|
            TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.
