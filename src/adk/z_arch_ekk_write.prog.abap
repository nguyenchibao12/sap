*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_WRITE
*& ADK Write — Archive Object Z_ARCH_EKK
*& Dynamic: any transparent table with active row in ZSP26_ARCH_CFG
*& Flow: OPEN_FOR_WRITE → IMPORT archive_handle → ARCHIVE_REGISTER_STRUCTURES
*&       (DDIC name = target table) → ARCHIVE_NEW_OBJECT → ARCHIVE_PUT_TABLE
*&       → ARCHIVE_SAVE_OBJECT → ARCHIVE_CLOSE_FILE
*& CREATE DATA + ASSIGN → dynamic SELECT with WHERE from CFG (+ optional RULE EQ)
*& Log ZSP26_ARCH_LOG after ARCHIVE_CLOSE_FILE (CONFIG_ID, timestamps)
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_write.

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
      gr_arch   TYPE REF TO data,
      lt_dd     TYPE TABLE OF dfies,
      lv_cutoff TYPE d,
      lv_cnt    TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0,
      lv_arch_h TYPE syst-tabix,
      lv_cfg_ok TYPE abap_bool,
      lv_ts_s   TYPE timestampl,
      lv_ts_e   TYPE timestampl,
      lv_sql_elig_cnt TYPE i,
      lv_tbl_tot      TYPE i,
      lv_tpl_cid      TYPE zsp26_arch_cfg-config_id,
      lv_tpl_df       TYPE zsp26_arch_cfg-data_field,
      lv_tpl_ret      TYPE zsp26_arch_cfg-retention.

CONSTANTS: lc_max_rows TYPE i VALUE 500000.

FIELD-SYMBOLS: <lt_src> TYPE STANDARD TABLE,
               <lt_arch> TYPE STANDARD TABLE,
               <row>    TYPE any.

" g_scr_h0 / g_scr_h1: COMMENT /1(79) auto-declares these — do not add DATA (conflicts on ADT/newer releases)

SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME.
SELECTION-SCREEN COMMENT /1(79) g_scr_h0.
PARAMETERS: p_table TYPE tabname OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
SELECTION-SCREEN COMMENT /1(79) g_scr_h1.
SELECT-OPTIONS: s_date FOR sy-datum.
PARAMETERS:     p_test TYPE c AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN: BEGIN OF LINE,
  PUSHBUTTON 1(25)  bt_tbls USER-COMMAND show_tbls,
  PUSHBUTTON 28(25) bt_data USER-COMMAND show_data.
SELECTION-SCREEN END OF LINE.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  DATA: lv_hub_tab TYPE tabname.

  IMPORT arch_tabname = lv_hub_tab FROM MEMORY ID 'Z_GSP18_ARCH_TAB'.
  IF sy-subrc = 0.
    IF p_table IS INITIAL AND lv_hub_tab IS NOT INITIAL.
      p_table = lv_hub_tab.
    ENDIF.
    FREE MEMORY ID 'Z_GSP18_ARCH_TAB'.
  ENDIF.

  g_scr_h0 = 'Table: press F4 to pick from configuration. Turn off Test Mode to write the archive file.'.
  g_scr_h1 = 'Dates/retention use configuration; extra rules may still filter rows.'.
  bt_tbls = 'Show All Tables'.
  bt_data = 'Show Eligible Data'.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN OUTPUT.
*----------------------------------------------------------------------*
  " Hub opens this screen only to create/edit variant: hide Execute (F8) — see FORM arch_submit_wvar_ss (Z_GSP18_SAP15_F01)
  DATA lv_hide_exec TYPE xfeld.
  CLEAR lv_hide_exec.
  IMPORT zsp26_no_ss_exec = lv_hide_exec FROM MEMORY ID 'Z_GSP18_WR_SS'.
  IF sy-subrc = 0 AND lv_hide_exec = 'X'.
    PERFORM insert_into_excl(RSDBRUNT) USING 'ONLI'.
    LOOP AT SCREEN.
      IF screen-name CS 'P_TABLE'.
        screen-input = 0.
        MODIFY SCREEN.
      ENDIF.
    ENDLOOP.
  ENDIF.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_table.
