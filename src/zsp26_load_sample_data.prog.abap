*&---------------------------------------------------------------------*
*& Report ZSP26_LOAD_SAMPLE_DATA
*&---------------------------------------------------------------------*
*& Program to load sample/test data into all Z tables
*& Run this ONCE after creating all tables in SE11
*&---------------------------------------------------------------------*
REPORT zsp26_load_sample_data.

*----------------------------------------------------------------------*
* Data Declarations
*----------------------------------------------------------------------*
DATA: lv_guid     TYPE sysuuid_x16,
      lv_timestamp TYPE timestampl.

DATA: ls_cfg      TYPE zsp26_arch_cfg,
      ls_rule     TYPE zsp26_arch_rule,
      ls_fmap     TYPE zsp26_arch_fmap,
      ls_dep      TYPE zsp26_arch_dep,
      ls_ekko     TYPE zsp26_ekko,
      ls_ekpo     TYPE zsp26_ekpo,
      ls_vbak     TYPE zsp26_vbak,
      ls_vbap     TYPE zsp26_vbap,
      ls_bkpf     TYPE zsp26_bkpf,
      ls_bseg     TYPE zsp26_bseg.

DATA: lt_ekko TYPE TABLE OF zsp26_ekko,
      lt_ekpo TYPE TABLE OF zsp26_ekpo,
      lt_vbak TYPE TABLE OF zsp26_vbak,
      lt_vbap TYPE TABLE OF zsp26_vbap,
      lt_bkpf TYPE TABLE OF zsp26_bkpf,
      lt_bseg TYPE TABLE OF zsp26_bseg.

DATA: lv_cfg_id_ekko TYPE sysuuid_x16,
      lv_cfg_id_vbak TYPE sysuuid_x16,
      lv_cfg_id_bkpf TYPE sysuuid_x16.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  WRITE: / '============================================'.
  WRITE: / 'Loading Sample Data for Archiving Tool'.
  WRITE: / '============================================'.
  WRITE: /.

