*&---------------------------------------------------------------------*
*& Report ZSP26_ARCH_REGISTER
*&---------------------------------------------------------------------*
*& Register any Z table into the archive system
*& Validate DDIC → INSERT ZSP26_ARCH_CFG
*& Run from SE38, no Basis required, no archive code changes needed
*&---------------------------------------------------------------------*
REPORT zsp26_arch_register.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
PARAMETERS:
  p_table  TYPE tabname   OBLIGATORY,
  p_datfld TYPE fieldname OBLIGATORY,
  p_ret    TYPE i         DEFAULT 1825,   " days — default 5 years
  p_desc   TYPE char80,
  p_active TYPE char1     AS CHECKBOX DEFAULT 'X'.

*----------------------------------------------------------------------*
* F4: TABLE_NAME — all Z* transparent tables from DDIC
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
  TYPES: BEGIN OF ty_dd_tab,
           tabname  TYPE tabname,
           ddtext   TYPE as4text,
         END OF ty_dd_tab.
  DATA: lt_dd   TYPE TABLE OF ty_dd_tab,
        ls_dd   TYPE ty_dd_tab,
        lt_ret  TYPE TABLE OF ddshretval,
        ls_ret  TYPE ddshretval.

  SELECT tabname, ddtext FROM dd02v
    INTO CORRESPONDING FIELDS OF TABLE @lt_dd
    WHERE tabname  LIKE 'Z%'
      AND tabclass = 'TRANSP'.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'TABNAME'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'P_TABLE'
      window_title = 'Z Transparent Tables (DDIC)'
      value_org    = 'S'
    TABLES
      value_tab    = lt_dd
      return_tab   = lt_ret
    EXCEPTIONS
      OTHERS       = 0.

  READ TABLE lt_ret INTO ls_ret INDEX 1.
  IF sy-subrc = 0 AND ls_ret-fieldval IS NOT INITIAL.
    p_table = CONV tabname( ls_ret-fieldval ).
    CONDENSE p_table.
    TRANSLATE p_table TO UPPER CASE.
  ENDIF.

*----------------------------------------------------------------------*
* F4: DATA_FIELD — show only DATE fields of selected table
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_datfld.
  TYPES: BEGIN OF ty_fld_f4,
           fieldname TYPE fieldname,
           ddtext    TYPE as4text,
         END OF ty_fld_f4.
  DATA: lt_flds TYPE TABLE OF ty_fld_f4,
        ls_fld  TYPE ty_fld_f4,
        lt_dd2  TYPE TABLE OF dfies,
        ls_dd2  TYPE dfies,
        lt_ret2 TYPE TABLE OF ddshretval,
        ls_ret2 TYPE ddshretval.

  IF p_table IS INITIAL.
    MESSAGE 'Enter Table Name before selecting Data Field.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = p_table
    TABLES     dfies_tab = lt_dd2
    EXCEPTIONS OTHERS    = 1.

  IF sy-subrc <> 0.
    MESSAGE |Cannot read table structure for { p_table } from DDIC.| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " Only DATE-type fields (inttype='D'), excluding MANDT
  LOOP AT lt_dd2 INTO ls_dd2
    WHERE inttype = 'D' AND fieldname <> 'MANDT'.
    CLEAR ls_fld.
    ls_fld-fieldname = ls_dd2-fieldname.
    ls_fld-ddtext    = ls_dd2-fieldtext.
    APPEND ls_fld TO lt_flds.
  ENDLOOP.

  IF lt_flds IS INITIAL.
    MESSAGE |Table { p_table } has no DATE-type field - cannot archive by date.| TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'FIELDNAME'
      dynpprog     = sy-repid
      dynpnr       = sy-dynnr
      dynprofield  = 'P_DATFLD'
      window_title = |Date Fields of { p_table }|
      value_org    = 'S'
    TABLES
      value_tab    = lt_flds
      return_tab   = lt_ret2
    EXCEPTIONS
      OTHERS       = 0.

  READ TABLE lt_ret2 INTO ls_ret2 INDEX 1.
  IF sy-subrc = 0 AND ls_ret2-fieldval IS NOT INITIAL.
    p_datfld = CONV fieldname( ls_ret2-fieldval ).
    CONDENSE p_datfld.
    TRANSLATE p_datfld TO UPPER CASE.
  ENDIF.

