*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_DELETE
*& ADK Delete — Archive Object Z_ARCH_EKK
*& Default: READ_OBJECT + ARCHIVE_GET_TABLE (matches Z_ARCH_EKK_WRITE PUT_TABLE)
*& ARCHIVE_GET_INFORMATION: metadata + USED_CLASSES (structure list in file)
*& Legacy: P_JSON = X → ty_arch_rec + ARCHIVE_GET_NEXT_RECORD (old WRITE_RECORD dumps)
*& DELETE (tab) FROM TABLE <itab> — key match per SAP rules; then ARCHIVE_DELETE_RECORD
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_delete.

INCLUDE z_gsp18_arch_dyn.

TYPES: BEGIN OF ty_arch_rec,
         rec_type   TYPE c LENGTH 1,
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_arch_rec.

TYPES: BEGIN OF ty_del_agg,
         table_name TYPE tabname,
         cnt        TYPE i,
       END OF ty_del_agg.
TYPES ty_del_agg_htab TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name.

DATA: ls_arec      TYPE ty_arch_rec,
      lv_cnt       TYPE i VALUE 0,
      lv_err       TYPE i VALUE 0,
      lt_del_agg   TYPE ty_del_agg_htab,
      lv_arch_h    TYPE syst-tabix,
      lv_obj       TYPE arch_obj-object VALUE 'Z_ARCH_EKK',
      lv_arch_name TYPE heada-arkey,
      lv_doc       TYPE admi_run-document,
      gr_dyn       TYPE REF TO data,
      lt_cfg_tabs  TYPE TABLE OF tabname,
      lv_cfg_tab   TYPE tabname,
      ls_hub_admi  TYPE admi_run,
      lv_open_obj  TYPE arch_obj-object,
      lv_arch_key  TYPE admi_files-archiv_key,
      lv_use_p_table TYPE abap_bool VALUE abap_true.