*----------------------------------------------------------------------*
* 1. Load Archive Configuration (ZSP26_ARCH_CFG)
*----------------------------------------------------------------------*
  WRITE: / '>>> Loading ZSP26_ARCH_CFG...'.

  " Config for EKKO
  TRY.
      lv_cfg_id_ekko = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_cfg_id_ekko = '11111111111111111111111111111111'.
  ENDTRY.

  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  ls_cfg-config_id  = lv_cfg_id_ekko.
  ls_cfg-table_name = 'ZSP26_EKKO'.
  ls_cfg-description = 'Purchase Order Header Archive Config'.
  ls_cfg-retention  = 365.
  ls_cfg-data_field = 'AEDAT'.
  ls_cfg-is_active  = 'X'.
  ls_cfg-created_by = sy-uname.
  ls_cfg-created_on = sy-datum.
  ls_cfg-changed_by = sy-uname.
  ls_cfg-changed_on = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0.
    WRITE: / '  - ZSP26_EKKO config inserted'.
  ENDIF.

  " Config for VBAK
  TRY.
      lv_cfg_id_vbak = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_cfg_id_vbak = '22222222222222222222222222222222'.
  ENDTRY.

  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  ls_cfg-config_id  = lv_cfg_id_vbak.
  ls_cfg-table_name = 'ZSP26_VBAK'.
  ls_cfg-description = 'Sales Order Header Archive Config'.
  ls_cfg-retention  = 365.
  ls_cfg-data_field = 'ERDAT'.
  ls_cfg-is_active  = 'X'.
  ls_cfg-created_by = sy-uname.
  ls_cfg-created_on = sy-datum.
  ls_cfg-changed_by = sy-uname.
  ls_cfg-changed_on = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0.
    WRITE: / '  - ZSP26_VBAK config inserted'.
  ENDIF.

  " Config for BKPF
  TRY.
      lv_cfg_id_bkpf = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_cfg_id_bkpf = '33333333333333333333333333333333'.
  ENDTRY.

  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  ls_cfg-config_id  = lv_cfg_id_bkpf.
  ls_cfg-table_name = 'ZSP26_BKPF'.
  ls_cfg-description = 'Accounting Document Header Archive Config'.
  ls_cfg-retention  = 730.
  ls_cfg-data_field = 'BUDAT'.
  ls_cfg-is_active  = 'X'.
  ls_cfg-created_by = sy-uname.
  ls_cfg-created_on = sy-datum.
  ls_cfg-changed_by = sy-uname.
  ls_cfg-changed_on = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0.
    WRITE: / '  - ZSP26_BKPF config inserted'.
  ENDIF.

  " Config for MKPF
  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  TRY. ls_cfg-config_id = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. ls_cfg-config_id = '44444444444444444444444444444444'. ENDTRY.
  ls_cfg-table_name  = 'ZSP26_MKPF'.
  ls_cfg-description = 'Material Document Header Archive Config'.
  ls_cfg-retention   = 365.
  ls_cfg-data_field  = 'BLDAT'.
  ls_cfg-is_active   = 'X'.
  ls_cfg-created_by  = sy-uname. ls_cfg-created_on = sy-datum.
  ls_cfg-changed_by  = sy-uname. ls_cfg-changed_on = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0. WRITE: / '  - ZSP26_MKPF config inserted'. ENDIF.

  " Config for MARA
  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  TRY. ls_cfg-config_id = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. ls_cfg-config_id = '55555555555555555555555555555555'. ENDTRY.
  ls_cfg-table_name  = 'ZSP26_MARA'.
  ls_cfg-description = 'Material Master Archive Config'.
  ls_cfg-retention   = 730.
  ls_cfg-data_field  = 'LAEDA'.
  ls_cfg-is_active   = 'X'.
  ls_cfg-created_by  = sy-uname. ls_cfg-created_on = sy-datum.
  ls_cfg-changed_by  = sy-uname. ls_cfg-changed_on = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0. WRITE: / '  - ZSP26_MARA config inserted'. ENDIF.

  " Config for KNA1
  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  TRY. ls_cfg-config_id = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error. ls_cfg-config_id = '66666666666666666666666666666666'. ENDTRY.
  ls_cfg-table_name  = 'ZSP26_KNA1'.
  ls_cfg-description = 'Customer Master Archive Config'.
  ls_cfg-retention   = 730.
  ls_cfg-data_field  = 'ERDAT'.
  ls_cfg-is_active   = 'X'.
  ls_cfg-created_by  = sy-uname. ls_cfg-created_on = sy-datum.
  ls_cfg-changed_by  = sy-uname. ls_cfg-changed_on = sy-datum.
  MODIFY zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0. WRITE: / '  - ZSP26_KNA1 config inserted'. ENDIF.

  WRITE: / '  Config loaded: 7 entries'.

*----------------------------------------------------------------------*
* 2. Load Archive Rules (ZSP26_ARCH_RULE)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_ARCH_RULE...'.

  " Rule: EKKO where AEDAT older than retention + LOEKZ = space
  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = '44444444444444444444444444444444'.
  ENDTRY.

  CLEAR ls_rule.
  ls_rule-mandt      = sy-mandt.
  ls_rule-rule_id    = lv_guid.
  ls_rule-config_id  = lv_cfg_id_ekko.
  ls_rule-rule_seq   = 1.
  ls_rule-field_name = 'LOEKZ'.
  ls_rule-operator   = 'EQ'.
  ls_rule-value_low  = ' '.
  ls_rule-and_or     = 'AND'.
  ls_rule-is_active  = 'X'.
  MODIFY zsp26_arch_rule FROM ls_rule.

  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = '55555555555555555555555555555555'.
  ENDTRY.

  CLEAR ls_rule.
  ls_rule-mandt      = sy-mandt.
  ls_rule-rule_id    = lv_guid.
  ls_rule-config_id  = lv_cfg_id_ekko.
  ls_rule-rule_seq   = 2.
  ls_rule-field_name = 'BSTYP'.
  ls_rule-operator   = 'EQ'.
  ls_rule-value_low  = 'F'.
  ls_rule-and_or     = ''.
  ls_rule-is_active  = 'X'.
  MODIFY zsp26_arch_rule FROM ls_rule.

  WRITE: / '  Rules loaded: 2 entries'.

