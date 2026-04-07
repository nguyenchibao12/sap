*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_WRITE
*& ADK Write — Archive Object Z_ARCH_EKK
*& Dynamic: any transparent table with active row in ZSP26_ARCH_CFG
*& Flow: OPEN_FOR_WRITE → IMPORT archive_handle → ARCHIVE_REGISTER_STRUCTURES
*&       (DDIC name = target table) → ARCHIVE_NEW_OBJECT → ARCHIVE_PUT_TABLE
*& CREATE DATA + ASSIGN → dynamic SELECT with WHERE from CFG (+ optional RULE EQ)
*& Log ZSP26_ARCH_LOG after ARCHIVE_CLOSE_OBJECT (CONFIG_ID, timestamps)
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_write.

INCLUDE z_gsp18_apply_rules.
INCLUDE z_gsp18_arch_dyn.

TYPES: BEGIN OF ty_cfg_disp,
         table_name  TYPE tabname,
         data_field  TYPE fieldname,
         retention   TYPE i,
         is_active   TYPE c,
         eligible    TYPE i,
         cutoff_date TYPE d,
       END OF ty_cfg_disp.

DATA: gs_cfg    TYPE zsp26_arch_cfg,
      gr_src    TYPE REF TO data,
      lt_dd     TYPE TABLE OF dfies,
      lv_cutoff TYPE d,
      lv_cnt    TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0,
      lv_arch_h TYPE syst-tabix,
      lv_cfg_ok TYPE abap_bool,
      lv_ts_s   TYPE timestampl,
      lv_ts_e   TYPE timestampl.

FIELD-SYMBOLS: <lt_src> TYPE STANDARD TABLE,
               <row>    TYPE any.

" g_scr_h0 / g_scr_h1: do COMMENT /1(79) tự khai báo — không thêm DATA (trùng trên ADT/bản mới)

SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME.
SELECTION-SCREEN COMMENT /1(79) g_scr_h0.
PARAMETERS: p_table TYPE tabname OBLIGATORY DEFAULT 'ZSP26_EKKO'.
SELECTION-SCREEN END OF BLOCK b0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
SELECTION-SCREEN COMMENT /1(72) g_scr_h1.
SELECT-OPTIONS: s_date FOR sy-datum.
PARAMETERS:     p_keyf TYPE char50,
                p_test TYPE c AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN: BEGIN OF LINE,
  PUSHBUTTON 1(25)  bt_tbls USER-COMMAND show_tbls,
  PUSHBUTTON 28(25) bt_data USER-COMMAND show_data.