PARAMETERS: p_table TYPE tabname DEFAULT 'ZSP26_EKKO'.
PARAMETERS: p_test  TYPE c AS CHECKBOX DEFAULT 'X'.
PARAMETERS: p_json  TYPE c AS CHECKBOX DEFAULT ' '.
PARAMETERS: p_doc   TYPE admi_run-document.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  WRITE: / '=== ADK Delete: Z_ARCH_EKK ===' && ' p_table=' && p_table && ' p_json=' && p_json && ' ==='.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no DB delete ***'. ENDIF.
  WRITE: /.

  CLEAR: ls_hub_admi, lv_arch_key.
  lv_open_obj = lv_obj.

  IF p_doc IS NOT INITIAL.
    ls_hub_admi-object   = lv_obj.
    ls_hub_admi-document = p_doc.
  ELSE.
    IMPORT del_admi = ls_hub_admi FROM MEMORY ID 'Z_GSP18_ADMI_DEL'.
  ENDIF.
  IF ls_hub_admi-document IS NOT INITIAL.
    lv_use_p_table = abap_false.
    DATA: lt_af_dd   TYPE TABLE OF dfies,
          ls_af_dd   TYPE dfies,
          lv_where_af TYPE string,
          lv_col_obj  TYPE fieldname,
          lv_col_doc  TYPE fieldname,
          lv_col_cli  TYPE fieldname.

    WRITE: / 'Hub: ADMI session' && ` ` && ls_hub_admi-document && ` AOBJ ` && ls_hub_admi-object.
    lv_open_obj = ls_hub_admi-object.

    CLEAR lt_af_dd.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING
        tabname   = 'ADMI_FILES'
      TABLES
        dfies_tab = lt_af_dd
      EXCEPTIONS
        OTHERS    = 1.

    CLEAR: lv_col_obj, lv_col_doc, lv_col_cli.

    READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'OBJECT'.
    IF sy-subrc = 0.
      lv_col_obj = 'OBJECT'.
    ELSE.
      READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'AR_OBJECT'.
      IF sy-subrc = 0.
        lv_col_obj = 'AR_OBJECT'.
      ELSE.
        READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'ARCHIVE_OBJECT'.
        IF sy-subrc = 0.
          lv_col_obj = 'ARCHIVE_OBJECT'.
        ELSE.
          READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'ARCH_OBJECT'.
          IF sy-subrc = 0.
            lv_col_obj = 'ARCH_OBJECT'.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    " Ưu tiên ARCH_DOCID vì nhiều hệ lưu số session tại cột này;
    " DOCUMENT có thể mang định danh khác và dẫn tới lấy sai ARCHIV_KEY.
    READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'ARCH_DOCID'.
    IF sy-subrc = 0.
      lv_col_doc = 'ARCH_DOCID'.
    ELSE.
      READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOCUMENT'.
      IF sy-subrc = 0.
        lv_col_doc = 'DOCUMENT'.
      ELSE.
        READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOC_ID'.
        IF sy-subrc = 0.
          lv_col_doc = 'DOC_ID'.
        ELSE.
          READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOCID'.
          IF sy-subrc = 0.
            lv_col_doc = 'DOCID'.
          ELSE.
            READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'DOCUMENT_ID'.
            IF sy-subrc = 0.
              lv_col_doc = 'DOCUMENT_ID'.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'MANDT'.
    IF sy-subrc = 0.
      lv_col_cli = 'MANDT'.
    ELSE.
      READ TABLE lt_af_dd INTO ls_af_dd WITH KEY fieldname = 'CLIENT'.
      IF sy-subrc = 0.
        lv_col_cli = 'CLIENT'.
      ENDIF.
    ENDIF.

    IF lv_col_doc IS INITIAL.
      WRITE: / 'ADMI_FILES fields on this system:'.
      LOOP AT lt_af_dd INTO ls_af_dd.
        WRITE: / '  - ' && ls_af_dd-fieldname.
      ENDLOOP.
      MESSAGE 'Cấu trúc ADMI_FILES trên hệ này khác chuẩn (không thấy cột document).' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    lv_where_af = |{ lv_col_doc } = '{ ls_hub_admi-document }'|.

    " Một số hệ có cột object, một số hệ không có (như spool bạn gửi)
    IF lv_col_obj IS NOT INITIAL.
      lv_where_af = |{ lv_col_obj } = '{ ls_hub_admi-object }' AND | && lv_where_af.
    ENDIF.

    IF lv_col_cli IS NOT INITIAL.
      lv_where_af = |{ lv_col_cli } = '{ sy-mandt }' AND | && lv_where_af.
    ENDIF.

    SELECT SINGLE archiv_key
      FROM admi_files
      WHERE (lv_where_af)
      INTO @lv_arch_key.
    IF sy-subrc <> 0.
      " Fallback mềm: một số hệ lưu document theo format khác (ARCH_DOCID có hậu tố, hoặc khác cột ưu tiên).
      DATA: lt_af_scan TYPE TABLE OF admi_files,
            ls_af_scan TYPE admi_files,
            lv_doc_in  TYPE string,
            lv_doc_db  TYPE string,
            lv_ok_hit  TYPE abap_bool.
      FIELD-SYMBOLS: <fs_doc_any> TYPE any.

      lv_doc_in = ls_hub_admi-document.
      CONDENSE lv_doc_in.

      SELECT * FROM admi_files INTO TABLE @lt_af_scan UP TO 5000 ROWS.

      CLEAR lv_arch_key.
      lv_ok_hit = abap_false.
      LOOP AT lt_af_scan INTO ls_af_scan.
        CLEAR lv_doc_db.

        ASSIGN COMPONENT lv_col_doc OF STRUCTURE ls_af_scan TO <fs_doc_any>.
        IF sy-subrc = 0 AND <fs_doc_any> IS ASSIGNED.
          lv_doc_db = <fs_doc_any>.
          CONDENSE lv_doc_db.
        ENDIF.

        IF lv_doc_db IS INITIAL.
          ASSIGN COMPONENT 'DOCUMENT' OF STRUCTURE ls_af_scan TO <fs_doc_any>.
          IF sy-subrc = 0 AND <fs_doc_any> IS ASSIGNED.
            lv_doc_db = <fs_doc_any>.
            CONDENSE lv_doc_db.
          ENDIF.
        ENDIF.

        IF lv_doc_db IS INITIAL.
          ASSIGN COMPONENT 'ARCH_DOCID' OF STRUCTURE ls_af_scan TO <fs_doc_any>.
          IF sy-subrc = 0 AND <fs_doc_any> IS ASSIGNED.
            lv_doc_db = <fs_doc_any>.
            CONDENSE lv_doc_db.
          ENDIF.
        ENDIF.

        IF lv_doc_db IS INITIAL.
          CONTINUE.
        ENDIF.

        IF lv_doc_db = lv_doc_in OR lv_doc_db CS lv_doc_in OR lv_doc_in CS lv_doc_db.
          lv_arch_key = ls_af_scan-archiv_key.
          lv_ok_hit = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_ok_hit = abap_false OR lv_arch_key IS INITIAL.
        FREE MEMORY ID 'Z_GSP18_ADMI_DEL'.
        MESSAGE 'Không tìm thấy khóa file trong ADMI_FILES cho session đã chọn (OBJECT/DOCUMENT).' TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ENDIF.
    FREE MEMORY ID 'Z_GSP18_ADMI_DEL'.
  ENDIF.
  lv_obj = lv_open_obj.
  WRITE: /.

  IF p_json = 'X'.
    PERFORM run_delete_legacy_json.
    EXIT.
  ENDIF.

  DATA lv_open_rc TYPE sy-subrc.

  IF lv_arch_key IS NOT INITIAL.
    WRITE: / 'Resolved ARCHIV_KEY: ' && lv_arch_key.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
      EXPORTING
        aindflag     = space
        object       = lv_open_obj
        archive_name = lv_arch_key
        test_mode    = p_test
      IMPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        file_already_open     = 1
        file_io_error         = 2
        internal_error        = 3
        no_files_available    = 4
        object_not_found      = 5
        open_error            = 6
        not_authorized        = 7
        archiving_standard_violation = 8
        OTHERS                = 9.
    lv_open_rc = sy-subrc.
  ELSE.
    WRITE: / 'ARCHIV_KEY not resolved from ADMI_FILES. Try open by object only.'.
    lv_open_rc = 4.
  ENDIF.

  IF lv_open_rc <> 0.
    WRITE: / |Open by key failed, rc={ lv_open_rc }. Try open by object only.|.
    " Fallback: mở theo object khi key/session mapping khác format trên hệ thống.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
      EXPORTING
        aindflag     = space
        object       = lv_open_obj
        test_mode    = p_test
      IMPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        file_already_open     = 1
        file_io_error         = 2
        internal_error        = 3
        no_files_available    = 4
        object_not_found      = 5
        open_error            = 6
        not_authorized        = 7
        archiving_standard_violation = 8
        OTHERS                = 9.
    lv_open_rc = sy-subrc.
  ENDIF.

  IF lv_open_rc <> 0.
    WRITE: / |Open for delete failed rc={ lv_open_rc } object={ lv_open_obj } key={ lv_arch_key }|.
    CASE lv_open_rc.
      WHEN 4.
        MESSAGE 'Không mở được archive cho delete (không có file phù hợp).' TYPE 'S' DISPLAY LIKE 'E'.
      WHEN 5.
        MESSAGE 'Không tìm thấy đối tượng archive (AOBJ) hoặc chưa đăng ký.' TYPE 'S' DISPLAY LIKE 'E'.
      WHEN OTHERS.
        MESSAGE 'Không mở được archive cho delete (kiểm tra quyền, file, session).' TYPE 'S' DISPLAY LIKE 'E'.
    ENDCASE.
    RETURN.
  ENDIF.

  " Generic delete path: read ZSTR_ARCH_REC payload and delete by KEY_VALS
  DATA: lt_arch_gen TYPE TABLE OF zstr_arch_rec,
        ls_arch_gen TYPE zstr_arch_rec,
        lv_obj_h_gen TYPE syst-tabix,
        lt_pairs_gen TYPE TABLE OF string,
        lv_pair_gen  TYPE string,
        lv_kf_gen    TYPE string,
        lv_kv_gen    TYPE string,
        lv_where_gen TYPE string,
        lv_del_rc    TYPE i.

  DO.
    CLEAR lv_obj_h_gen.
    CALL FUNCTION 'ARCHIVE_READ_OBJECT'
      EXPORTING
        object = lv_obj
      IMPORTING
        archive_handle = lv_obj_h_gen
      EXCEPTIONS
        no_record_found           = 1
        file_io_error             = 2
        internal_error            = 3
        open_error                = 4
        cancelled_by_user         = 5
        object_not_found          = 6
        filename_creation_failure = 7
        file_already_open         = 8
        not_authorized            = 9
        file_not_found            = 10
        OTHERS                    = 11.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.

    REFRESH lt_arch_gen.
    CALL FUNCTION 'ARCHIVE_GET_TABLE'
      EXPORTING
        archive_handle        = lv_obj_h_gen
        record_structure      = 'ZSTR_ARCH_REC'
        all_records_of_object = 'X'
      TABLES
        table                 = lt_arch_gen
      EXCEPTIONS
        end_of_object           = 1
        internal_error          = 2
        wrong_access_to_archive = 3
        OTHERS                  = 4.
    IF sy-subrc <> 0 OR lt_arch_gen IS INITIAL.
      CONTINUE.
    ENDIF.

    LOOP AT lt_arch_gen INTO ls_arch_gen.
      CHECK ls_arch_gen-rec_type = 'D'.
      IF p_table IS NOT INITIAL AND ls_arch_gen-table_name <> p_table.
        CONTINUE.
      ENDIF.

      CLEAR: lv_where_gen, lv_pair_gen, lv_kf_gen, lv_kv_gen.
      REFRESH lt_pairs_gen.
      SPLIT ls_arch_gen-key_vals AT '|' INTO TABLE lt_pairs_gen.
      LOOP AT lt_pairs_gen INTO lv_pair_gen.
        SPLIT lv_pair_gen AT '=' INTO lv_kf_gen lv_kv_gen.
        CHECK lv_kf_gen IS NOT INITIAL.
        IF lv_where_gen IS NOT INITIAL.
          lv_where_gen = lv_where_gen && ' AND '.
        ENDIF.
        lv_where_gen = lv_where_gen && lv_kf_gen && ` EQ '` && lv_kv_gen && `'`.
      ENDLOOP.
      IF lv_where_gen IS INITIAL.
        ADD 1 TO lv_err.
        CONTINUE.
      ENDIF.
      lv_where_gen = |MANDT EQ '{ sy-mandt }' AND | && lv_where_gen.

      IF p_test = ' '.
        DELETE FROM (ls_arch_gen-table_name) WHERE (lv_where_gen).
        lv_del_rc = sy-subrc.
        IF lv_del_rc = 0 OR lv_del_rc = 4.
          CALL FUNCTION 'ARCHIVE_DELETE_RECORD' EXCEPTIONS OTHERS = 1.
          ADD 1 TO lv_cnt.
          PERFORM del_agg_bump_legacy USING lt_del_agg ls_arch_gen-table_name.
        ELSE.
          ADD 1 TO lv_err.
        ENDIF.
      ELSE.
        ADD 1 TO lv_cnt.
        WRITE: / '  [TEST] Would delete ' && ls_arch_gen-table_name && ' / ' && ls_arch_gen-key_vals.
      ENDIF.
    ENDLOOP.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_arch_h
    EXCEPTIONS
      OTHERS         = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_agg lv_err.
  ENDIF.

  WRITE: /.
  WRITE: / '=== Generic Summary: processed ' && lv_cnt && ' errors ' && lv_err && ' ==='.
  IF p_test = 'X'.
    WRITE: / 'Uncheck Test Mode to delete DB rows + log.'.
  ENDIF.
  RETURN.

  " USED_CLASSES must match FM typing (DDIC table type ADK_CLASSES), not TABLE OF arch_ddic
  " — avoids CALL_FUNCTION_CONFLICT_TAB_TYP (CX_SY_DYN_CALL_ILLEGAL_TYPE).
  DATA: lt_used    TYPE adk_classes,
        lv_tab_try TYPE tabname,
        lv_got     TYPE abap_bool,
        lv_obj_h   TYPE syst-tabix.

  CALL FUNCTION 'ARCHIVE_GET_INFORMATION'
    EXPORTING
      archive_handle = lv_arch_h
    IMPORTING
      archive_name     = lv_arch_name
      object           = lv_obj
      archive_document = lv_doc
    TABLES
      used_classes     = lt_used
    EXCEPTIONS
      internal_error          = 1
      wrong_access_to_archive = 2
      OTHERS                  = 3.

  WRITE: / 'GET_INFORMATION: obj ' && lv_obj && ' arch ' && lv_arch_name && ' doc ' && lv_doc && ' rc ' && sy-subrc.
  LOOP AT lt_used REFERENCE INTO DATA(lr_used).
    PERFORM adk_used_row_to_tabname USING lr_used->* CHANGING lv_tab_try.
    WRITE: / '  REGISTERED_DDIC_NAME: ' && lv_tab_try.
  ENDLOOP.
  CLEAR lv_tab_try.
  WRITE: /.

  DO.
    CLEAR lv_obj_h.
    " Handle từ OPEN_FOR_DELETE (lv_arch_h) không truyền vào READ_OBJECT — FM chỉ IMPORT OBJECT;
    " IMPORTING archive_handle = handle ngữ cảnh object (dùng cho GET_TABLE / DELETE_RECORD).
    CALL FUNCTION 'ARCHIVE_READ_OBJECT'
      EXPORTING
        object = lv_obj
      IMPORTING
        archive_handle = lv_obj_h
      EXCEPTIONS
        no_record_found           = 1
        file_io_error           = 2
        internal_error          = 3
        open_error              = 4
        cancelled_by_user       = 5
        object_not_found        = 6
        filename_creation_failure = 7
        file_already_open       = 8
        not_authorized          = 9
        file_not_found          = 10
        OTHERS                  = 11.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.

    CLEAR lv_got.

    " Nếu đã chọn cụ thể session/file: không ép p_table từ màn hình hub (có thể lệch object/file).
    IF lv_use_p_table = abap_true AND p_table IS NOT INITIAL.
      PERFORM process_one_arch_table USING lv_obj_h p_table p_test CHANGING lv_cnt lv_err lv_got.
    ENDIF.

    IF lv_got = abap_false.
      LOOP AT lt_used REFERENCE INTO DATA(lr_u).
        PERFORM adk_used_row_to_tabname USING lr_u->* CHANGING lv_tab_try.
        CHECK lv_tab_try IS NOT INITIAL.
        PERFORM process_one_arch_table USING lv_obj_h lv_tab_try p_test CHANGING lv_cnt lv_err lv_got.
        IF lv_got = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_got = abap_false.
      SELECT table_name FROM zsp26_arch_cfg INTO TABLE lt_cfg_tabs
        WHERE is_active = 'X'.
      LOOP AT lt_cfg_tabs INTO lv_cfg_tab.
        PERFORM process_one_arch_table USING lv_obj_h lv_cfg_tab p_test CHANGING lv_cnt lv_err lv_got.
        IF lv_got = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lv_got = abap_false.
      WRITE: / 'WARN: Could not ARCHIVE_GET_TABLE for this object (set P_TABLE or check registration).'.
      lv_err = lv_err + 1.
    ENDIF.
  ENDDO.

  " Một số hệ không có ARCHIVE_CLOSE_OBJECT (CALL_FUNCTION_NOT_FOUND) — dùng CLOSE_FILE như Z_ARCH_EKK_WRITE.
  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_arch_h
    EXCEPTIONS
      OTHERS         = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_agg lv_err.
  ENDIF.

  WRITE: /.
  WRITE: / '=== Summary: processed ' && lv_cnt && ' errors ' && lv_err && ' ==='.
  WRITE: / 'Lifecycle: DELETE step executed. Source DB rows matched by archive records were processed for deletion.'.
  IF p_test = 'X'. WRITE: / 'Uncheck Test Mode to delete DB rows + log.'. ENDIF.

