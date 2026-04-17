*&---------------------------------------------------------------------*
*& Report ZSP26_DEMO_FULL_FLOW_DATA
*&---------------------------------------------------------------------*
*& Loads a dedicated demo dataset (EBELN 998xxxxxxx) for end-to-end
*& archive demos: Hub preview (READY / TOO NEW / RULE FAIL), Write,
*& Delete. Optional: insert minimal ZSP26_ARCH_CFG + rules + dep if
*& no active EKKO configuration exists.
*&---------------------------------------------------------------------*
REPORT zsp26_demo_full_flow_data.

TYPES ty_demo_mode TYPE c LENGTH 5.

CONSTANTS:
  gc_demo_lo TYPE ebeln VALUE '9980000001',
  gc_demo_hi TYPE ebeln VALUE '9980000999'.

DATA:
  lt_ekko TYPE STANDARD TABLE OF zsp26_ekko WITH DEFAULT KEY,
  lt_ekpo TYPE STANDARD TABLE OF zsp26_ekpo WITH DEFAULT KEY,
  ls_ekko TYPE zsp26_ekko,
  ls_ekpo TYPE zsp26_ekpo.

DATA lv_cfg_ok TYPE abap_bool.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-001.
PARAMETERS:
  p_ready   TYPE i DEFAULT 40,
  p_new     TYPE i DEFAULT 12,
  p_loekzf TYPE i DEFAULT 6,
  p_bstypf TYPE i DEFAULT 6.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-002.
PARAMETERS:
  p_clear TYPE c AS CHECKBOX DEFAULT 'X',
  p_cfg   TYPE c AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  IF p_ready < 0 OR p_new < 0 OR p_loekzf < 0 OR p_bstypf < 0.
    MESSAGE 'Counts must be zero or positive.' TYPE 'E'.
  ENDIF.
  IF p_ready + p_new + p_loekzf + p_bstypf > 900.
    MESSAGE 'Total demo rows exceed reserved EBELN range (900).' TYPE 'E'.
  ENDIF.

  PERFORM ensure_ekko_config USING p_cfg CHANGING lv_cfg_ok.
  IF lv_cfg_ok = abap_false.
    RETURN.
  ENDIF.

  IF p_clear = 'X'.
    DELETE FROM zsp26_ekpo WHERE ebeln >= gc_demo_lo AND ebeln <= gc_demo_hi.
    DELETE FROM zsp26_ekko WHERE ebeln >= gc_demo_lo AND ebeln <= gc_demo_hi.
    WRITE: / |Cleared previous demo POs in range { gc_demo_lo }–{ gc_demo_hi }.|.
  ENDIF.

  CLEAR: lt_ekko, lt_ekpo.

  DATA lv_start TYPE i.
  DATA lv_mode TYPE ty_demo_mode.

  " 1) READY: AEDAT old enough vs retention 365 + rules LOEKZ space, BSTYP F
  lv_mode = 'READY'.
  PERFORM append_ekko_block
    USING p_ready 1 lv_mode
    CHANGING lt_ekko lt_ekpo.

  " 2) TOO NEW: AEDAT recent (hub should show TOO NEW)
  lv_start = p_ready + 1.
  lv_mode = 'NEW'.
  PERFORM append_ekko_block
    USING p_new lv_start lv_mode
    CHANGING lt_ekko lt_ekpo.

  " 3) RULE FAIL: deletion indicator (archive rules typically exclude)
  lv_start = p_ready + p_new + 1.
  PERFORM append_ekko_block_fail_loekz
    USING p_loekzf lv_start
    CHANGING lt_ekko lt_ekpo.

  " 4) RULE FAIL: document category not F
  lv_start = p_ready + p_new + p_loekzf + 1.
  PERFORM append_ekko_block_fail_bstyp
    USING p_bstypf lv_start
    CHANGING lt_ekko lt_ekpo.

  IF lt_ekko IS INITIAL.
    MESSAGE 'No rows generated.' TYPE 'E'.
  ENDIF.

  MODIFY zsp26_ekko FROM TABLE lt_ekko.
  IF sy-subrc <> 0.
    MESSAGE 'Could not insert ZSP26_EKKO demo rows.' TYPE 'E'.
  ENDIF.
  MODIFY zsp26_ekpo FROM TABLE lt_ekpo.

  COMMIT WORK.

  WRITE: / '=== ZSP26_DEMO_FULL_FLOW_DATA complete ==='.
  WRITE: / |ZSP26_EKKO: { lines( lt_ekko ) } rows|.
  WRITE: / |ZSP26_EKPO: { lines( lt_ekpo ) } rows|.
  WRITE: / 'EBELN from 998… — use table ZSP26_EKKO in the hub; archive write uses AEDAT window + rules.'.
  WRITE: / 'Tip: READY rows use AEDAT = sy-datum - 400 + offset (eligible with 365d retention).'.