*----------------------------------------------------------------------*
* START-OF-SELECTION: Validate + INSERT ZSP26_ARCH_CFG
*----------------------------------------------------------------------*
START-OF-SELECTION.

  CONDENSE p_table  NO-GAPS.
  CONDENSE p_datfld NO-GAPS.
  TRANSLATE p_table  TO UPPER CASE.
  TRANSLATE p_datfld TO UPPER CASE.

  DATA: lt_fields  TYPE TABLE OF dfies,
        ls_field   TYPE dfies,
        lv_ok      TYPE abap_bool VALUE abap_true,
        lv_has_mandt TYPE abap_bool VALUE abap_false,
        lv_has_key   TYPE abap_bool VALUE abap_false,
        lv_datfld_ok TYPE abap_bool VALUE abap_false.

  " ---------------------------------------------------------------
  " Step 1: Does the table exist in DDIC?
  " ---------------------------------------------------------------
  DATA: ls_dd02 TYPE dd02v.
  SELECT SINGLE tabname, tabclass FROM dd02v
    INTO (@ls_dd02-tabname, @ls_dd02-tabclass)
    WHERE tabname = @p_table.

  IF sy-subrc <> 0.
    WRITE: / |✗ Table { p_table } does not exist in DDIC or is not activated.|.
    lv_ok = abap_false.
  ELSEIF ls_dd02-tabclass <> 'TRANSP'.
    WRITE: / |✗ Table { p_table } is not a transparent table (type: { ls_dd02-tabclass }).|.
    lv_ok = abap_false.
  ELSE.
    WRITE: / |✓ Table { p_table } exists in DDIC (TRANSP).|.
  ENDIF.

  IF lv_ok = abap_false. STOP. ENDIF.

  " ---------------------------------------------------------------
  " Step 2: Read table structure from DDIC
  " ---------------------------------------------------------------
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = p_table
    TABLES     dfies_tab = lt_fields
    EXCEPTIONS OTHERS    = 1.

  IF sy-subrc <> 0.
    WRITE: / |✗ Cannot read field list of { p_table }.|.
    STOP.
  ENDIF.

  " ---------------------------------------------------------------
  " Step 3: Check MANDT
  " ---------------------------------------------------------------
  LOOP AT lt_fields INTO ls_field WHERE fieldname = 'MANDT'.
    lv_has_mandt = abap_true. EXIT.
  ENDLOOP.

  IF lv_has_mandt = abap_true.
    WRITE: / |✓ MANDT field found (client-dependent).|.
  ELSE.
    WRITE: / |✗ No MANDT field - table is not client-dependent, cannot archive.|.
    lv_ok = abap_false.
  ENDIF.

  " ---------------------------------------------------------------
  " Step 4: Check key field besides MANDT
  " ---------------------------------------------------------------
  LOOP AT lt_fields INTO ls_field
    WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
    lv_has_key = abap_true. EXIT.
  ENDLOOP.

  IF lv_has_key = abap_true.
    WRITE: / |✓ Key field found besides MANDT (required for DELETE).|.
  ELSE.
    WRITE: / |✗ No key field besides MANDT - DELETE will not work.|.
    lv_ok = abap_false.
  ENDIF.

  " ---------------------------------------------------------------
  " Step 5: Check DATA_FIELD exists and is DATE type
  " ---------------------------------------------------------------
  LOOP AT lt_fields INTO ls_field WHERE fieldname = p_datfld.
    IF ls_field-inttype = 'D'.
      lv_datfld_ok = abap_true.
      WRITE: / |✓ Field { p_datfld } exists and is DATE type (DATS).|.
    ELSE.
      WRITE: / |✗ Field { p_datfld } exists but is not DATE type (type: { ls_field-inttype }) - please select a DATE field.|.
      lv_ok = abap_false.
    ENDIF.
    EXIT.
  ENDLOOP.
  IF sy-subrc <> 0.
    WRITE: / |✗ Field { p_datfld } does not exist in table { p_table }.|.
    lv_ok = abap_false.
  ENDIF.

  " ---------------------------------------------------------------
  " Step 6: Check for duplicate config
  " ---------------------------------------------------------------
  SELECT SINGLE config_id FROM zsp26_arch_cfg
    INTO @DATA(lv_dup_cfgid)
    WHERE table_name = @p_table
      AND is_active  = 'X'.
  IF sy-subrc = 0.
    WRITE: / |✗ Active config already exists for { p_table } (ID: { lv_dup_cfgid }). Deactivate old config before creating a new one.|.
    lv_ok = abap_false.
  ENDIF.

  SKIP.

  " ---------------------------------------------------------------
  " Validation result
  " ---------------------------------------------------------------
  IF lv_ok = abap_false.
    WRITE: / '--- Validation FAILED - config not inserted. Check errors marked above. ---'.
    STOP.
  ENDIF.

  WRITE: / '--- Validation PASSED - inserting config... ---'.

  " ---------------------------------------------------------------
  " INSERT ZSP26_ARCH_CFG
  " ---------------------------------------------------------------
  DATA: ls_cfg   TYPE zsp26_arch_cfg,
        lv_uuid  TYPE sysuuid_x16.

  TRY.
    lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
  CATCH cx_uuid_error.
    WRITE: / 'UUID generation error.'. STOP.
  ENDTRY.

  CLEAR ls_cfg.
  ls_cfg-mandt      = sy-mandt.
  ls_cfg-config_id  = lv_uuid.
  ls_cfg-table_name = p_table.
  ls_cfg-description = p_desc.
  ls_cfg-retention  = p_ret.
  ls_cfg-data_field = p_datfld.
  ls_cfg-is_active  = p_active.
  ls_cfg-created_by = sy-uname.
  ls_cfg-created_on = sy-datum.

  INSERT zsp26_arch_cfg FROM ls_cfg.
  IF sy-subrc = 0.
    COMMIT WORK.
    DATA: lv_years TYPE p DECIMALS 1.
    lv_years = p_ret / 365.
    SKIP.
    WRITE: / |✓ Table { p_table } registered in archive system.|.
    WRITE: / |  Config ID : { lv_uuid }|.
    WRITE: / |  Data Field: { p_datfld }|.
    WRITE: / |  Retention : { p_ret } days (|.
    WRITE: lv_years. WRITE: 'years)'.
    WRITE: / |  Active    : { p_active }|.
    SKIP.
    WRITE: / 'Next: Go to Z_GSP18_SAP15_MAIN > select table > Preview > Archive.'.
  ELSE.
    WRITE: / |✗ INSERT error ZSP26_ARCH_CFG (sy-subrc={ sy-subrc }).|.
  ENDIF.