*----------------------------------------------------------------------*
* 3. Load Dependencies (ZSP26_ARCH_DEP)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_ARCH_DEP...'.

  " EKKO → EKPO
  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1'.
  ENDTRY.

  CLEAR ls_dep.
  ls_dep-mandt        = sy-mandt.
  ls_dep-dep_id       = lv_guid.
  ls_dep-parent_table = 'ZSP26_EKKO'.
  ls_dep-child_table  = 'ZSP26_EKPO'.
  ls_dep-dep_type     = 'H'.
  ls_dep-parent_field = 'EBELN'.
  ls_dep-child_field  = 'EBELN'.
  ls_dep-del_cascade  = 'X'.
  MODIFY zsp26_arch_dep FROM ls_dep.

  " VBAK → VBAP
  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA2'.
  ENDTRY.

  CLEAR ls_dep.
  ls_dep-mandt        = sy-mandt.
  ls_dep-dep_id       = lv_guid.
  ls_dep-parent_table = 'ZSP26_VBAK'.
  ls_dep-child_table  = 'ZSP26_VBAP'.
  ls_dep-dep_type     = 'H'.
  ls_dep-parent_field = 'VBELN'.
  ls_dep-child_field  = 'VBELN'.
  ls_dep-del_cascade  = 'X'.
  MODIFY zsp26_arch_dep FROM ls_dep.

  " BKPF → BSEG (compound key - 3 entries)
  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA3'.
  ENDTRY.

  CLEAR ls_dep.
  ls_dep-mandt        = sy-mandt.
  ls_dep-dep_id       = lv_guid.
  ls_dep-parent_table = 'ZSP26_BKPF'.
  ls_dep-child_table  = 'ZSP26_BSEG'.
  ls_dep-dep_type     = 'H'.
  ls_dep-parent_field = 'BUKRS'.
  ls_dep-child_field  = 'BUKRS'.
  ls_dep-del_cascade  = 'X'.
  MODIFY zsp26_arch_dep FROM ls_dep.

  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4'.
  ENDTRY.

  CLEAR ls_dep.
  ls_dep-mandt        = sy-mandt.
  ls_dep-dep_id       = lv_guid.
  ls_dep-parent_table = 'ZSP26_BKPF'.
  ls_dep-child_table  = 'ZSP26_BSEG'.
  ls_dep-dep_type     = 'H'.
  ls_dep-parent_field = 'BELNR'.
  ls_dep-child_field  = 'BELNR'.
  ls_dep-del_cascade  = 'X'.
  MODIFY zsp26_arch_dep FROM ls_dep.

  TRY.
      lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      lv_guid = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA5'.
  ENDTRY.

  CLEAR ls_dep.
  ls_dep-mandt        = sy-mandt.
  ls_dep-dep_id       = lv_guid.
  ls_dep-parent_table = 'ZSP26_BKPF'.
  ls_dep-child_table  = 'ZSP26_BSEG'.
  ls_dep-dep_type     = 'H'.
  ls_dep-parent_field = 'GJAHR'.
  ls_dep-child_field  = 'GJAHR'.
  ls_dep-del_cascade  = 'X'.
  MODIFY zsp26_arch_dep FROM ls_dep.

  WRITE: / '  Dependencies loaded: 5 entries'.