*----------------------------------------------------------------------*
  PERFORM f4_arch_cfg_table CHANGING p_table.

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
            lv_wh_full TYPE string,
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

        CLEAR: lv_cnt2, lv_wh, lv_wh_full.
        PERFORM build_where_from_arch_cfg
          USING ls_cfgraw s_date-low lv_co_pop
          CHANGING lv_wh.
        lv_wh_full = lv_wh.
        PERFORM append_rules_eq_to_where
          USING ls_cfgraw-config_id ls_cfgraw-table_name
          CHANGING lv_wh_full.
        SELECT COUNT(*) FROM (ls_cfgraw-table_name) INTO @lv_cnt2
          WHERE (lv_wh_full).
        ls_cfg-eligible = lv_cnt2.

        APPEND ls_cfg TO lt_cfg.
      ENDLOOP.

      DATA: lo_alv  TYPE REF TO cl_salv_table,
            lo_col  TYPE REF TO cl_salv_column,
            lo_cols TYPE REF TO cl_salv_columns_table.
      TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = lt_cfg ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).

        lo_cols = lo_alv->get_columns( ).
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
        MESSAGE |Table '{ p_table }' is not active in archive configuration or is unknown to the dictionary.| TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.

      DATA: lv_co TYPE d,
            lv_w2 TYPE string,
            lv_w0 TYPE string,
            lv_c0 TYPE i,
            lv_m  TYPE string,
            lv_df TYPE zsp26_arch_cfg-data_field.
      lv_co = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                      ELSE sy-datum - gs_cfg-retention ).
      lv_df = gs_cfg-data_field.

      CREATE DATA gr_src TYPE TABLE OF (p_table).
      ASSIGN gr_src->* TO <lt_src>.
      PERFORM build_where_from_arch_cfg
        USING gs_cfg s_date-low lv_co
        CHANGING lv_w2.
      lv_w0 = lv_w2.
      PERFORM append_rules_eq_to_where USING gs_cfg-config_id p_table CHANGING lv_w2.
      SELECT * FROM (p_table) INTO TABLE <lt_src> UP TO lc_max_rows ROWS WHERE (lv_w2).

      lv_sql_elig_cnt = lines( <lt_src> ).
      PERFORM apply_rules_to_src.

      IF <lt_src> IS INITIAL.
        IF lv_sql_elig_cnt > 0.
          lv_m = |{ lv_sql_elig_cnt } row(s) passed the date window but none passed the extra archive rules. Review rules for this table in configuration.|.
          MESSAGE lv_m TYPE 'S' DISPLAY LIKE 'W'.
        ELSE.
          CLEAR lv_tbl_tot.
          SELECT COUNT(*) FROM (p_table) INTO @lv_tbl_tot.
          IF lv_tbl_tot > 0.
            CLEAR lv_c0.
            SELECT COUNT(*) FROM (p_table) INTO @lv_c0 WHERE (lv_w0).
            IF lv_c0 > 0.
              lv_m = |{ lv_tbl_tot } row(s) exist but none qualify after rules are applied. Widen the date range or review archive rules for this table.|.
            ELSE.
              lv_m = |{ lv_tbl_tot } row(s) exist but none match the configured date field ({ lv_df }) up to { lv_co }. Widen the date range or change the date field in configuration (e.g. posting vs document date).|.
            ENDIF.
            MESSAGE lv_m TYPE 'S' DISPLAY LIKE 'W'.
          ELSE.
            lv_m = |No rows found for { p_table } in this client. If you expected data, check the table, client, and keys in the data browser.|.
            MESSAGE lv_m TYPE 'S' DISPLAY LIKE 'W'.
          ENDIF.
        ENDIF.
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
    MESSAGE |Table '{ p_table }' cannot be archived: missing active configuration or date field not in the dictionary.| TYPE 'A'.
  ENDIF.

  lv_tpl_df = gs_cfg-data_field.
  lv_tpl_cid = gs_cfg-config_id.
  lv_tpl_ret = gs_cfg-retention.

  lv_cutoff = COND #( WHEN s_date-high IS NOT INITIAL THEN s_date-high
                      ELSE sy-datum - gs_cfg-retention ).

  WRITE: /.
  WRITE: / |=== Archive write: { p_table } ===|.
  WRITE: / |Configuration ID: { lv_tpl_cid }|.
  WRITE: / |Date field      : { lv_tpl_df }|.
  WRITE: / |Retention (days): { lv_tpl_ret }|.
  IF s_date-low IS NOT INITIAL.
    WRITE: / |Date From  : { s_date-low }|.
  ELSE.
    WRITE: / 'Date From  : (no lower bound)'.
  ENDIF.
  WRITE: / |Date To    : { lv_cutoff }|.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no archive I/O ***'. ENDIF.
  WRITE: /.

  DATA: lv_where    TYPE string,
        lv_where0   TYPE string,
        lv_c0       TYPE i,
        ls_dd_wa    TYPE dfies,
        ls_arch_rec TYPE zstr_arch_rec,
        lv_keyvals  TYPE char255,
        lv_json     TYPE string,
        lv_jlen     TYPE i,
        lv_jpos     TYPE i,
        lv_take     TYPE i,
        lv_val2     TYPE string,
        lv_fn2      TYPE fieldname,
        lv_kfn      TYPE string.
  PERFORM build_where_from_arch_cfg
    USING gs_cfg s_date-low lv_cutoff
    CHANGING lv_where0.
  lv_where = lv_where0.
  PERFORM append_rules_eq_to_where USING gs_cfg-config_id p_table CHANGING lv_where.

  " Runtime memory for target rows: CREATE DATA creates heap data; ASSIGN binds field-symbol
  CREATE DATA gr_src TYPE TABLE OF (p_table).
  ASSIGN gr_src->* TO <lt_src>.
  SELECT * FROM (p_table) INTO TABLE <lt_src> UP TO lc_max_rows ROWS WHERE (lv_where).

  lv_sql_elig_cnt = lines( <lt_src> ).
  IF lv_sql_elig_cnt >= lc_max_rows.
    WRITE: / |Warning: only the first { lc_max_rows } rows were read; more rows may exist.|.
  ENDIF.
  PERFORM apply_rules_to_src.

  WRITE: / |Records eligible: { lines( <lt_src> ) }|.

  IF <lt_src> IS INITIAL.
    IF lv_sql_elig_cnt > 0.
      WRITE: / |{ lv_sql_elig_cnt } row(s) matched the date window but none passed row-level archive rules.|.
    ELSE.
      CLEAR lv_tbl_tot.
      SELECT COUNT(*) FROM (p_table) INTO @lv_tbl_tot.
      IF lv_tbl_tot > 0.
        CLEAR lv_c0.
        SELECT COUNT(*) FROM (p_table) INTO @lv_c0 WHERE (lv_where0).
        IF lv_c0 > 0.
          WRITE: / |{ lv_tbl_tot } row(s) exist; { lv_c0 } in the date window but none after rules — review archive rules.|.
        ELSE.
          WRITE: / |{ lv_tbl_tot } row(s) exist but none match date field { lv_tpl_df } up to { lv_cutoff } — widen dates or change date field.|.
        ENDIF.
      ELSE.
        WRITE: / |No rows for cutoff { lv_cutoff } on field { lv_tpl_df }; table may be empty in this client.|.
      ENDIF.
    ENDIF.
    WRITE: / 'No rows qualify for archiving.'.
    RETURN.
  ENDIF.

  " Build generic archive payload rows (ZSTR_ARCH_REC)
  CREATE DATA gr_arch TYPE TABLE OF zstr_arch_rec.
  ASSIGN gr_arch->* TO <lt_arch>.
  REFRESH <lt_arch>.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING
      tabname   = p_table
    TABLES
      dfies_tab = lt_dd
    EXCEPTIONS
      OTHERS    = 1.
  IF sy-subrc <> 0 OR lt_dd IS INITIAL.
    MESSAGE |Could not read field list for table { p_table }; archiving cannot continue.| TYPE 'A'.
  ENDIF.

  LOOP AT <lt_src> ASSIGNING <row>.
    CLEAR: lv_keyvals, lv_json.

    LOOP AT lt_dd INTO ls_dd_wa WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
      ASSIGN COMPONENT ls_dd_wa-fieldname OF STRUCTURE <row> TO FIELD-SYMBOL(<fkv2>).
      IF <fkv2> IS ASSIGNED.
        MOVE <fkv2> TO lv_val2.
        lv_fn2 = ls_dd_wa-fieldname.
        CONDENSE lv_fn2.
        TRANSLATE lv_fn2 TO UPPER CASE.
        CLEAR lv_kfn.
        lv_kfn = lv_fn2.
        PERFORM zsp26_arch_norm_keyfname CHANGING lv_kfn.
        lv_fn2 = lv_kfn.
        IF lv_keyvals IS NOT INITIAL.
          lv_keyvals = lv_keyvals && '|' && lv_fn2 && '=' && lv_val2.
        ELSE.
          lv_keyvals = lv_fn2 && '=' && lv_val2.
        ENDIF.
      ENDIF.
    ENDLOOP.

    TRY.
        lv_json = /ui2/cl_json=>serialize( data = <row> ).
      CATCH cx_root.
        lv_json = ''.
    ENDTRY.

    " Chunk JSON: REC_TYPE D = first part, 2 = continuation (255 chars = domain LENG/OUTPUTLEN, no DDIC warnings).
    lv_jlen = strlen( lv_json ).
    IF lv_jlen = 0.
      CLEAR ls_arch_rec.
      ls_arch_rec-rec_type   = 'D'.
      ls_arch_rec-table_name = p_table.
      ls_arch_rec-key_vals   = lv_keyvals.
      ls_arch_rec-exec_user  = sy-uname.
      GET TIME STAMP FIELD ls_arch_rec-exec_ts.
      INSERT ls_arch_rec INTO TABLE <lt_arch>.
    ELSE.
      CLEAR lv_jpos.
      WHILE lv_jpos < lv_jlen.
        CLEAR ls_arch_rec.
        ls_arch_rec-table_name = p_table.
        ls_arch_rec-key_vals   = lv_keyvals.
        ls_arch_rec-rec_type   = COND #( WHEN lv_jpos = 0 THEN 'D' ELSE '2' ).
        lv_take = 255.
        IF lv_jpos + lv_take > lv_jlen.
          lv_take = lv_jlen - lv_jpos.
        ENDIF.
        ls_arch_rec-data_json = lv_json+lv_jpos(lv_take).
        ls_arch_rec-exec_user  = sy-uname.
        GET TIME STAMP FIELD ls_arch_rec-exec_ts.
        INSERT ls_arch_rec INTO TABLE <lt_arch>.
        lv_jpos = lv_jpos + lv_take.
      ENDWHILE.
    ENDIF.
  ENDLOOP.

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
      MESSAGE 'Could not open archive for writing. Check archive object setup and your authorizations.' TYPE 'A'.
    ENDIF.

    " Register generic DDIC record structure
    DATA: lt_reg TYPE TABLE OF arch_ddic,
          ls_reg TYPE arch_ddic.
    CLEAR ls_reg.
    ls_reg-name = 'ZSTR_ARCH_REC'.
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
      lv_err = lv_err + 1.
      WRITE: / |Error: archive structure registration failed (return code { sy-subrc }).|.
      CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
        EXPORTING archive_handle = lv_arch_h EXCEPTIONS OTHERS = 1.
      MESSAGE 'Archive structure registration failed; run cannot continue.' TYPE 'A'.
    ENDIF.

    CALL FUNCTION 'ARCHIVE_NEW_OBJECT'
      EXPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        internal_error            = 1
        wrong_access_to_archive   = 2
        OTHERS                    = 3.
    IF sy-subrc <> 0.
      CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
        EXPORTING archive_handle = lv_arch_h EXCEPTIONS OTHERS = 1.
      MESSAGE 'Could not create a new archive object in the file.' TYPE 'A'.
    ENDIF.

    CALL FUNCTION 'ARCHIVE_PUT_TABLE'
      EXPORTING
        archive_handle   = lv_arch_h
        record_structure = 'ZSTR_ARCH_REC'
      TABLES
        table            = <lt_arch>
      EXCEPTIONS
        internal_error            = 1
        wrong_access_to_archive   = 2
        invalid_record_structure  = 3
        OTHERS                    = 4.
    IF sy-subrc <> 0.
      lv_err = lv_err + 1.
      WRITE: / |Error: writing data to the archive file failed (return code { sy-subrc }).|.
      CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
        EXPORTING
          archive_handle = lv_arch_h
        EXCEPTIONS
          OTHERS         = 1.
      MESSAGE 'Writing rows to the archive file failed.' TYPE 'A'.
    ENDIF.

    lv_cnt = lines( <lt_arch> ).

    " On this system, ARCHIVE_CLOSE_OBJECT is unavailable.
    " Persist object explicitly, then close archive file.
    CALL FUNCTION 'ARCHIVE_SAVE_OBJECT'
      EXPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        internal_error          = 1
        wrong_access_to_archive = 2
        OTHERS                  = 3.
    IF sy-subrc <> 0.
      lv_err = lv_err + 1.
      CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
        EXPORTING
          archive_handle = lv_arch_h
        EXCEPTIONS
          OTHERS         = 1.
      MESSAGE 'Saving the archive object failed.' TYPE 'A'.
    ENDIF.

    CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
      EXPORTING
        archive_handle = lv_arch_h
      EXCEPTIONS
        OTHERS         = 1.

    GET TIME STAMP FIELD lv_ts_e.

    DATA: ls_log TYPE zsp26_arch_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error.
      ls_log-log_id = CONV sysuuid_x16( |{ sy-datum }{ sy-uzeit }{ sy-tabix }| ).
    ENDTRY.
    ls_log-config_id   = gs_cfg-config_id.
    ls_log-table_name  = p_table.
    ls_log-action      = 'ARCHIVE'.
    ls_log-rec_count   = lv_cnt.
    ls_log-status      = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-start_time  = lv_ts_s.
    ls_log-end_time    = lv_ts_e.
    ls_log-exec_user   = sy-uname.
    ls_log-exec_date   = sy-datum.
    ls_log-message     = |Archived { lv_cnt } row(s) for { p_table } (cutoff { lv_cutoff }, session handle { lv_arch_h }).|.
    INSERT zsp26_arch_log FROM ls_log.
    IF sy-subrc <> 0.
      WRITE: / |Warning: archive completed but application log could not be saved (return code { sy-subrc }).|.
    ENDIF.
    COMMIT WORK.
  ENDIF.

  WRITE: /.
  WRITE: / '=== Summary ==='.
  WRITE: / |Rows in selection: { lines( <lt_src> ) }|.
  IF p_test = ' '.
    WRITE: / |Rows written to archive file: { lv_cnt }|.
    WRITE: / 'Write step finished: data is in the archive file; database rows are not removed yet.'.
    WRITE: / 'Next step: run the Delete program from the hub to remove the same rows from the database.'.
    WRITE: / 'Use the hub Delete flow and pick the archive session that matches this run.'.
  ELSE.
    WRITE: / 'Test mode: turn off Test Mode to perform a real archive write to disk.'.
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
    PERFORM apply_archive_rules USING <lr> gs_cfg-config_id gs_cfg-table_name CHANGING lv_rp.
    IF lv_rp = abap_false.
      DELETE <lt_src> INDEX lv_ix.
    ENDIF.
    lv_ix = lv_ix - 1.
  ENDWHILE.
ENDFORM.