*&---------------------------------------------------------------------*
*& DDIC row type of ADK_CLASSES is not always ARCH_DDIC (no -NAME on some releases).
*& Try common component names; convert first non-empty to TABNAME.
*&---------------------------------------------------------------------*
FORM adk_used_row_to_tabname USING    ps_row TYPE any
                               CHANGING cv_tab TYPE tabname.

  FIELD-SYMBOLS <fs_comp> TYPE any.
  DATA: lt_nm TYPE STANDARD TABLE OF string WITH EMPTY KEY,
        lv_nm TYPE string,
        lv_s  TYPE string.

  APPEND `NAME` TO lt_nm.
  APPEND `CLASS` TO lt_nm.
  APPEND `TABNAME` TO lt_nm.
  APPEND `STRUCTURE` TO lt_nm.
  APPEND `RECORD_STRUCTURE` TO lt_nm.
  APPEND `DDIC_NAME` TO lt_nm.
  APPEND `OBJ_CLASS` TO lt_nm.
  APPEND `ARCH_CLASS` TO lt_nm.

  CLEAR cv_tab.
  LOOP AT lt_nm INTO lv_nm.
    ASSIGN COMPONENT lv_nm OF STRUCTURE ps_row TO <fs_comp>.
    IF sy-subrc <> 0 OR <fs_comp> IS NOT ASSIGNED.
      CONTINUE.
    ENDIF.
    TRY.
        lv_s = CONV string( <fs_comp> ).
      CATCH cx_root.
        CONTINUE.
    ENDTRY.
    CONDENSE lv_s.
    IF strlen( lv_s ) = 0 OR strlen( lv_s ) > 30.
      CONTINUE.
    ENDIF.
    cv_tab = lv_s.
    TRANSLATE cv_tab TO UPPER CASE.
    RETURN.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