*----------------------------------------------------------------------*
* 4. Load Field Mappings (ZSP26_ARCH_FMAP) - for EKKO as example
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_ARCH_FMAP for ZSP26_EKKO...'.

  DATA: lt_fmap TYPE TABLE OF zsp26_arch_fmap.
  DATA: lv_seq TYPE i VALUE 0.

  DEFINE add_fmap.
    lv_seq = lv_seq + 1.
    TRY.
        lv_guid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
    ENDTRY.
    CLEAR ls_fmap.
    ls_fmap-mandt      = sy-mandt.
    ls_fmap-map_id     = lv_guid.
    ls_fmap-table_name = &1.
    ls_fmap-field_name = &2.
    ls_fmap-field_seq  = lv_seq.
    ls_fmap-is_key     = &3.
    ls_fmap-is_display = &4.
    ls_fmap-is_search  = &5.
    ls_fmap-field_label = &6.
    APPEND ls_fmap TO lt_fmap.
  END-OF-DEFINITION.

  " EKKO field mappings
  lv_seq = 0.
  add_fmap 'ZSP26_EKKO' 'EBELN' 'X' 'X' 'X' 'PO Number'.
  add_fmap 'ZSP26_EKKO' 'BUKRS' ' ' 'X' 'X' 'Company Code'.
  add_fmap 'ZSP26_EKKO' 'BSART' ' ' 'X' ' ' 'Doc Type'.
  add_fmap 'ZSP26_EKKO' 'LIFNR' ' ' 'X' 'X' 'Vendor'.
  add_fmap 'ZSP26_EKKO' 'EKORG' ' ' 'X' ' ' 'Purch. Org'.
  add_fmap 'ZSP26_EKKO' 'WAERS' ' ' 'X' ' ' 'Currency'.
  add_fmap 'ZSP26_EKKO' 'AEDAT' ' ' 'X' 'X' 'Created On'.
  add_fmap 'ZSP26_EKKO' 'ERNAM' ' ' 'X' ' ' 'Created By'.
  add_fmap 'ZSP26_EKKO' 'BEDAT' ' ' 'X' 'X' 'PO Date'.
  add_fmap 'ZSP26_EKKO' 'LOEKZ' ' ' 'X' ' ' 'Deletion Flag'.

  MODIFY zsp26_arch_fmap FROM TABLE lt_fmap.
  WRITE: / '  EKKO field mappings loaded:', lines( lt_fmap ), 'entries'.

  " VBAK field mappings
  CLEAR lt_fmap. lv_seq = 0.
  add_fmap 'ZSP26_VBAK' 'VBELN' 'X' 'X' 'X' 'Sales Doc'.
  add_fmap 'ZSP26_VBAK' 'AUART' ' ' 'X' ' ' 'Doc Type'.
  add_fmap 'ZSP26_VBAK' 'VKORG' ' ' 'X' 'X' 'Sales Org'.
  add_fmap 'ZSP26_VBAK' 'KUNNR' ' ' 'X' 'X' 'Customer'.
  add_fmap 'ZSP26_VBAK' 'NETWR' ' ' 'X' ' ' 'Net Value'.
  add_fmap 'ZSP26_VBAK' 'WAERK' ' ' 'X' ' ' 'Currency'.
  add_fmap 'ZSP26_VBAK' 'ERDAT' ' ' 'X' 'X' 'Created On'.
  add_fmap 'ZSP26_VBAK' 'ERNAM' ' ' 'X' ' ' 'Created By'.
  add_fmap 'ZSP26_VBAK' 'AUDAT' ' ' 'X' 'X' 'Doc Date'.

  MODIFY zsp26_arch_fmap FROM TABLE lt_fmap.
  WRITE: / '  VBAK field mappings loaded:', lines( lt_fmap ), 'entries'.

  " BKPF field mappings
  CLEAR lt_fmap. lv_seq = 0.
  add_fmap 'ZSP26_BKPF' 'BUKRS' 'X' 'X' 'X' 'Company Code'.
  add_fmap 'ZSP26_BKPF' 'BELNR' 'X' 'X' 'X' 'Doc Number'.
  add_fmap 'ZSP26_BKPF' 'GJAHR' 'X' 'X' 'X' 'Fiscal Year'.
  add_fmap 'ZSP26_BKPF' 'BLART' ' ' 'X' ' ' 'Doc Type'.
  add_fmap 'ZSP26_BKPF' 'BUDAT' ' ' 'X' 'X' 'Posting Date'.
  add_fmap 'ZSP26_BKPF' 'BLDAT' ' ' 'X' ' ' 'Doc Date'.
  add_fmap 'ZSP26_BKPF' 'USNAM' ' ' 'X' ' ' 'User'.
  add_fmap 'ZSP26_BKPF' 'WAERS' ' ' 'X' ' ' 'Currency'.
  add_fmap 'ZSP26_BKPF' 'BKTXT' ' ' 'X' 'X' 'Header Text'.
  add_fmap 'ZSP26_BKPF' 'XBLNR' ' ' 'X' 'X' 'Reference'.

  MODIFY zsp26_arch_fmap FROM TABLE lt_fmap.
  WRITE: / '  BKPF field mappings loaded:', lines( lt_fmap ), 'entries'.