*&---------------------------------------------------------------------*
*& Form APPEND_EKKO_BLOCK
*&---------------------------------------------------------------------*
FORM append_ekko_block
  USING    iv_count TYPE i
           iv_start TYPE i
           iv_mode  TYPE ty_demo_mode
  CHANGING ct_ekko TYPE STANDARD TABLE OF zsp26_ekko WITH DEFAULT KEY
           ct_ekpo TYPE STANDARD TABLE OF zsp26_ekpo WITH DEFAULT KEY.

  DATA: lv_ix   TYPE i,
        lv_off  TYPE i,
        lv_ebel TYPE ebeln,
        ls_ekko TYPE zsp26_ekko,
        ls_ekpo TYPE zsp26_ekpo,
        lv_aed  TYPE d,
        lv_i    TYPE i.

  lv_ix = iv_start.
  DO iv_count TIMES.
    CLEAR ls_ekko.
    lv_off = sy-index - 1.
    lv_ebel = |998{ lv_ix WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-mandt = sy-mandt.
    ls_ekko-ebeln = lv_ebel.
    ls_ekko-bukrs = COND #( WHEN lv_ix MOD 2 = 0 THEN '1000' ELSE '2000' ).
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = COND #( WHEN lv_ix MOD 3 = 0 THEN 'NB' WHEN lv_ix MOD 3 = 1 THEN 'FO' ELSE 'UB' ).
    ls_ekko-loekz = ' '.

    IF iv_mode = 'READY'.
      lv_aed = sy-datum - 400 + lv_off.
    ELSE.
      lv_aed = sy-datum - 20 + ( lv_off MOD 15 ). "too new vs 365d retention
    ENDIF.
    ls_ekko-aedat = lv_aed.
    ls_ekko-ernam = 'DEMO_USER'.
    ls_ekko-lifnr = |{ 200000 + lv_ix }|.
    ls_ekko-ekorg = '1000'.
    ls_ekko-ekgrp = '001'.
    ls_ekko-waers = 'USD'.
    ls_ekko-bedat = lv_aed.
    APPEND ls_ekko TO ct_ekko.

    DO 2 TIMES.
      CLEAR ls_ekpo.
      ls_ekpo-mandt = sy-mandt.
      ls_ekpo-ebeln = lv_ebel.
      ls_ekpo-ebelp = sy-index * 10.
      lv_i = lv_ix * 10 + sy-index.
      ls_ekpo-matnr = |DM{ lv_i WIDTH = 10 ALIGN = RIGHT PAD = '0' }|.
      ls_ekpo-txz01 = |Demo item { sy-index }|.
      ls_ekpo-menge = sy-index * 10.
      ls_ekpo-meins = 'EA'.
      ls_ekpo-netpr = sy-index * 25.
      ls_ekpo-peinh = 1.
      ls_ekpo-werks = '1000'.
      ls_ekpo-lgort = '0001'.
      ls_ekpo-matkl = '001'.
      ls_ekpo-aedat = lv_aed.
      APPEND ls_ekpo TO ct_ekpo.
    ENDDO.

    ADD 1 TO lv_ix.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
FORM append_ekko_block_fail_loekz
  USING    iv_count TYPE i
           iv_start TYPE i
  CHANGING ct_ekko TYPE STANDARD TABLE OF zsp26_ekko WITH DEFAULT KEY
           ct_ekpo TYPE STANDARD TABLE OF zsp26_ekpo WITH DEFAULT KEY.

  DATA: lv_ix   TYPE i,
        lv_off  TYPE i,
        lv_ebel TYPE ebeln,
        ls_ekko TYPE zsp26_ekko,
        ls_ekpo TYPE zsp26_ekpo,
        lv_aed  TYPE d,
        lv_i    TYPE i.

  lv_ix = iv_start.
  DO iv_count TIMES.
    CLEAR ls_ekko.
    lv_off = sy-index - 1.
    lv_ebel = |998{ lv_ix WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-mandt = sy-mandt.
    ls_ekko-ebeln = lv_ebel.
    ls_ekko-bukrs = '1000'.
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = 'NB'.
    ls_ekko-loekz = 'L'. "blocked by archive rule
    ls_ekko-aedat = sy-datum - 500 + lv_off.
    ls_ekko-ernam = 'DEMO_USER'.
    ls_ekko-lifnr = '300001'.
    ls_ekko-ekorg = '1000'.
    ls_ekko-ekgrp = '001'.
    ls_ekko-waers = 'USD'.
    ls_ekko-bedat = ls_ekko-aedat.
    APPEND ls_ekko TO ct_ekko.

    CLEAR ls_ekpo.
    ls_ekpo-mandt = sy-mandt.
    ls_ekpo-ebeln = lv_ebel.
    ls_ekpo-ebelp = 10.
    lv_i = lv_ix.
    ls_ekpo-matnr = |DL{ lv_i WIDTH = 8 ALIGN = RIGHT PAD = '0' }|.
    ls_ekpo-txz01 = 'Rule fail LOEKZ'.
    ls_ekpo-menge = 1.
    ls_ekpo-meins = 'EA'.
    ls_ekpo-netpr = 1.
    ls_ekpo-peinh = 1.
    ls_ekpo-werks = '1000'.
    ls_ekpo-lgort = '0001'.
    ls_ekpo-matkl = '001'.
    ls_ekpo-aedat = ls_ekko-aedat.
    APPEND ls_ekpo TO ct_ekpo.

    ADD 1 TO lv_ix.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
FORM append_ekko_block_fail_bstyp
  USING    iv_count TYPE i
           iv_start TYPE i
  CHANGING ct_ekko TYPE STANDARD TABLE OF zsp26_ekko WITH DEFAULT KEY
           ct_ekpo TYPE STANDARD TABLE OF zsp26_ekpo WITH DEFAULT KEY.

  DATA: lv_ix   TYPE i,
        lv_off  TYPE i,
        lv_ebel TYPE ebeln,
        ls_ekko TYPE zsp26_ekko,
        ls_ekpo TYPE zsp26_ekpo,
        lv_aed  TYPE d,
        lv_i    TYPE i.

  lv_ix = iv_start.
  DO iv_count TIMES.
    CLEAR ls_ekko.
    lv_off = sy-index - 1.
    lv_ebel = |998{ lv_ix WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-mandt = sy-mandt.
    ls_ekko-ebeln = lv_ebel.
    ls_ekko-bukrs = '1000'.
    ls_ekko-bstyp = 'K'. "not F — rule fail
    ls_ekko-bsart = 'NB'.
    ls_ekko-loekz = ' '.
    ls_ekko-aedat = sy-datum - 500 + lv_off.
    ls_ekko-ernam = 'DEMO_USER'.
    ls_ekko-lifnr = '300002'.
    ls_ekko-ekorg = '1000'.
    ls_ekko-ekgrp = '001'.
    ls_ekko-waers = 'USD'.
    ls_ekko-bedat = ls_ekko-aedat.
    APPEND ls_ekko TO ct_ekko.

    CLEAR ls_ekpo.
    ls_ekpo-mandt = sy-mandt.
    ls_ekpo-ebeln = lv_ebel.
    ls_ekpo-ebelp = 10.
    lv_i = lv_ix.
    ls_ekpo-matnr = |DK{ lv_i WIDTH = 8 ALIGN = RIGHT PAD = '0' }|.
    ls_ekpo-txz01 = 'Rule fail BSTYP'.
    ls_ekpo-menge = 1.
    ls_ekpo-meins = 'EA'.
    ls_ekpo-netpr = 1.
    ls_ekpo-peinh = 1.
    ls_ekpo-werks = '1000'.
    ls_ekpo-lgort = '0001'.
    ls_ekpo-matkl = '001'.
    ls_ekpo-aedat = ls_ekko-aedat.
    APPEND ls_ekpo TO ct_ekpo.

    ADD 1 TO lv_ix.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form ENSURE_EKKO_CONFIG
*&---------------------------------------------------------------------*
FORM ensure_ekko_config
  USING    iv_insert TYPE c
  CHANGING cv_ok TYPE abap_bool.

  DATA: ls_cfg TYPE zsp26_arch_cfg,
        ls_r   TYPE zsp26_arch_rule,
        ls_d   TYPE zsp26_arch_dep,
        lv_id  TYPE sysuuid_x16,
        lv_r1  TYPE sysuuid_x16,
        lv_r2  TYPE sysuuid_x16,
        lv_d1  TYPE sysuuid_x16.

  CLEAR cv_ok.
  SELECT COUNT( * ) FROM zsp26_arch_cfg
    WHERE table_name = 'ZSP26_EKKO'
      AND is_active  = 'X'
    INTO @DATA(lv_cfg_cnt).
  IF lv_cfg_cnt > 0.
    cv_ok = abap_true.
    WRITE: / 'Active ZSP26_ARCH_CFG for ZSP26_EKKO already exists — skipped config insert.'.
    RETURN.
  ENDIF.

  IF iv_insert <> 'X'.
    WRITE: / 'No active archive config for ZSP26_EKKO. Run with "Insert minimal config" or execute ZSP26_LOAD_SAMPLE_DATA.'.
    cv_ok = abap_false.
    RETURN.
  ENDIF.

  TRY.
      lv_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_id = 'DEMODEMODEMODEMODEMODEME01'.
  ENDTRY.

  CLEAR ls_cfg.
  ls_cfg-mandt       = sy-mandt.
  ls_cfg-config_id   = lv_id.
  ls_cfg-table_name  = 'ZSP26_EKKO'.
  ls_cfg-description = 'Demo PO header — created by ZSP26_DEMO_FULL_FLOW_DATA'.
  ls_cfg-retention   = 365.
  ls_cfg-data_field  = 'AEDAT'.
  ls_cfg-is_active   = 'X'.
  ls_cfg-created_by  = sy-uname.
  ls_cfg-created_on  = sy-datum.
  ls_cfg-changed_by  = sy-uname.
  ls_cfg-changed_on  = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.

  TRY. lv_r1 = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. lv_r1 = 'DEMODEMODEMODEMODEMODEME02'. ENDTRY.
  TRY. lv_r2 = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. lv_r2 = 'DEMODEMODEMODEMODEMODEME03'. ENDTRY.

  CLEAR ls_r.
  ls_r-mandt      = sy-mandt.
  ls_r-rule_id    = lv_r1.
  ls_r-config_id  = lv_id.
  ls_r-rule_seq   = 1.
  ls_r-field_name = 'LOEKZ'.
  ls_r-operator   = 'EQ'.
  ls_r-value_low  = ' '.
  ls_r-and_or     = 'AND'.
  ls_r-is_active  = 'X'.
  MODIFY zsp26_arch_rule FROM ls_r.

  CLEAR ls_r.
  ls_r-mandt      = sy-mandt.
  ls_r-rule_id    = lv_r2.
  ls_r-config_id  = lv_id.
  ls_r-rule_seq   = 2.
  ls_r-field_name = 'BSTYP'.
  ls_r-operator   = 'EQ'.
  ls_r-value_low  = 'F'.
  ls_r-and_or     = ''.
  ls_r-is_active  = 'X'.
  MODIFY zsp26_arch_rule FROM ls_r.

  TRY. lv_d1 = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. lv_d1 = 'DEMODEMODEMODEMODEMODEME04'. ENDTRY.

  CLEAR ls_d.
  ls_d-mandt         = sy-mandt.
  ls_d-dep_id        = lv_d1.
  ls_d-parent_table  = 'ZSP26_EKKO'.
  ls_d-child_table   = 'ZSP26_EKPO'.
  ls_d-dep_type      = 'H'.
  ls_d-parent_field  = 'EBELN'.
  ls_d-child_field   = 'EBELN'.
  ls_d-del_cascade   = 'X'.
  MODIFY zsp26_arch_dep FROM ls_d.

  COMMIT WORK.
  cv_ok = abap_true.
  WRITE: / 'Inserted minimal ZSP26_ARCH_CFG + rules + EKKO→EKPO dependency for demo.'.
ENDFORM.