FORM process_one_arch_table
  USING    VALUE(pv_handle) TYPE syst-tabix
           VALUE(pv_tab)    TYPE tabname
           VALUE(pv_test)   TYPE c
  CHANGING cv_cnt TYPE i
           cv_err TYPE i
           cv_got TYPE abap_bool.

  DATA: lv_lines TYPE i,
        lv_t     TYPE i.

  " FM ARCHIVE_GET_TABLE — TABLES chỉ chấp nhận STANDARD TABLE (ANY TABLE → SYNTAX_ERROR).
  FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.

  cv_got = abap_false.
  TRY.
      CREATE DATA gr_dyn TYPE STANDARD TABLE OF (pv_tab).
    CATCH cx_sy_create_data_error.
      RETURN.
  ENDTRY.
  ASSIGN gr_dyn->* TO <lt>.
  REFRESH <lt>.

  TRY.
      CALL FUNCTION 'ARCHIVE_GET_TABLE'
        EXPORTING
          archive_handle           = pv_handle
          record_structure         = pv_tab
          all_records_of_object    = 'X'
        TABLES
          table                    = <lt>
        EXCEPTIONS
          end_of_object            = 1
          internal_error           = 2
          wrong_access_to_archive  = 3
          OTHERS                   = 4.
    CATCH cx_sy_dyn_call_illegal_type.
      WRITE: / '  WARN: ARCHIVE_GET_TABLE type conflict, skip tab ' && pv_tab.
      RETURN.
    CATCH cx_sy_dyn_call_illegal_func.
      WRITE: / '  WARN: ARCHIVE_GET_TABLE unavailable on this system.'.
      RETURN.
  ENDTRY.

  IF sy-subrc <> 0 OR <lt> IS INITIAL.
    RETURN.
  ENDIF.

  cv_got = abap_true.

  IF pv_test = ' '.
    DELETE (pv_tab) FROM TABLE <lt>.
    IF sy-subrc = 0 OR sy-subrc = 4.
      lv_lines = lines( <lt> ).
      cv_cnt = cv_cnt + lv_lines.
      PERFORM del_agg_add USING lt_del_agg pv_tab lv_lines.
      DO lv_lines TIMES.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD'
          EXCEPTIONS OTHERS = 1.
      ENDDO.
    ELSE.
      cv_err = cv_err + 1.
      WRITE: / '  ERR: DB delete failed, tab ' && pv_tab && ', rc ' && sy-subrc.
    ENDIF.
  ELSE.
    lv_t = lines( <lt> ).
    cv_cnt = cv_cnt + lv_t.
    WRITE: / '  [TEST] Would delete ' && lv_t && ' rows, tab ' && pv_tab.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM del_agg_add
  USING    ct_agg TYPE ty_del_agg_htab
           VALUE(pv_tab) TYPE tabname
           VALUE(pv_n) TYPE i.

  DATA ls TYPE ty_del_agg.

  FIELD-SYMBOLS: <dg> LIKE LINE OF ct_agg.
  READ TABLE ct_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + pv_n.
  ELSE.
    CLEAR ls.
    ls-table_name = pv_tab.
    ls-cnt        = pv_n.
    INSERT ls INTO TABLE ct_agg.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM flush_arch_log_delete
  USING    ct_agg TYPE ty_del_agg_htab
           VALUE(pv_err) TYPE i.

  DATA: ls_log TYPE zsp26_arch_log,
        ls_a   TYPE ty_del_agg,
        lv_ts  TYPE timestampl.
  GET TIME STAMP FIELD lv_ts.

  IF lines( ct_agg ) > 0.
    LOOP AT ct_agg INTO ls_a.
      CLEAR ls_log.
      TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error. ENDTRY.
      ls_log-table_name = ls_a-table_name.
      ls_log-action     = 'DELETE'.
      ls_log-rec_count  = ls_a-cnt.
      ls_log-status     = COND #( WHEN pv_err = 0 THEN 'S' ELSE 'W' ).
      ls_log-start_time = lv_ts.
      ls_log-end_time   = lv_ts.
      ls_log-exec_user  = sy-uname.
      ls_log-exec_date  = sy-datum.
      ls_log-message    = 'ADK DELETE (GET_TABLE): ' && ls_a-cnt && ' rows, tab ' && ls_a-table_name && '. err ' && pv_err.
      INSERT zsp26_arch_log FROM ls_log.
    ENDLOOP.
  ELSEIF pv_err > 0.
    CLEAR ls_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-table_name = 'Z_ARCH_EKK'.
    ls_log-action     = 'DELETE'.
    ls_log-rec_count  = 0.
    ls_log-status     = 'W'.
    ls_log-start_time = lv_ts.
    ls_log-end_time   = lv_ts.
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    ls_log-message    = 'ADK DELETE: errors ' && pv_err && ' (no row aggregates).'.
    INSERT zsp26_arch_log FROM ls_log.
  ENDIF.
  COMMIT WORK.
