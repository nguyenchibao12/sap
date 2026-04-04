*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_WRITE
*& ADK Write Program — Archive Object Z_ARCH_EKK
*& Generic: archives any ZSP26_* table configured in ZSP26_ARCH_CFG
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_write.

INCLUDE z_gsp18_apply_rules.

"----------------------------------------------------------------------
" Archive record structure written to ADK file — fixed length, no string
"----------------------------------------------------------------------
TYPES: BEGIN OF ty_arch_rec,
         rec_type   TYPE c LENGTH 1,     " 'D' = data record
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_arch_rec.

TYPES: BEGIN OF ty_cfg_disp,
         table_name  TYPE tabname,
         data_field  TYPE fieldname,
         retention   TYPE i,
         is_active   TYPE c,
         eligible    TYPE i,
         cutoff_date TYPE d,
       END OF ty_cfg_disp.

DATA: gs_cfg    TYPE zsp26_arch_cfg,
      ls_arec   TYPE ty_arch_rec,
      gr_src    TYPE REF TO data,
      lt_dd     TYPE TABLE OF dfies,
      lv_cutoff TYPE d,
      lv_cnt    TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0.

FIELD-SYMBOLS: <lt_src> TYPE ANY TABLE,
               <row>    TYPE any.

DATA: g_scr_h0(72) TYPE c,
      g_scr_h1(72) TYPE c.

"----------------------------------------------------------------------
" Selection Screen — demo-friendly: hints + F4 on P_TABLE (ZSP26_ARCH_CFG)
"----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME.
SELECTION-SCREEN COMMENT /1(72) g_scr_h0.
PARAMETERS: p_table TYPE tabname OBLIGATORY DEFAULT 'ZSP26_EKKO'.
SELECTION-SCREEN END OF BLOCK b0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
SELECTION-SCREEN COMMENT /1(72) g_scr_h1.
SELECT-OPTIONS: s_date FOR sy-datum.   " Date range (maps to config date field)
PARAMETERS:     p_keyf TYPE char50,    " Key value filter (e.g. PO#, Doc#)
                p_test TYPE c AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN: BEGIN OF LINE,
  PUSHBUTTON 1(25)  bt_tbls USER-COMMAND show_tbls,
  PUSHBUTTON 28(25) bt_data USER-COMMAND show_data.
SELECTION-SCREEN END OF LINE.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  g_scr_h0 = 'Table: F4 = active ZSP26_ARCH_CFG. Uncheck P_TEST for real ADK write to .ARC.'.
  g_scr_h1 = 'Date/key optional. Buttons: Show All Tables (counts) | Show Eligible Data for P_TABLE.'.
  bt_tbls = 'Show All Tables'.
  bt_data = 'Show Eligible Data'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