*----------------------------------------------------------------------*
* 5. Load Sample Purchase Orders (ZSP26_EKKO + ZSP26_EKPO)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_EKKO / ZSP26_EKPO sample data...'.

  DO 20 TIMES.
    CLEAR ls_ekko.
    ls_ekko-mandt = sy-mandt.
    ls_ekko-ebeln = |45000{ sy-index WIDTH = 5 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-bukrs = COND #( WHEN sy-index <= 10 THEN '1000'
                             ELSE '2000' ).
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = COND #( WHEN sy-index <= 7 THEN 'NB'
                             WHEN sy-index <= 14 THEN 'FO'
                             ELSE 'UB' ).
    ls_ekko-loekz = COND #( WHEN sy-index = 5 OR sy-index = 15 THEN 'L'
                             ELSE ' ' ).
    " Dates: spread over last 2 years
    ls_ekko-aedat = sy-datum - ( sy-index * 35 ).
    ls_ekko-ernam = COND #( WHEN sy-index <= 10 THEN 'USER01'
                             ELSE 'USER02' ).
    ls_ekko-lifnr = |{ 100000 + sy-index }|.
    ls_ekko-ekorg = '1000'.
    ls_ekko-ekgrp = COND #( WHEN sy-index <= 10 THEN '001'
                             ELSE '002' ).
    ls_ekko-waers = 'USD'.
    ls_ekko-bedat = ls_ekko-aedat.
    APPEND ls_ekko TO lt_ekko.

    " 2-3 items per PO
    DO 3 TIMES.
      IF sy-index > 2 AND sy-tabix > 15. EXIT. ENDIF.
      CLEAR ls_ekpo.
      ls_ekpo-mandt = sy-mandt.
      ls_ekpo-ebeln = ls_ekko-ebeln.
      ls_ekpo-ebelp = sy-index * 10.
      ls_ekpo-matnr = |MAT-{ sy-tabix WIDTH = 4 ALIGN = RIGHT PAD = '0' }-{ sy-index }|.
      ls_ekpo-txz01 = |Material Item { sy-index }|.
      ls_ekpo-menge = sy-index * 100.
      ls_ekpo-meins = 'EA'.
      ls_ekpo-netpr = sy-index * 50.
      ls_ekpo-peinh = 1.
      ls_ekpo-werks = '1000'.
      ls_ekpo-lgort = '0001'.
      ls_ekpo-matkl = '001'.
      ls_ekpo-aedat = ls_ekko-aedat.
      APPEND ls_ekpo TO lt_ekpo.
    ENDDO.
  ENDDO.

  MODIFY zsp26_ekko FROM TABLE lt_ekko.
  WRITE: / '  EKKO loaded:', lines( lt_ekko ), 'entries'.

  MODIFY zsp26_ekpo FROM TABLE lt_ekpo.
  WRITE: / '  EKPO loaded:', lines( lt_ekpo ), 'entries'.


