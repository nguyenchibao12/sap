*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_CREATE_VARIANTS
*& One-time utility: creates SARA variants for Z_ARCH_EKK_WRITE
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
      ls_param  TYPE rsparams.

PARAMETERS: p_report TYPE programm DEFAULT 'Z_ARCH_EKK_WRITE'.

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

    " P_TEST = X (safe default)
    CLEAR ls_param.
    ls_param-selname = 'P_TEST'.
    ls_param-kind    = 'P'.
    ls_param-sign    = 'I'.
    ls_param-option  = 'EQ'.
    ls_param-low     = 'X'.
    APPEND ls_param TO lt_params.

    " Create/update variant
    CALL FUNCTION 'RS_CHANGE_CREATED_VARIANT'
      EXPORTING
        curr_report          = p_report
        curr_variant         = ls_table-tabname
        vari_desc            = ls_table-desc
      TABLES
        vari_contents        = lt_params
      EXCEPTIONS
        illegal_report_or_variant = 1
        illegal_variantname       = 2
        not_authorized            = 3
        not_executed              = 4
        report_not_existent       = 5
        OTHERS                    = 6.

    IF sy-subrc = 0.
      WRITE: / |  ✓ Variant { ls_table-tabname } created — { ls_table-desc }|.
    ELSE.
      WRITE: / |  ✗ Failed: { ls_table-tabname } (sy-subrc={ sy-subrc })|.
    ENDIF.
  ENDLOOP.

  WRITE: /.
  WRITE: / '=== Done. Check SARA → Z_ARCH_EKK → Archive → Variant (F4) ==='.