*----------------------------------------------------------------------*
  PERFORM f4_arch_cfg_table.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  CASE sy-ucomm.

    WHEN 'SHOW_TBLS'.
      " Show all configured tables with eligible record counts
      DATA: lt_cfg    TYPE TABLE OF ty_cfg_disp,
            ls_cfg    TYPE ty_cfg_disp,
            lt_cfgraw TYPE TABLE OF zsp26_arch_cfg,
            ls_cfgraw TYPE zsp26_arch_cfg,
            lv_wh     TYPE string,
            lv_cnt2   TYPE i.

      REFRESH: lt_cfg, lt_cfgraw.
      SELECT * FROM zsp26_arch_cfg INTO TABLE @lt_cfgraw WHERE is_active = 'X'.

      LOOP AT lt_cfgraw INTO ls_cfgraw.
        CLEAR ls_cfg.
        ls_cfg-table_name  = ls_cfgraw-table_name.
        ls_cfg-data_field  = ls_cfgraw-data_field.
        ls_cfg-retention   = ls_cfgraw-retention.
        ls_cfg-is_active   = ls_cfgraw-is_active.
        ls_cfg-cutoff_date = sy-datum - ls_cfgraw-retention.

        " Count eligible records dynamically
        CLEAR: lv_cnt2, lv_wh.
        lv_wh = |{ ls_cfgraw-data_field } LE '{ ls_cfg-cutoff_date }'|.
        SELECT COUNT(*) FROM (ls_cfgraw-table_name) INTO @lv_cnt2
          WHERE (lv_wh).
        ls_cfg-eligible = lv_cnt2.

        APPEND ls_cfg TO lt_cfg.
      ENDLOOP.

      " Display via SALV popup
      DATA: lo_alv  TYPE REF TO cl_salv_table,
            lo_col  TYPE REF TO cl_salv_column.
      TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = lt_cfg ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).

        " Set column headers manually
        DATA(lo_cols) = lo_alv->get_columns( ).
        TRY. lo_col ?= lo_cols->get_column( 'TABLE_NAME' ).
             lo_col->set_long_text( 'Table Name' ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_col ?= lo_cols->get_column( 'DATA_FIELD' ).
             lo_col->set_long_text( 'Date Field' ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_col ?= lo_cols->get_column( 'RETENTION' ).
             lo_col->set_long_text( 'Retention (Days)' ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_col ?= lo_cols->get_column( 'IS_ACTIVE' ).
             lo_col->set_long_text( 'Active' ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_col ?= lo_cols->get_column( 'ELIGIBLE' ).
             lo_col->set_long_text( 'Eligible Records' ). CATCH cx_salv_not_found. ENDTRY.
        TRY. lo_col ?= lo_cols->get_column( 'CUTOFF_DATE' ).
             lo_col->set_long_text( 'Cutoff Date' ). CATCH cx_salv_not_found. ENDTRY.

        lo_alv->get_display_settings( )->set_list_header(
          'Archive Configuration — All Active Tables' ).
        lo_alv->display( ).
      CATCH cx_salv_msg. ENDTRY.

    WHEN 'SHOW_DATA'.
      " Show eligible records for selected p_table
      SELECT SINGLE * FROM zsp26_arch_cfg INTO @gs_cfg
        WHERE table_name = @p_table AND is_active = 'X'.
      IF sy-subrc <> 0.
        MESSAGE |No active config for '{ p_table }'| TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.

      DATA: lv_co TYPE d,
            lv_w2 TYPE string.
      lv_co = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                      ELSE sy-datum - gs_cfg-retention ).

      CREATE DATA gr_src TYPE TABLE OF (p_table).
      ASSIGN gr_src->* TO <lt_src>.
      IF s_date-low IS NOT INITIAL.
        lv_w2 = |{ gs_cfg-data_field } GE '{ s_date-low }' AND { gs_cfg-data_field } LE '{ lv_co }'|.
      ELSE.
        lv_w2 = |{ gs_cfg-data_field } LE '{ lv_co }'|.
      ENDIF.
      SELECT * FROM (p_table) INTO TABLE <lt_src> WHERE (lv_w2).

      PERFORM apply_rules_to_src.

      IF <lt_src> IS INITIAL.
        MESSAGE |No eligible records in { p_table } (cutoff: { lv_co })| TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.

      DATA: lo_alv2 TYPE REF TO cl_salv_table.
      TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv2
          CHANGING  t_table      = <lt_src> ).
        lo_alv2->get_functions( )->set_all( abap_true ).
        lo_alv2->get_columns( )->set_optimize( abap_true ).
        lo_alv2->get_display_settings( )->set_list_header(
          |[PREVIEW] { p_table } — { s_date-low } to { lv_co } — { lines( <lt_src> ) } records| ).
        lo_alv2->display( ).
      CATCH cx_salv_msg. ENDTRY.

  ENDCASE.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  " 1. Read archive config
  SELECT SINGLE * FROM zsp26_arch_cfg INTO @gs_cfg
    WHERE table_name = @p_table AND is_active = 'X'.
  IF sy-subrc <> 0.
    MESSAGE |Chưa có config active cho '{ p_table }'.| TYPE 'A'.
  ENDIF.
  IF gs_cfg-data_field IS INITIAL.
    MESSAGE |Config cho '{ p_table }' thiếu Date Field.| TYPE 'A'.
  ENDIF.

  " 2. Cutoff date (Date To)
  lv_cutoff = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                      ELSE sy-datum - gs_cfg-retention ).

  WRITE: /.
  WRITE: / |=== ADK Write: { p_table } ===|.
  WRITE: / |Date Field : { gs_cfg-data_field }|.
  WRITE: / |Retention  : { gs_cfg-retention } days|.
  IF s_date-low IS NOT INITIAL.
    WRITE: / |Date From  : { s_date-low }|.
  ELSE.
    WRITE: / 'Date From  : (no lower bound)'.
  ENDIF.
  WRITE: / |Date To    : { lv_cutoff }|.
  IF p_keyf IS NOT INITIAL.
    WRITE: / |Key Filter : { p_keyf }|.
  ENDIF.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no data written to archive ***'. ENDIF.
  WRITE: /.

  " 3. Open archive for write (skip in test mode)
  IF p_test = ' '.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_WRITE'
      EXPORTING
        archiv_obj = 'Z_ARCH_EKK'
      EXCEPTIONS
        open_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      MESSAGE 'Cannot open archive Z_ARCH_EKK. Check AOBJ/SARA config.' TYPE 'A'.
    ENDIF.
  ENDIF.

  " 4. Get key fields from DDIC
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = p_table
    TABLES     dfies_tab = lt_dd
    EXCEPTIONS OTHERS    = 1.

  " 5. Dynamic SELECT — only eligible records
  CREATE DATA gr_src TYPE TABLE OF (p_table).
  ASSIGN gr_src->* TO <lt_src>.
  DATA: lv_where TYPE string.
  IF s_date-low IS NOT INITIAL.
    lv_where = |{ gs_cfg-data_field } GE '{ s_date-low }' AND { gs_cfg-data_field } LE '{ lv_cutoff }'|.
  ELSE.
    lv_where = |{ gs_cfg-data_field } LE '{ lv_cutoff }'|.
  ENDIF.
  SELECT * FROM (p_table) INTO TABLE <lt_src> WHERE (lv_where).

  PERFORM apply_rules_to_src.

  " Apply key value filter if specified (post-select filter on key_vals string)
  IF p_keyf IS NOT INITIAL.
    LOOP AT <lt_src> ASSIGNING FIELD-SYMBOL(<frow>).
      DATA: lv_kcheck TYPE char255.
      CLEAR lv_kcheck.
      LOOP AT lt_dd INTO DATA(ls_kdd) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
        ASSIGN COMPONENT ls_kdd-fieldname OF STRUCTURE <frow> TO FIELD-SYMBOL(<fkv>).
        IF <fkv> IS ASSIGNED. lv_kcheck &&= <fkv>. ENDIF.
      ENDLOOP.
      IF lv_kcheck NS p_keyf.
        DELETE <lt_src>.
      ENDIF.
    ENDLOOP.
  ENDIF.

  WRITE: / |Records eligible: { lines( <lt_src> ) }|.

  IF <lt_src> IS INITIAL.
    WRITE: / 'Không có records đủ điều kiện.'.
    IF p_test = ' '.
      CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
        EXPORTING object_count = 0
        EXCEPTIONS OTHERS      = 1.
    ENDIF.
    RETURN.
  ENDIF.

  " 6. Write each record to archive file
  LOOP AT <lt_src> ASSIGNING <row>.
    " Build key string: FIELD1=VAL1|FIELD2=VAL2
    DATA: lv_kv TYPE char255.
    CLEAR lv_kv.
    LOOP AT lt_dd INTO DATA(ls_dd) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
      ASSIGN COMPONENT ls_dd-fieldname OF STRUCTURE <row> TO FIELD-SYMBOL(<fv>).
      IF <fv> IS ASSIGNED.
        IF lv_kv IS NOT INITIAL. lv_kv &&= '|'. ENDIF.
        lv_kv &&= ls_dd-fieldname && '=' && <fv>.
      ENDIF.
    ENDLOOP.

    " Serialize to JSON
    DATA: lv_json TYPE string,
          lv_jc   TYPE c LENGTH 4990.
    CLEAR: lv_json, lv_jc.
    TRY.
      lv_json = /ui2/cl_json=>serialize( data = <row> ).
    CATCH cx_root.
      lv_json = lv_kv.
    ENDTRY.
    lv_jc = lv_json.

    " Build archive record
    CLEAR ls_arec.
    ls_arec-rec_type   = 'D'.
    ls_arec-table_name = p_table.
    ls_arec-key_vals   = lv_kv.
    ls_arec-data_json  = lv_jc.

    IF p_test = ' '.
      CALL FUNCTION 'ARCHIVE_WRITE_RECORD'
        EXPORTING  record        = ls_arec
        EXCEPTIONS end_of_object = 1
                   OTHERS        = 2.
      IF sy-subrc <> 0.
        ADD 1 TO lv_err.
        WRITE: / |  ERROR: { lv_kv }|.
        CONTINUE.
      ENDIF.
    ELSE.
      WRITE: / |  [TEST] { lv_kv }|.
    ENDIF.

    ADD 1 TO lv_cnt.
  ENDLOOP.

  " 7. Close archive object
  IF p_test = ' '.
    CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
      EXPORTING  object_count = lv_cnt
      EXCEPTIONS OTHERS       = 1.
  ENDIF.

  " 8. Log to ZSP26_ARCH_LOG
  IF p_test = ' '.
    DATA: ls_log TYPE zsp26_arch_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-table_name = p_table.
    ls_log-action     = 'ARCHIVE'.
    ls_log-rec_count  = lv_cnt.
    ls_log-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    ls_log-message    = |ADK Archive: { lv_cnt } records written. Cutoff: { lv_cutoff }. Errors: { lv_err }|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.
  ENDIF.

  " 9. Summary
  WRITE: /.
  WRITE: / '=== Summary ==='.
  WRITE: / |Written to archive: { lv_cnt } records|.
  WRITE: / |Errors            : { lv_err }|.
  IF p_test = ' '.
    WRITE: / 'Next step: run Z_ARCH_EKK_DELETE via SARA to remove from DB.'.
  ELSE.
    WRITE: / 'Uncheck Test Mode and re-run to actually archive.'.
  ENDIF.

*&---------------------------------------------------------------------*
*& Remove rows that fail ZSP26_ARCH_RULE (same logic as main preview)
*&---------------------------------------------------------------------*
FORM apply_rules_to_src.
  DATA: lv_ix TYPE i,
        lv_rp TYPE abap_bool.
  FIELD-SYMBOLS: <lr> TYPE any.
  IF NOT <lt_src> IS ASSIGNED.
    RETURN.
  ENDIF.
  lv_ix = lines( <lt_src> ).
  WHILE lv_ix >= 1.
    READ TABLE <lt_src> INDEX lv_ix ASSIGNING <lr>.
    IF sy-subrc <> 0.
      lv_ix = lv_ix - 1.
      CONTINUE.
    ENDIF.
    PERFORM apply_archive_rules USING <lr> gs_cfg-config_id CHANGING lv_rp.
    IF lv_rp = abap_false.
      DELETE <lt_src> INDEX lv_ix.
    ENDIF.
    lv_ix = lv_ix - 1.
  ENDWHILE.
ENDFORM.

*&---------------------------------------------------------------------*
*& F4: list TABLE_NAME from ZSP26_ARCH_CFG (active only)
*&---------------------------------------------------------------------*
FORM f4_arch_cfg_table.
  DATA: lt_val TYPE TABLE OF help_value,
        ls_val TYPE help_value.

  SELECT DISTINCT table_name FROM zsp26_arch_cfg
    INTO TABLE @DATA(lt_names)
    WHERE is_active = 'X'
    ORDER BY table_name.

  LOOP AT lt_names INTO DATA(ls_nm).
    CLEAR ls_val.
    ls_val-value = ls_nm-table_name.
    APPEND ls_val TO lt_val.
  ENDLOOP.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'VALUE'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'P_TABLE'
      value_org       = 'S'
    TABLES
      value_tab       = lt_val
    EXCEPTIONS
      OTHERS          = 2.
ENDFORM.