*----------------------------------------------------------------------*
* 6. Load Sample Sales Orders (ZSP26_VBAK + ZSP26_VBAP)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_VBAK / ZSP26_VBAP sample data...'.

  DO 20 TIMES.
    CLEAR ls_vbak.
    ls_vbak-mandt = sy-mandt.
    ls_vbak-vbeln = |00200{ sy-index WIDTH = 5 ALIGN = RIGHT PAD = '0' }|.
    ls_vbak-auart = COND #( WHEN sy-index <= 12 THEN 'OR'
                             ELSE 'RE' ).
    ls_vbak-vkorg = '1000'.
    ls_vbak-vtweg = '10'.
    ls_vbak-spart = '00'.
    ls_vbak-kunnr = |{ 200000 + sy-index }|.
    ls_vbak-bstnk = |CUSTPO-{ sy-index }|.
    ls_vbak-erdat = sy-datum - ( sy-index * 30 ).
    ls_vbak-erzet = '120000'.
    ls_vbak-ernam = 'USER01'.
    ls_vbak-netwr = sy-index * 1500.
    ls_vbak-waerk = 'USD'.
    ls_vbak-audat = ls_vbak-erdat.
    APPEND ls_vbak TO lt_vbak.

    " 2 items per SO
    DO 2 TIMES.
      CLEAR ls_vbap.
      ls_vbap-mandt  = sy-mandt.
      ls_vbap-vbeln  = ls_vbak-vbeln.
      ls_vbap-posnr  = sy-index * 10.
      ls_vbap-matnr  = |PROD-{ sy-tabix WIDTH = 4 ALIGN = RIGHT PAD = '0' }-{ sy-index }|.
      ls_vbap-arktx  = |Product Item { sy-index }|.
      ls_vbap-kwmeng = sy-index * 10.
      ls_vbap-vrkme  = 'EA'.
      ls_vbap-netwr  = sy-index * 750.
      ls_vbap-waerk  = 'USD'.
      ls_vbap-werks  = '1000'.
      ls_vbap-lgort  = '0001'.
      ls_vbap-pstyv  = 'TAN'.
      ls_vbap-erdat  = ls_vbak-erdat.
      ls_vbap-ernam  = 'USER01'.
      APPEND ls_vbap TO lt_vbap.
    ENDDO.
  ENDDO.

  MODIFY zsp26_vbak FROM TABLE lt_vbak.
  WRITE: / '  VBAK loaded:', lines( lt_vbak ), 'entries'.

  MODIFY zsp26_vbap FROM TABLE lt_vbap.
  WRITE: / '  VBAP loaded:', lines( lt_vbap ), 'entries'.