ENDFORM.

*&---------------------------------------------------------------------*
FORM run_delete_legacy_json.
  DATA: ls_arec_loc   TYPE ty_arch_rec,
        lv_where_loc  TYPE string,
        lv_cnt_loc    TYPE i VALUE 0,
        lv_err_loc    TYPE i VALUE 0,
        lt_pairs_loc  TYPE TABLE OF string,
        lv_pair_loc   TYPE string,
        lv_kf_loc     TYPE string,
        lv_kv_loc     TYPE string,
        lt_del_loc    TYPE ty_del_agg_htab,
        ls_del_loc    TYPE ty_del_agg,
        lv_leg_h      TYPE syst-tabix.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    IMPORTING
      archive_handle = lv_leg_h
    EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Không mở được archive (legacy / P_JSON).' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DO.
    CLEAR ls_arec_loc.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
      IMPORTING  record      = ls_arec_loc
      EXCEPTIONS end_of_file = 1
                 OTHERS      = 2.
    IF sy-subrc = 1. EXIT.
    ELSEIF sy-subrc > 1.
      ADD 1 TO lv_err_loc.
      CONTINUE.
    ENDIF.

    CHECK ls_arec_loc-rec_type = 'D'.

    CLEAR: lv_where_loc, lv_pair_loc, lv_kf_loc, lv_kv_loc.
    REFRESH lt_pairs_loc.
    SPLIT ls_arec_loc-key_vals AT '|' INTO TABLE lt_pairs_loc.
    LOOP AT lt_pairs_loc INTO lv_pair_loc.
      SPLIT lv_pair_loc AT '=' INTO lv_kf_loc lv_kv_loc.
      IF lv_where_loc IS NOT INITIAL. lv_where_loc &&= ' AND '. ENDIF.
      lv_where_loc &&= lv_kf_loc && ` EQ '` && lv_kv_loc && `'`.
    ENDLOOP.
    lv_where_loc = 'MANDT EQ ''' && sy-mandt && ''' AND ' && lv_where_loc.

    WRITE: / '  LEGACY ' && ls_arec_loc-table_name && ' / ' && ls_arec_loc-key_vals.

    IF p_test = ' '.
      DELETE FROM (ls_arec_loc-table_name) WHERE (lv_where_loc).
      IF sy-subrc = 0.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD' EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt_loc.
        PERFORM del_agg_bump_legacy USING lt_del_loc ls_arec_loc-table_name.
      ELSEIF sy-subrc = 4.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD' EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt_loc.
        PERFORM del_agg_bump_legacy USING lt_del_loc ls_arec_loc-table_name.
        WRITE: / '    INFO: already deleted'.
      ELSE.
        ADD 1 TO lv_err_loc.
      ENDIF.
    ELSE.
      ADD 1 TO lv_cnt_loc.
    ENDIF.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_leg_h
    EXCEPTIONS
      OTHERS         = 1.

  IF p_test = ' '.
    PERFORM flush_arch_log_delete USING lt_del_loc lv_err_loc.
  ENDIF.

  WRITE: / '=== Legacy JSON summary: ' && lv_cnt_loc && ' / err ' && lv_err_loc && ' ==='.
ENDFORM.

*&---------------------------------------------------------------------*
FORM del_agg_bump_legacy
  USING    ct_agg TYPE ty_del_agg_htab
           VALUE(pv_tab) TYPE tabname.

  DATA ls TYPE ty_del_agg.

  FIELD-SYMBOLS: <dg> LIKE LINE OF ct_agg.
  READ TABLE ct_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + 1.
  ELSE.
    CLEAR ls.
    ls-table_name = pv_tab.
    ls-cnt        = 1.
    INSERT ls INTO TABLE ct_agg.
  ENDIF.
ENDFORM.
