*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_CREATE_VARIANTS
*& One-time utility: creates report variants for Z_ARCH_EKK_WRITE (usable with archive scheduling)
*& Run once in SE38, then delete or keep for reference
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_create_variants.

TYPES: BEGIN OF ty_tbl,
         tabname   TYPE tabname,
         desc      TYPE char50,
       END OF ty_tbl.

DATA: lt_tables TYPE TABLE OF ty_tbl,
      ls_table  TYPE ty_tbl,
      lt_params TYPE TABLE OF rsparams,
      ls_param  TYPE rsparams,
      lv_vname  TYPE rvari,
      lv_vok    TYPE abap_bool.

PARAMETERS: p_report TYPE programm DEFAULT 'Z_ARCH_EKK_WRITE'.

*----------------------------------------------------------------------*
FORM zarc_var_prefix USING iv_tab TYPE tabname CHANGING cv_pfx TYPE string.
  cv_pfx = iv_tab.
  TRANSLATE cv_pfx TO UPPER CASE.
  CONDENSE cv_pfx NO-GAPS.
  IF strlen( cv_pfx ) >= 6 AND cv_pfx(6) = 'ZSP26_'.
    SHIFT cv_pfx BY 6 PLACES LEFT.
  ENDIF.
  IF strlen( cv_pfx ) > 8.
    cv_pfx = cv_pfx(8).
  ENDIF.
ENDFORM.

FORM zarc_var_tech
  USING    iv_tab TYPE tabname
           iv_log TYPE csequence
  CHANGING cv     TYPE rvari
           cv_ok  TYPE abap_bool.

  DATA: lv_pfx TYPE string,
        lv_log TYPE string,
        lv_ml  TYPE i,
        lv_mxp TYPE i,
        lv_f   TYPE string.

  CLEAR: cv, cv_ok.
  cv_ok = abap_false.

  lv_log = iv_log.
  TRANSLATE lv_log TO UPPER CASE.
  CONDENSE lv_log NO-GAPS.
  IF lv_log IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM zarc_var_prefix USING iv_tab CHANGING lv_pfx.
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

  lv_f = |{ lv_pfx }_{ lv_log }|.
  IF strlen( lv_f ) > 14.
    RETURN.
  ENDIF.

  cv = lv_f.
  TRANSLATE cv TO UPPER CASE.
  cv_ok = abap_true.
ENDFORM.

START-OF-SELECTION.

  " Define all 10 archive tables
  DEFINE add_tbl.
    CLEAR ls_table.
    ls_table-tabname = &1.
    ls_table-desc    = &2.
    APPEND ls_table TO lt_tables.
  END-OF-DEFINITION.

  add_tbl 'ZSP26_EKKO' 'Archive PO Header (EKKO)'.
  add_tbl 'ZSP26_EKPO' 'Archive PO Item (EKPO)'.
  add_tbl 'ZSP26_VBAK' 'Archive Sales Order Header (VBAK)'.
  add_tbl 'ZSP26_VBAP' 'Archive Sales Order Item (VBAP)'.
  add_tbl 'ZSP26_BKPF' 'Archive FI Doc Header (BKPF)'.
  add_tbl 'ZSP26_BSEG' 'Archive FI Doc Segment (BSEG)'.
  add_tbl 'ZSP26_MKPF' 'Archive Mat Doc Header (MKPF)'.
  add_tbl 'ZSP26_MSEG' 'Archive Mat Doc Segment (MSEG)'.
  add_tbl 'ZSP26_MARA' 'Archive Material Master (MARA)'.
  add_tbl 'ZSP26_KNA1' 'Archive Customer Master (KNA1)'.

  WRITE: / |Creating variants for report: { p_report }|.
  WRITE: /.

  LOOP AT lt_tables INTO ls_table.
    " Build variant parameters
    REFRESH lt_params.

    " P_TABLE
    CLEAR ls_param.
    ls_param-selname = 'P_TABLE'.
    ls_param-kind    = 'P'.
    ls_param-sign    = 'I'.
    ls_param-option  = 'EQ'.
    ls_param-low     = ls_table-tabname.
    APPEND ls_param TO lt_params.

    " P_TEST = ' ' — variant sẵn sàng cho production; hub override nếu cần
    CLEAR ls_param.
    ls_param-selname = 'P_TEST'.
    ls_param-kind    = 'P'.
    ls_param-sign    = 'I'.
    ls_param-option  = 'EQ'.
    CLEAR ls_param-low.
    APPEND ls_param TO lt_params.

    PERFORM zarc_var_tech
      USING ls_table-tabname 'DEFAULT'
      CHANGING lv_vname lv_vok.
    IF lv_vok = abap_false.
      WRITE: / |  ✗ Tên variant quá dài: { ls_table-tabname }|.
      CONTINUE.
    ENDIF.

    DATA: ls_varid_cv TYPE varid,
          lt_varit_cv TYPE TABLE OF varit,
          ls_varit_cv TYPE varit,
          lv_rep_cv   TYPE syrepid.
    lv_rep_cv = p_report.

    CLEAR ls_varid_cv.
    ls_varid_cv-mandt      = sy-mandt.
    ls_varid_cv-report     = lv_rep_cv.
    ls_varid_cv-variant    = lv_vname.
    ls_varid_cv-environmnt = 'A'.
    ls_varid_cv-aedat      = sy-datum.
    ls_varid_cv-aetime     = sy-uzeit.

    CLEAR ls_varit_cv.
    ls_varit_cv-mandt   = sy-mandt.
    ls_varit_cv-langu   = sy-langu.
    ls_varit_cv-report  = lv_rep_cv.
    ls_varit_cv-variant = lv_vname.
    ls_varit_cv-vtext   = ls_table-desc.
    REFRESH lt_varit_cv.
    APPEND ls_varit_cv TO lt_varit_cv.

    CALL FUNCTION 'RS_CREATE_VARIANT'
      EXPORTING
        curr_report               = lv_rep_cv
        curr_variant              = lv_vname
        vari_desc                 = ls_varid_cv
      TABLES
        vari_contents             = lt_params
        vari_text                 = lt_varit_cv
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
      WRITE: / |  ✓ Created { lv_vname } ({ ls_table-tabname }) — { ls_table-desc }|.
    ELSEIF sy-subrc = 7.
      WRITE: / |  ○ Already exists { lv_vname } ({ ls_table-tabname }) — skipped (no overwrite)|.
    ELSE.
      WRITE: / |  ✗ Failed: { ls_table-tabname } (sy-subrc={ sy-subrc })|.
    ENDIF.
  ENDLOOP.

  WRITE: /.
  WRITE: / '=== Done. Variants saved — pick via F4 on selection screen or archive job variant list ==='.