*----------------------------------------------------------------------*
* 7. Load Sample Accounting Docs (ZSP26_BKPF + ZSP26_BSEG)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_BKPF / ZSP26_BSEG sample data...'.

  DO 20 TIMES.
    CLEAR ls_bkpf.
    ls_bkpf-mandt = sy-mandt.
    ls_bkpf-bukrs = COND #( WHEN sy-index <= 10 THEN '1000'
                             ELSE '2000' ).
    ls_bkpf-belnr = |10000{ sy-index WIDTH = 5 ALIGN = RIGHT PAD = '0' }|.
    ls_bkpf-gjahr = COND #( WHEN sy-index <= 10 THEN '2024'
                             ELSE '2023' ).
    ls_bkpf-blart = COND #( WHEN sy-index <= 7 THEN 'SA'
                             WHEN sy-index <= 14 THEN 'KR'
                             ELSE 'RE' ).
    ls_bkpf-budat = sy-datum - ( sy-index * 40 ).
    ls_bkpf-bldat = ls_bkpf-budat.
    ls_bkpf-monat = ls_bkpf-budat+4(2).
    ls_bkpf-cpudt = ls_bkpf-budat.
    ls_bkpf-cputm = '100000'.
    ls_bkpf-usnam = 'USER01'.
    ls_bkpf-waers = 'USD'.
    ls_bkpf-bktxt = |Document { sy-index }|.
    ls_bkpf-xblnr = |REF-{ sy-index }|.
    APPEND ls_bkpf TO lt_bkpf.

    " 2-3 line items per doc
    DO 3 TIMES.
      IF sy-index > 2 AND sy-tabix > 15. EXIT. ENDIF.
      CLEAR ls_bseg.
      ls_bseg-mandt = sy-mandt.
      ls_bseg-bukrs = ls_bkpf-bukrs.
      ls_bseg-belnr = ls_bkpf-belnr.
      ls_bseg-gjahr = ls_bkpf-gjahr.
      ls_bseg-buzei = |{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
      ls_bseg-bschl = COND #( WHEN sy-index = 1 THEN '40'
                               ELSE '50' ).
      ls_bseg-koart = 'S'.
      ls_bseg-shkzg = COND #( WHEN sy-index = 1 THEN 'S'
                               ELSE 'H' ).
      ls_bseg-dmbtr = sy-index * 1000.
      ls_bseg-wrbtr = ls_bseg-dmbtr.
      ls_bseg-hkont = |{ 400000 + sy-index }|.
      ls_bseg-kostl = '1000'.
      ls_bseg-sgtxt = |Line item { sy-index } for doc { sy-tabix }|.
      APPEND ls_bseg TO lt_bseg.
    ENDDO.
  ENDDO.

  MODIFY zsp26_bkpf FROM TABLE lt_bkpf.
  WRITE: / '  BKPF loaded:', lines( lt_bkpf ), 'entries'.

  MODIFY zsp26_bseg FROM TABLE lt_bseg.
  WRITE: / '  BSEG loaded:', lines( lt_bseg ), 'entries'.