SELECTION-SCREEN END OF LINE.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  g_scr_h0 = 'Table: F4 = ZSP26_ARCH_CFG. Uncheck P_TEST for ADK PUT_TABLE (Z_ARCH_EKK).'.
  g_scr_h1 = 'WHERE = DATA_FIELD/RETENTION (+ EQ rules w/o OR). Rules also in ABAP (apply_archive_rules).'.
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
      DATA: lt_cfg    TYPE TABLE OF ty_cfg_disp,
            ls_cfg    TYPE ty_cfg_disp,
            lt_cfgraw TYPE TABLE OF zsp26_arch_cfg,
            ls_cfgraw TYPE zsp26_arch_cfg,
            lv_wh     TYPE string,
            lv_cnt2   TYPE i,
            lv_co_pop TYPE d.

      REFRESH: lt_cfg, lt_cfgraw.
      SELECT * FROM zsp26_arch_cfg INTO TABLE @lt_cfgraw WHERE is_active = 'X'.

      LOOP AT lt_cfgraw INTO ls_cfgraw.
        CLEAR ls_cfg.
        ls_cfg-table_name  = ls_cfgraw-table_name.
        ls_cfg-data_field  = ls_cfgraw-data_field.
        ls_cfg-retention   = ls_cfgraw-retention.
        ls_cfg-is_active   = ls_cfgraw-is_active.
        lv_co_pop = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                            ELSE sy-datum - ls_cfgraw-retention ).
        ls_cfg-cutoff_date = lv_co_pop.

        CLEAR: lv_cnt2, lv_wh.
        PERFORM build_where_from_arch_cfg
          USING ls_cfgraw s_date-low lv_co_pop
          CHANGING lv_wh.
        SELECT COUNT(*) FROM (ls_cfgraw-table_name) INTO @lv_cnt2
          WHERE (lv_wh).
        ls_cfg-eligible = lv_cnt2.

        APPEND ls_cfg TO lt_cfg.
      ENDLOOP.

      DATA: lo_alv  TYPE REF TO cl_salv_table,
            lo_col  TYPE REF TO cl_salv_column.
      TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = lt_cfg ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).

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
      PERFORM validate_table_against_cfg
        USING p_table CHANGING gs_cfg lv_cfg_ok.
      IF lv_cfg_ok = abap_false.
        MESSAGE |No active ZSP26_ARCH_CFG / invalid DDIC for '{ p_table }'| TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.

      DATA: lv_co TYPE d,
            lv_w2 TYPE string.
      lv_co = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                      ELSE sy-datum - gs_cfg-retention ).

      CREATE DATA gr_src TYPE TABLE OF (p_table).
      ASSIGN gr_src->* TO <lt_src>.
      PERFORM build_where_from_arch_cfg
        USING gs_cfg s_date-low lv_co
        CHANGING lv_w2.
      PERFORM append_rules_eq_to_where USING gs_cfg-config_id p_table CHANGING lv_w2.
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
          |[PREVIEW] { p_table } — { lines( <lt_src> ) } rows (dynamic line type)| ).
        lo_alv2->display( ).
      CATCH cx_salv_msg. ENDTRY.

  ENDCASE.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  CLEAR: lv_cnt, lv_err.

  PERFORM validate_table_against_cfg
    USING p_table CHANGING gs_cfg lv_cfg_ok.
  IF lv_cfg_ok = abap_false.
    MESSAGE |Invalid archive target '{ p_table }': no active ZSP26_ARCH_CFG or DATA_FIELD not in DDIC.|
            TYPE 'A'.
  ENDIF.

  lv_cutoff = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                      ELSE sy-datum - gs_cfg-retention ).

  WRITE: /.
  WRITE: / |=== ADK Write (PUT_TABLE): { p_table } - Object Z_ARCH_EKK ===|.
  WRITE: / |CONFIG_ID  : { gs_cfg-config_id }|.
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
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no archive I/O ***'. ENDIF.
  WRITE: /.

  DATA: lv_where TYPE string.
  PERFORM build_where_from_arch_cfg
    USING gs_cfg s_date-low lv_cutoff
    CHANGING lv_where.
  PERFORM append_rules_eq_to_where USING gs_cfg-config_id p_table CHANGING lv_where.

  " Runtime memory for target rows: CREATE DATA creates heap data; ASSIGN binds field-symbol
  CREATE DATA gr_src TYPE TABLE OF (p_table).
  ASSIGN gr_src->* TO <lt_src>.
  SELECT * FROM (p_table) INTO TABLE <lt_src> WHERE (lv_where).

  PERFORM apply_rules_to_src.

  IF p_keyf IS NOT INITIAL.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING  tabname   = p_table
      TABLES     dfies_tab = lt_dd
      EXCEPTIONS OTHERS    = 1.
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
    WRITE: / 'No eligible rows — nothing to archive.'.
    RETURN.
  ENDIF.

  IF p_test = ' '.
    GET TIME STAMP FIELD lv_ts_s.

    CALL FUNCTION 'ARCHIVE_OPEN_FOR_WRITE'
      EXPORTING
        object              = 'Z_ARCH_EKK'
        create_archive_file = 'X'
      IMPORTING
        archive_handle      = lv_arch_h
      EXCEPTIONS
        internal_error                = 1
        object_not_found              = 2
        open_error                    = 3
        not_authorized                = 4
        archiving_standard_violation  = 5
        OTHERS                        = 6.
    IF sy-subrc <> 0.
      MESSAGE 'ARCHIVE_OPEN_FOR_WRITE failed. Check AOBJ Z_ARCH_EKK / authorizations.' TYPE 'A'.
    ENDIF.

    " Position: immediately after OPEN — register DDIC line type of target table (TABNAME = structure)
    DATA: lt_reg TYPE TABLE OF arch_ddic,
          ls_reg TYPE arch_ddic.
    CLEAR ls_reg.
    ls_reg-name = p_table.
    APPEND ls_reg TO lt_reg.

    CALL FUNCTION 'ARCHIVE_REGISTER_STRUCTURES'
      EXPORTING
        archive_handle = lv_arch_h
      TABLES
        record_structures = lt_reg
      EXCEPTIONS
        no_new_structures_permitted = 1
        wrong_access_to_archive     = 2
        OTHERS                      = 3.
    IF sy-subrc <> 0.
      WRITE: / |WARN: ARCHIVE_REGISTER_STRUCTURES RC={ sy-subrc } (check ADK / DDIC)|.
    ENDIF.

    CALL FUNCTION 'ARCHIVE_NEW_OBJECT'
      EXPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        internal_error            = 1
        wrong_access_to_archive   = 2
        OTHERS                    = 3.
    IF sy-subrc <> 0.
      MESSAGE 'ARCHIVE_NEW_OBJECT failed.' TYPE 'A'.
    ENDIF.

    CALL FUNCTION 'ARCHIVE_PUT_TABLE'
      EXPORTING
        archive_handle   = lv_arch_h
        record_structure = p_table
      TABLES
        table            = <lt_src>
      EXCEPTIONS
        internal_error            = 1
        wrong_access_to_archive   = 2
        invalid_record_structure  = 3
        OTHERS                    = 4.
    IF sy-subrc <> 0.
      lv_err = lv_err + 1.
      WRITE: / |ERROR: ARCHIVE_PUT_TABLE RC={ sy-subrc }|.
      CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
        EXPORTING object_count = 0
        EXCEPTIONS OTHERS      = 1.
      MESSAGE 'Archive write failed (PUT_TABLE).' TYPE 'A'.
    ENDIF.

    lv_cnt = lines( <lt_src> ).

    CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
      EXPORTING
        object_count = lv_cnt
      EXCEPTIONS
        OTHERS       = 1.

    GET TIME STAMP FIELD lv_ts_e.

    DATA: ls_log TYPE zsp26_arch_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-config_id   = gs_cfg-config_id.
    ls_log-table_name  = p_table.
    ls_log-action      = 'ARCHIVE'.
    ls_log-rec_count   = lv_cnt.
    ls_log-status      = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-start_time  = lv_ts_s.
    ls_log-end_time    = lv_ts_e.
    ls_log-exec_user   = sy-uname.
    ls_log-exec_date   = sy-datum.
    ls_log-message     = |ADK PUT_TABLE { lv_cnt } rows. Cutoff { lv_cutoff }. HANDLE={ lv_arch_h }|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.
  ENDIF.

  WRITE: /.
  WRITE: / '=== Summary ==='.
  WRITE: / |Rows in selection: { lines( <lt_src> ) }|.
  IF p_test = ' '.
    WRITE: / |Archived (PUT_TABLE): { lv_cnt }|.
    WRITE: / 'Next: Z_ARCH_EKK_DELETE via SARA (uncheck P_JSON if using this PUT_TABLE format).'.
  ELSE.
    WRITE: / 'Uncheck Test Mode to run OPEN → REGISTER_STRUCTURES → NEW_OBJECT → PUT_TABLE → CLOSE.'.
  ENDIF.

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
FORM f4_arch_cfg_table.
  TYPES: BEGIN OF ty_sht_f4,
           table_name  TYPE tabname,
           description TYPE char80,
         END OF ty_sht_f4.
  DATA lt_sht TYPE STANDARD TABLE OF ty_sht_f4 WITH DEFAULT KEY.

  SELECT table_name, description
    FROM zsp26_arch_cfg
    WHERE is_active = 'X'
    INTO CORRESPONDING FIELDS OF TABLE @lt_sht
    UP TO 999 ROWS.
  IF lt_sht IS INITIAL.
    SELECT table_name, description
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
      dynprofield  = 'P_TABLE'
      value_org    = 'S'
    TABLES
      value_tab    = lt_sht
    EXCEPTIONS
      OTHERS       = 0.

  DATA: lt_df TYPE TABLE OF dynpread,
        ls_df TYPE dynpread.
  CLEAR lt_df.
  ls_df-fieldname = 'P_TABLE'.
  APPEND ls_df TO lt_df.
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING
      dyname     = sy-repid
      dynumb     = sy-dynnr
    TABLES
      dynpfields = lt_df
    EXCEPTIONS
      OTHERS     = 1.
  READ TABLE lt_df INTO ls_df INDEX 1.
  IF sy-subrc = 0 AND ls_df-fieldvalue IS NOT INITIAL.
    p_table = CONV tabname( ls_df-fieldvalue ).
    CONDENSE p_table.
    TRANSLATE p_table TO UPPER CASE.
  ENDIF.
ENDFORM.