*----------------------------------------------------------------------*
* 8. Load Sample Material Documents (ZSP26_MKPF + ZSP26_MSEG)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_MKPF / ZSP26_MSEG sample data...'.

  DATA: ls_mkpf TYPE zsp26_mkpf,
        ls_mseg TYPE zsp26_mseg,
        lt_mkpf TYPE TABLE OF zsp26_mkpf,
        lt_mseg TYPE TABLE OF zsp26_mseg.

  DO 20 TIMES.
    CLEAR ls_mkpf.
    ls_mkpf-mandt = sy-mandt.
    ls_mkpf-mblnr = |5000{ sy-index WIDTH = 6 ALIGN = RIGHT PAD = '0' }|.
    ls_mkpf-mjahr = COND #( WHEN sy-index <= 10 THEN '2024' ELSE '2023' ).
    ls_mkpf-bldat = sy-datum - ( sy-index * 35 ).
    ls_mkpf-budat = ls_mkpf-bldat.
    ls_mkpf-blart = COND #( WHEN sy-index <= 10 THEN '101' ELSE '261' ).
    ls_mkpf-usnam = 'USER01'.
    ls_mkpf-cpudt = ls_mkpf-bldat.
    ls_mkpf-bktxt = |MatDoc { sy-index }|.
    ls_mkpf-werks = '1000'.
    APPEND ls_mkpf TO lt_mkpf.

    DO 2 TIMES.
      CLEAR ls_mseg.
      ls_mseg-mandt = sy-mandt.
      ls_mseg-mblnr = ls_mkpf-mblnr.
      ls_mseg-mjahr = ls_mkpf-mjahr.
      ls_mseg-zeile = sy-index * 1.
      ls_mseg-matnr = |MAT-{ sy-tabix WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
      ls_mseg-werks = '1000'.
      ls_mseg-lgort = '0001'.
      ls_mseg-bwart = COND #( WHEN sy-index = 1 THEN '101' ELSE '261' ).
      ls_mseg-menge = sy-index * 50.
      ls_mseg-meins = 'EA'.
      ls_mseg-dmbtr = sy-index * 200.
      APPEND ls_mseg TO lt_mseg.
    ENDDO.
  ENDDO.

  MODIFY zsp26_mkpf FROM TABLE lt_mkpf.
  WRITE: / '  MKPF loaded:', lines( lt_mkpf ), 'entries'.
  MODIFY zsp26_mseg FROM TABLE lt_mseg.
  WRITE: / '  MSEG loaded:', lines( lt_mseg ), 'entries'.

*----------------------------------------------------------------------*
* 9. Load Sample Material Master (ZSP26_MARA)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_MARA sample data...'.

  DATA: ls_mara TYPE zsp26_mara,
        lt_mara TYPE TABLE OF zsp26_mara.

  DO 20 TIMES.
    CLEAR ls_mara.
    ls_mara-mandt = sy-mandt.
    ls_mara-matnr = |MAT-ZSP-{ sy-index WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
    ls_mara-ersda = sy-datum - ( sy-index * 40 ).
    ls_mara-laeda = ls_mara-ersda.
    ls_mara-mtart = COND #( WHEN sy-index <= 10 THEN 'FERT' ELSE 'ROH' ).
    ls_mara-mbrsh = 'A'.
    ls_mara-matkl = '001'.
    ls_mara-meins = 'EA'.
    ls_mara-brgew = sy-index * 5.
    ls_mara-gewei = 'KG'.
    APPEND ls_mara TO lt_mara.
  ENDDO.

  MODIFY zsp26_mara FROM TABLE lt_mara.
  WRITE: / '  MARA loaded:', lines( lt_mara ), 'entries'.

*----------------------------------------------------------------------*
* 10. Load Sample Customer Master (ZSP26_KNA1)
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '>>> Loading ZSP26_KNA1 sample data...'.

  DATA: ls_kna1 TYPE zsp26_kna1,
        lt_kna1 TYPE TABLE OF zsp26_kna1.

  DO 20 TIMES.
    CLEAR ls_kna1.
    ls_kna1-mandt = sy-mandt.
    ls_kna1-kunnr = |ZCU{ sy-index WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
    ls_kna1-erdat = sy-datum - ( sy-index * 45 ).
    ls_kna1-ernam = 'USER01'.
    ls_kna1-land1 = COND #( WHEN sy-index <= 7 THEN 'VN'
                             WHEN sy-index <= 14 THEN 'US'
                             ELSE 'DE' ).
    ls_kna1-name1 = |Customer { sy-index }|.
    ls_kna1-ort01 = |City { sy-index }|.
    ls_kna1-pstlz = |7{ sy-index WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
    ls_kna1-stras = |Street { sy-index }|.
    ls_kna1-ktokd = 'KUNA'.
    ls_kna1-waers = 'USD'.
    APPEND ls_kna1 TO lt_kna1.
  ENDDO.

  MODIFY zsp26_kna1 FROM TABLE lt_kna1.
  WRITE: / '  KNA1 loaded:', lines( lt_kna1 ), 'entries'.

*----------------------------------------------------------------------*
* Summary
*----------------------------------------------------------------------*
  WRITE: /.
  WRITE: / '============================================'.
  WRITE: / 'Sample Data Load Complete!'.
  WRITE: / '============================================'.
  WRITE: / 'Config:  7 entries (EKKO/VBAK/BKPF/MKPF/MARA/KNA1 + deps)'.
  WRITE: / 'Tables:  20 rows each x 10 source tables'.
  WRITE: / '============================================'.

  COMMIT WORK.
  WRITE: / 'All data committed successfully.'.
