*&---------------------------------------------------------------------*
*& Include  Z_GSP18_ARCH_DYN
*& Shared helpers: validate table vs ZSP26_ARCH_CFG, dynamic WHERE,
*& apply_archive_rules, F4 for P_TABLE (ZSP26_ARCH_CFG)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Clear app IS_ACTIVE for table when DDIC is gone / unreadable (no delete)
*& Used when iv_clear_if_ddic_bad = true on validate failure
*&---------------------------------------------------------------------*
FORM deact_active_cfg_for_table
  USING    VALUE(pv_table) TYPE tabname
  CHANGING cv_rows_updated TYPE abap_bool.

  DATA: lv_tn       TYPE tabname,
        lv_inactive TYPE zsp26_de_xflag.

  CLEAR cv_rows_updated.
  CLEAR lv_inactive.
  lv_tn = pv_table.
  CONDENSE lv_tn.
  TRANSLATE lv_tn TO UPPER CASE.
  IF lv_tn IS INITIAL.
    RETURN.
  ENDIF.

  UPDATE zsp26_arch_cfg
    SET is_active  = @lv_inactive,
        changed_by = @sy-uname,
        changed_on = @sy-datum
    WHERE table_name = @lv_tn
      AND is_active  = 'X'.
  IF sy-subrc = 0 AND sy-dbcnt > 0.
    cv_rows_updated = abap_true.
    COMMIT WORK.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Validate archive target table against ZSP26_ARCH_CFG + DDIC
*& 1 Row exists, IS_ACTIVE, DATA_FIELD non-initial, retention > 0
*& 2 Table exists in active DDIC (DD02V) — catches deleted / not in catalog
*& 3 DDIF field list readable (may be stale after failed activation)
*& 3b DDIF_NAMETAB_GET (active runtime) — catches "nametab cannot be generated" while DFIES from DDIF_FIELDINFO_GET may be stale
*& 4 DATA_FIELD is a DATE column in current DDIC
*& Fails: cv_ok = false and cv_reason_text = user-facing explanation
*& If iv_clear_if_ddic_bad: on missing/unreadable DDIC, clear
*& IS_ACTIVE on ZSP26_ARCH_CFG for that table (no row delete) + COMMIT
*&---------------------------------------------------------------------*
FORM validate_table_against_cfg
  USING    VALUE(pv_table) TYPE tabname
           VALUE(iv_clear_if_ddic_bad) TYPE abap_bool
  CHANGING ps_cfg            TYPE zsp26_arch_cfg
           cv_ok             TYPE abap_bool
           cv_reason_text    TYPE string.

  DATA: lt_df          TYPE TABLE OF dfies,
        ls_df          TYPE dfies,
        lt_cfg_pick    TYPE STANDARD TABLE OF zsp26_arch_cfg WITH EMPTY KEY,
        lv_tn          TYPE tabname,
        lv_df          TYPE fieldname,
        lv_dd_tab      TYPE tabname,
        lv_synced      TYPE abap_bool,
        lt_x031l       TYPE TABLE OF x031l.

  CLEAR: ps_cfg, cv_ok, cv_reason_text.
  cv_ok = abap_false.

  lv_tn = pv_table.
  CONDENSE lv_tn.
  TRANSLATE lv_tn TO UPPER CASE.
  IF lv_tn IS INITIAL.
    cv_reason_text = |Enter a table name.| ##NO_TEXT.
    RETURN.
  ENDIF.

  SELECT * FROM zsp26_arch_cfg
    INTO TABLE @lt_cfg_pick
    WHERE table_name = @lv_tn AND is_active = 'X'.
  IF lt_cfg_pick IS INITIAL.
    cv_reason_text = |Table { lv_tn } has no active archive configuration (ZSP26_ARCH_CFG with IS_ACTIVE = X). Use F4 or [Manage] to register.| ##NO_TEXT.
    RETURN.
  ENDIF.
  SORT lt_cfg_pick BY changed_on DESCENDING created_on DESCENDING config_id.
  READ TABLE lt_cfg_pick INTO ps_cfg INDEX 1.
  IF sy-subrc <> 0.
    cv_reason_text = |Table { lv_tn }: could not read archive configuration.| ##NO_TEXT.
    RETURN.
  ENDIF.
  IF ps_cfg-data_field IS INITIAL.
    cv_reason_text = |Table { lv_tn }: configuration has no date field (DATA_FIELD is empty in ZSP26_ARCH_CFG). Fix the config before using this table.| ##NO_TEXT.
    RETURN.
  ENDIF.
  IF ps_cfg-retention <= 0.
    cv_reason_text = |Table { lv_tn }: retention (days) in ZSP26_ARCH_CFG must be greater than zero.| ##NO_TEXT.
    RETURN.
  ENDIF.

  lv_df = ps_cfg-data_field.
  CONDENSE lv_df NO-GAPS.
  TRANSLATE lv_df TO UPPER CASE.
  ps_cfg-data_field = lv_df.

  CLEAR lv_dd_tab.
  SELECT SINGLE tabname FROM dd02v ##WARN_OK
    INTO @lv_dd_tab
    WHERE tabname = @lv_tn.
  IF sy-subrc <> 0.
    CLEAR lv_synced.
    IF iv_clear_if_ddic_bad = abap_true.
      PERFORM deact_active_cfg_for_table USING lv_tn CHANGING lv_synced.
    ENDIF.
    cv_reason_text = |Table { lv_tn } is not in the active DDIC catalog (deleted, or inactive / not activated in SE11).| ##NO_TEXT.
    IF lv_synced = abap_true.
      cv_reason_text &&= | IS_ACTIVE was cleared on ZSP26_ARCH_CFG for this table so it no longer shows as active; fix or activate the table in SE11, then set active again in [Manage].| ##NO_TEXT.
    ELSE.
      cv_reason_text &&= | Update or deactivate the archive configuration row.| ##NO_TEXT.
    ENDIF.
    RETURN.
  ENDIF.

  " Detect pending/failed SE11 activation:
  " SAP keeps a non-'A' entry in DD02L while an object has unactivated changes.
  " The value is 'M' (Modified) on some systems and 'N' (New) on others.
  " Checking for any entry with as4local <> 'A' is the definitive signal.
  " On successful activation only the 'A' entry remains.
  SELECT SINGLE tabname FROM dd02l BYPASSING BUFFER INTO @DATA(lv_dd02l_inact) ##WARN_OK
    WHERE tabname = @lv_tn AND as4local <> 'A'.
  IF sy-subrc = 0.
    CLEAR lv_synced.
    IF iv_clear_if_ddic_bad = abap_true.
      PERFORM deact_active_cfg_for_table USING lv_tn CHANGING lv_synced.
    ENDIF.
    cv_reason_text = |Table { lv_tn } has SE11 changes not yet activated (or activation failed). Fix errors and activate in SE11.| ##NO_TEXT.
    IF lv_synced = abap_true.
      cv_reason_text &&= | IS_ACTIVE was cleared on ZSP26_ARCH_CFG.| ##NO_TEXT.
    ENDIF.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = lv_tn
    TABLES     dfies_tab = lt_df
    EXCEPTIONS OTHERS    = 7.
  IF sy-subrc <> 0 OR lt_df IS INITIAL.
    CLEAR lv_synced.
    IF iv_clear_if_ddic_bad = abap_true.
      PERFORM deact_active_cfg_for_table USING lv_tn CHANGING lv_synced.
    ENDIF.
    cv_reason_text = |Table { lv_tn }: DDIC field list could not be read (dictionary inactive or error). Check SE11 activation.| ##NO_TEXT.
    IF lv_synced = abap_true.
      cv_reason_text &&= | IS_ACTIVE was cleared on ZSP26_ARCH_CFG for this table.| ##NO_TEXT.
    ENDIF.
    RETURN.
  ENDIF.

  " DDIF_NAMETAB_GET: detects missing nametab (never activated).
  " After a FAILED SE11 re-activation the OLD nametab may still be valid,
  " so DDIF_NAMETAB_GET alone is not enough. Do a cheap dynamic SELECT
  " (UP TO 0 ROWS) as the definitive runtime check — CX_SY_DYNAMIC_OSQL_ERROR
  " fires when the Open SQL runtime rejects the table (broken nametab).
  CLEAR lt_x031l.
  CALL FUNCTION 'DDIF_NAMETAB_GET'
    EXPORTING
      tabname = lv_tn
      status  = 'A'
    TABLES
      x031l_tab = lt_x031l
    EXCEPTIONS
      not_found = 1
      OTHERS      = 2.
  IF sy-subrc <> 0 OR lt_x031l IS INITIAL.
    CLEAR lv_synced.
    IF iv_clear_if_ddic_bad = abap_true.
      PERFORM deact_active_cfg_for_table USING lv_tn CHANGING lv_synced.
    ENDIF.
    cv_reason_text = |Table { lv_tn } has no active runtime nametab (DDIC activation incomplete or failed). Fix SE11 errors, then activate.| ##NO_TEXT.
    IF lv_synced = abap_true.
      cv_reason_text &&= | IS_ACTIVE was cleared on ZSP26_ARCH_CFG for this table.| ##NO_TEXT.
    ENDIF.
    RETURN.
  ENDIF.

  " Runtime probe: SELECT UP TO 0 ROWS triggers CX_SY_DYNAMIC_OSQL_ERROR
  " when the nametab exists but is stale after a failed SE11 activation.
  TRY.
    SELECT COUNT(*) FROM (lv_tn) INTO @DATA(lv_probe) ##NO_TEXT ##WARN_OK.
  CATCH cx_sy_dynamic_osql_error cx_sy_open_sql_db.
    CLEAR lv_synced.
    IF iv_clear_if_ddic_bad = abap_true.
      PERFORM deact_active_cfg_for_table USING lv_tn CHANGING lv_synced.
    ENDIF.
    cv_reason_text = |Table { lv_tn } is not accessible at runtime (stale nametab after failed SE11 activation). Fix SE11 errors, activate, then re-enable in [Manage].| ##NO_TEXT.
    IF lv_synced = abap_true.
      cv_reason_text &&= | IS_ACTIVE was cleared on ZSP26_ARCH_CFG.| ##NO_TEXT.
    ENDIF.
    RETURN.
  ENDTRY.

  READ TABLE lt_df INTO ls_df WITH KEY fieldname = ps_cfg-data_field.
  IF sy-subrc <> 0.
    cv_reason_text = |Date field { ps_cfg-data_field } is not a column of { lv_tn } in active DDIC (structure may have changed).| ##NO_TEXT.
    RETURN.
  ENDIF.
  IF ls_df-inttype <> 'D'.
    cv_reason_text = |Field { ps_cfg-data_field } on { lv_tn } is not DATE type (DDIC inttype { ls_df-inttype }). Update DATA_FIELD in ZSP26_ARCH_CFG.| ##NO_TEXT.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
  CLEAR cv_reason_text.
ENDFORM.

*&---------------------------------------------------------------------*
*& Sync ZSP26_ARCH_CFG.IS_ACTIVE vs active DDIC (SE11 deactivate/delete)
*& For every row still marked active in DB: re-run validate with clear.
*& Call from hub PBO, monitor/config entry, F4, ADK selection-screen init.
*&---------------------------------------------------------------------*
FORM zsp26_sync_cfg_active_vs_ddic.

  DATA: lt_tn    TYPE STANDARD TABLE OF tabname WITH DEFAULT KEY,
        lv_tn    TYPE tabname,
        ls_dummy TYPE zsp26_arch_cfg,
        lv_ok    TYPE abap_bool,
        lv_rs    TYPE string.

  " Phase 1: check every active row — clear IS_ACTIVE if DDIC is broken.
  SELECT DISTINCT table_name FROM zsp26_arch_cfg
    INTO TABLE @lt_tn
    WHERE is_active = 'X'.

  LOOP AT lt_tn INTO lv_tn.
    PERFORM validate_table_against_cfg
      USING lv_tn abap_true
      CHANGING ls_dummy lv_ok lv_rs.
  ENDLOOP.

  " Phase 2: auto-restore IS_ACTIVE for tables whose flag was cleared by a
  " previous sync run. Pass lt_tn so Phase 2 skips tables Phase 1 just
  " evaluated — prevents immediate re-restore within the same sync call.
  PERFORM zsp26_restore_cfg_if_ddic_ok USING lt_tn.
ENDFORM.

*&---------------------------------------------------------------------*
*& Restore IS_ACTIVE='X' for the best cleared config row whose table
*& is now fully active in DDIC (dd02v + runtime SELECT pass).
*& it_p1_checked: tables Phase 1 just checked — skip these to avoid
*& restoring what Phase 1 cleared in the same sync run.
*&---------------------------------------------------------------------*
FORM zsp26_restore_cfg_if_ddic_ok
  USING it_p1_checked TYPE STANDARD TABLE.

  DATA: lt_inact  TYPE STANDARD TABLE OF tabname WITH DEFAULT KEY,
        lv_it     TYPE tabname,
        ls_best   TYPE zsp26_arch_cfg,
        lt_fld_r  TYPE TABLE OF dfies,
        ls_fld_r  TYPE dfies.

  " Candidate tables: have a cleared config with valid data_field + retention,
  " but no currently active row.
  SELECT DISTINCT table_name FROM zsp26_arch_cfg
    INTO TABLE @lt_inact
    WHERE is_active  = ''
      AND data_field <> ''
      AND retention  > 0.
  CHECK lt_inact IS NOT INITIAL.

  LOOP AT lt_inact INTO lv_it.

    " Skip if Phase 1 already evaluated this table in the current sync run
    " (prevents restoring what Phase 1 just cleared).
    READ TABLE it_p1_checked WITH KEY table_line = lv_it TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. CONTINUE. ENDIF.

    " Skip if an active row already exists (manually re-registered etc.)
    SELECT COUNT(*) FROM zsp26_arch_cfg INTO @DATA(lv_act)
      WHERE table_name = @lv_it AND is_active = 'X'.
    IF lv_act > 0. CONTINUE. ENDIF.

    " DDIC check 1: active catalog entry
    SELECT SINGLE tabname FROM dd02v ##WARN_OK INTO @DATA(lv_d2v) WHERE tabname = @lv_it.
    IF sy-subrc <> 0. CONTINUE. ENDIF.

    " DDIC check 2: skip if table has any pending/failed SE11 activation (non-'A' in DD02L)
    SELECT SINGLE tabname FROM dd02l BYPASSING BUFFER INTO @DATA(lv_dd02l_inact_r) ##WARN_OK
      WHERE tabname = @lv_it AND as4local <> 'A'.
    IF sy-subrc = 0. CONTINUE. ENDIF.

    " DDIC check 3: runtime SELECT probe — definitive check that nametab is usable
    TRY.
      SELECT COUNT(*) FROM (lv_it) INTO @DATA(lv_pr) ##WARN_OK.
    CATCH cx_sy_dynamic_osql_error cx_sy_open_sql_db.
      CONTINUE.
    ENDTRY.

    " Pick best cleared config row (most recently changed with valid fields)
    SELECT * FROM zsp26_arch_cfg INTO @ls_best
      UP TO 1 ROWS
      WHERE table_name = @lv_it
        AND is_active  = ''
        AND data_field <> ''
        AND retention  > 0
      ORDER BY changed_on DESCENDING.
    ENDSELECT.
    IF sy-subrc <> 0. CONTINUE. ENDIF.

    " Verify data_field is still a DATE column in current DDIC
    CLEAR lt_fld_r.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING tabname   = lv_it
      TABLES    dfies_tab = lt_fld_r
      EXCEPTIONS OTHERS   = 1.
    IF sy-subrc <> 0 OR lt_fld_r IS INITIAL. CONTINUE. ENDIF.
    READ TABLE lt_fld_r INTO ls_fld_r WITH KEY fieldname = ls_best-data_field.
    IF sy-subrc <> 0 OR ls_fld_r-inttype <> 'D'. CONTINUE. ENDIF.

    " All checks pass — restore IS_ACTIVE for this config row.
    UPDATE zsp26_arch_cfg
      SET is_active  = 'X',
          changed_by = @sy-uname,
          changed_on = @sy-datum
      WHERE config_id = @ls_best-config_id.
    IF sy-subrc = 0. COMMIT WORK. ENDIF.

  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Build Open SQL WHERE from ZSP26_ARCH_CFG (retention / date window)
*& Date field = DATA_FIELD; upper bound = P_DHIGH or sy-datum - RETENTION
*&---------------------------------------------------------------------*
FORM build_where_from_arch_cfg
  USING    ps_cfg   TYPE zsp26_arch_cfg
           pv_dlow  TYPE d
           pv_dhigh TYPE d
  CHANGING cv_where TYPE string.

  DATA: lv_hi   TYPE d,
        lv_df_u TYPE string,
        lt_df   TYPE TABLE OF dfies,
        lv_ae   TYPE abap_bool,
        lv_be   TYPE abap_bool,
        lv_tab  TYPE tabname.

  IF pv_dhigh IS NOT INITIAL.
    lv_hi = pv_dhigh.
  ELSE.
    lv_hi = sy-datum - ps_cfg-retention.
  ENDIF.

  lv_df_u = ps_cfg-data_field.
  CONDENSE lv_df_u.
  TRANSLATE lv_df_u TO UPPER CASE.

  CLEAR: lv_ae, lv_be.
  IF lv_df_u = 'AEDAT'.
    lv_tab = ps_cfg-table_name.
    CONDENSE lv_tab.
    TRANSLATE lv_tab TO UPPER CASE.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING  tabname   = lv_tab
      TABLES     dfies_tab = lt_df
      EXCEPTIONS OTHERS    = 7.
    IF sy-subrc = 0.
      READ TABLE lt_df WITH KEY fieldname = 'AEDAT' TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_ae = abap_true.
      ENDIF.
      READ TABLE lt_df WITH KEY fieldname = 'BEDAT' TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_be = abap_true.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_ae = abap_true AND lv_be = abap_true.
    " EKKO-style: use BEDAT when AEDAT is DDIC initial. Dynamic WHERE (string) must not use IS INITIAL — parse error CX_SY_DYNAMIC_OSQL_SEMANTICS.
    " Literal '00000000': works in dynamic OSQL; SQL NULL on AEDAT still needs CFG DATA_FIELD=BEDAT or row-level filter.
    IF pv_dlow IS NOT INITIAL.
      cv_where = |( ( AEDAT NE '00000000' AND AEDAT GE '{ pv_dlow }' AND AEDAT LE '{ lv_hi }' ) OR | &&
                   |( AEDAT EQ '00000000' AND BEDAT NE '00000000' AND BEDAT GE '{ pv_dlow }' AND BEDAT LE '{ lv_hi }' ) )|.
    ELSE.
      cv_where = |( ( AEDAT NE '00000000' AND AEDAT LE '{ lv_hi }' ) OR | &&
                   |( AEDAT EQ '00000000' AND BEDAT NE '00000000' AND BEDAT LE '{ lv_hi }' ) )|.
    ENDIF.
  ELSE.
    IF pv_dlow IS NOT INITIAL.
      cv_where = |{ ps_cfg-data_field } NE '00000000' AND { ps_cfg-data_field } GE '{ pv_dlow }' AND { ps_cfg-data_field } LE '{ lv_hi }'|.
    ELSE.
      cv_where = |{ ps_cfg-data_field } NE '00000000' AND { ps_cfg-data_field } LE '{ lv_hi }'|.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Optional: append simple EQ predicates from ZSP26_ARCH_RULE (AND only)
*& FIELD_NAME must match a column in pv_table (DDIF); identifier taken from DFIES, not raw config
*& Skips rows with AND_OR = OR (leave those to apply_archive_rules)
*&---------------------------------------------------------------------*
FORM append_rules_eq_to_where
  USING    VALUE(pv_config_id) TYPE zsp26_arch_cfg-config_id
           VALUE(pv_table)     TYPE tabname
  CHANGING cv_where TYPE string.

  DATA: lt_r   TYPE TABLE OF zsp26_arch_rule,
        ls_r   TYPE zsp26_arch_rule,
        ls_or  TYPE zsp26_arch_rule,
        lt_df  TYPE TABLE OF dfies,
        ls_df  TYPE dfies,
        lv_esc TYPE string,
        lv_fn  TYPE fieldname.

  SELECT * FROM zsp26_arch_rule INTO TABLE @lt_r
    WHERE config_id = @pv_config_id AND is_active = 'X'
    ORDER BY rule_seq.
  IF lt_r IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = pv_table
    TABLES     dfies_tab = lt_df
    EXCEPTIONS OTHERS    = 7.
  IF sy-subrc <> 0 OR lt_df IS INITIAL.
    RETURN.
  ENDIF.

  " Only EQ predicates are appended below. OR on non-EQ rows must not block merging EQ into SQL.
  " If an EQ row uses OR to the next rule, AND-chaining EQ into Open SQL is unsafe — skip all EQ SQL.
  LOOP AT lt_r INTO ls_or WHERE operator = 'EQ'.
    IF ls_or-and_or CS 'OR'.
      RETURN.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_r INTO ls_r WHERE operator = 'EQ'.
    lv_fn = ls_r-field_name.
    CONDENSE lv_fn.
    TRANSLATE lv_fn TO UPPER CASE.
    IF strlen( lv_fn ) = 0 OR strlen( lv_fn ) > 30.
      CONTINUE.
    ENDIF.
    IF NOT lv_fn CO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789'.
      CONTINUE.
    ENDIF.

    READ TABLE lt_df INTO ls_df WITH KEY fieldname = lv_fn.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    lv_esc = ls_r-value_low.
    REPLACE ALL OCCURRENCES OF `'` IN lv_esc WITH `''`.
    cv_where &&= | AND { ls_df-fieldname } EQ '{ lv_esc }'|.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& FORM apply_archive_rules — row-level rule eval (ZSP26_ARCH_RULE)
*& AND_OR on rule N = how rule N links to rule N+1 (eval at rule N+1).
*& iv_tab: DDIC table → DATE fields (INTTYPE D) compared as type D (stable after JSON restore).
*& Shared: main UI (F01) + Z_ARCH_EKK_WRITE
*&---------------------------------------------------------------------*
FORM apply_archive_rules
  USING    iv_row    TYPE any
           iv_cfg_id TYPE zsp26_arch_cfg-config_id
           iv_tab    TYPE tabname
  CHANGING cv_pass   TYPE abap_bool.

  DATA: lt_rules     TYPE TABLE OF zsp26_arch_rule,
        ls_rule      TYPE zsp26_arch_rule,
        ls_prev_rule TYPE zsp26_arch_rule,
        lv_result    TYPE abap_bool,
        lv_match     TYPE abap_bool,
        lv_fv_s      TYPE string,
        lv_first     TYPE abap_bool,
        lt_df        TYPE TABLE OF dfies,
        ls_df2       TYPE dfies,
        lv_fn        TYPE fieldname,
        lv_row_d     TYPE d,
        lv_lo        TYPE d,
        lv_hi        TYPE d,
        lv_use_d     TYPE abap_bool.

  cv_pass  = abap_true.
  lv_first = abap_true.

  IF iv_tab IS NOT INITIAL.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING  tabname   = iv_tab
      TABLES     dfies_tab = lt_df
      EXCEPTIONS OTHERS    = 0.
  ENDIF.

  SELECT * FROM zsp26_arch_rule INTO TABLE @lt_rules
    WHERE config_id = @iv_cfg_id
      AND is_active = 'X'
    ORDER BY rule_seq.

  IF lt_rules IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR ls_prev_rule.

  LOOP AT lt_rules INTO ls_rule.
    lv_fn = ls_rule-field_name.
    CONDENSE lv_fn.
    TRANSLATE lv_fn TO UPPER CASE.

    CLEAR: lv_use_d, lv_match.
    READ TABLE lt_df INTO ls_df2 WITH KEY fieldname = lv_fn.
    IF sy-subrc = 0 AND ls_df2-inttype = 'D'.
      lv_use_d = abap_true.
    ENDIF.

    IF lv_use_d = abap_true.
      ASSIGN COMPONENT ls_df2-fieldname OF STRUCTURE iv_row TO FIELD-SYMBOL(<anyd>).
      IF sy-subrc <> 0 OR <anyd> IS NOT ASSIGNED.
        lv_match = abap_false.
      ELSE.
        lv_row_d = <anyd>.
        lv_lo    = ls_rule-value_low.
        lv_hi    = ls_rule-value_high.
        CASE ls_rule-operator.
          WHEN 'EQ'.
            lv_match = COND #( WHEN lv_row_d = lv_lo THEN abap_true ELSE abap_false ).
          WHEN 'NE'.
            lv_match = COND #( WHEN lv_row_d <> lv_lo THEN abap_true ELSE abap_false ).
          WHEN 'GT'.
            lv_match = COND #( WHEN lv_row_d > lv_lo THEN abap_true ELSE abap_false ).
          WHEN 'LT'.
            lv_match = COND #( WHEN lv_row_d < lv_lo THEN abap_true ELSE abap_false ).
          WHEN 'GE'.
            lv_match = COND #( WHEN lv_row_d >= lv_lo THEN abap_true ELSE abap_false ).
          WHEN 'LE'.
            lv_match = COND #( WHEN lv_row_d <= lv_lo THEN abap_true ELSE abap_false ).
          WHEN 'BT'.
            lv_match = COND #( WHEN lv_row_d >= lv_lo AND lv_row_d <= lv_hi
                               THEN abap_true ELSE abap_false ).
          WHEN OTHERS.
            lv_match = abap_false.
        ENDCASE.
      ENDIF.
    ELSE.
      ASSIGN COMPONENT lv_fn OF STRUCTURE iv_row TO FIELD-SYMBOL(<fv>).
      IF sy-subrc <> 0.
        ASSIGN COMPONENT ls_rule-field_name OF STRUCTURE iv_row TO <fv>.
      ENDIF.

      IF <fv> IS NOT ASSIGNED.
        lv_match = abap_false.
      ELSE.
        lv_fv_s = CONV string( <fv> ).
        CASE ls_rule-operator.
          WHEN 'EQ'.
            lv_match = COND #( WHEN lv_fv_s =  ls_rule-value_low THEN abap_true ELSE abap_false ).
          WHEN 'NE'.
            lv_match = COND #( WHEN lv_fv_s <> ls_rule-value_low THEN abap_true ELSE abap_false ).
          WHEN 'GT'.
            lv_match = COND #( WHEN lv_fv_s >  ls_rule-value_low THEN abap_true ELSE abap_false ).
          WHEN 'LT'.
            lv_match = COND #( WHEN lv_fv_s <  ls_rule-value_low THEN abap_true ELSE abap_false ).
          WHEN 'GE'.
            lv_match = COND #( WHEN lv_fv_s >= ls_rule-value_low THEN abap_true ELSE abap_false ).
          WHEN 'LE'.
            lv_match = COND #( WHEN lv_fv_s <= ls_rule-value_low THEN abap_true ELSE abap_false ).
          WHEN 'BT'.
            lv_match = COND #( WHEN lv_fv_s >= ls_rule-value_low
                                AND lv_fv_s <= ls_rule-value_high
                               THEN abap_true ELSE abap_false ).
          WHEN OTHERS.
            lv_match = abap_false.
        ENDCASE.
      ENDIF.
    ENDIF.

    IF lv_first = abap_true.
      lv_result = lv_match.
      lv_first  = abap_false.
    ELSE.
      IF ls_prev_rule-and_or = 'OR'.
        IF lv_match = abap_true. lv_result = abap_true. ENDIF.
      ELSE.
        IF lv_match = abap_false. lv_result = abap_false. ENDIF.
      ENDIF.
    ENDIF.

    ls_prev_rule = ls_rule.
  ENDLOOP.

  cv_pass = lv_result.
ENDFORM.

*&---------------------------------------------------------------------*
*& KEY_VALS segment sometimes stores glued "AND" + DDIC name (ANDMJAHR).
*& String + lv(3) compare can fail on some stacks — use c(3) from +0(3).
*&---------------------------------------------------------------------*
FORM zsp26_arch_norm_keyfname CHANGING cv_kf TYPE string.

  DATA: lv_l     TYPE i,
        lv_head3 TYPE c LENGTH 3.

  CONDENSE cv_kf.
  TRANSLATE cv_kf TO UPPER CASE.
  lv_l = strlen( cv_kf ).
  WHILE lv_l > 3.
    CLEAR lv_head3.
    lv_head3 = cv_kf+0(3).
    IF lv_head3 <> 'AND'.
      EXIT.
    ENDIF.
    cv_kf = cv_kf+3.
    CONDENSE cv_kf.
    lv_l = strlen( cv_kf ).
  ENDWHILE.
ENDFORM.

*&---------------------------------------------------------------------*
*& Dynamic WHERE sometimes shows '...'ANDMJAHR or '...' ANDMJAHR (missing
*& space between AND and field). Fix using DDIC keys, longest name first.
*&---------------------------------------------------------------------*
FORM zsp26_arch_fix_where_glued_and
  USING    VALUE(pv_tab) TYPE tabname
  CHANGING cv_where       TYPE string.

  TYPES: BEGIN OF ty_kflen,
           kfname TYPE fieldname,
           kflen  TYPE i,
         END OF ty_kflen.

  DATA: lt_df    TYPE TABLE OF dfies,
        ls_df    TYPE dfies,
        lt_kflen TYPE STANDARD TABLE OF ty_kflen WITH DEFAULT KEY,
        ls_kf    TYPE ty_kflen,
        lv_fn    TYPE fieldname,
        lv_fr    TYPE string,
        lv_to    TYPE string,
        lv_tab   TYPE tabname.

  CHECK pv_tab IS NOT INITIAL AND cv_where IS NOT INITIAL.

  lv_tab = pv_tab.
  CONDENSE lv_tab.
  TRANSLATE lv_tab TO UPPER CASE.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = lv_tab
    TABLES     dfies_tab = lt_df
    EXCEPTIONS OTHERS    = 7.
  IF sy-subrc <> 0 OR lt_df IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lt_kflen.
  LOOP AT lt_df INTO ls_df WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
    CLEAR ls_kf.
    ls_kf-kfname = ls_df-fieldname.
    CONDENSE ls_kf-kfname.
    TRANSLATE ls_kf-kfname TO UPPER CASE.
    ls_kf-kflen = strlen( ls_kf-kfname ).
    CHECK ls_kf-kflen > 0.
    APPEND ls_kf TO lt_kflen.
  ENDLOOP.
  SORT lt_kflen BY kflen DESCENDING.

  LOOP AT lt_kflen INTO ls_kf.
    lv_fn = ls_kf-kfname.
    lv_fr = `'` && `AND` && lv_fn.
    lv_to = `'` && ` AND ` && lv_fn.
    REPLACE ALL OCCURRENCES OF lv_fr IN cv_where WITH lv_to.
    lv_fr = `'` && ` AND` && lv_fn.
    lv_to = `'` && ` AND ` && lv_fn.
    REPLACE ALL OCCURRENCES OF lv_fr IN cv_where WITH lv_to.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& F4 help: tables — prioritize ZSP26_ARCH_CFG (configured), fallback DD02V
*&  Show all Z* transparent tables from DDIC + mark which are configured
*&---------------------------------------------------------------------*
FORM f4_arch_cfg_table CHANGING cv_tabname TYPE tabname.

  TYPES: BEGIN OF ty_sht_f4,
           table_name  TYPE tabname,
           description TYPE char80,
           configured  TYPE char3,   " 'YES' if active config exists
         END OF ty_sht_f4.

  DATA: lt_sht     TYPE STANDARD TABLE OF ty_sht_f4 WITH DEFAULT KEY,
        ls_sht     TYPE ty_sht_f4,
        lt_cfg     TYPE STANDARD TABLE OF ty_sht_f4 WITH DEFAULT KEY,
        ls_cfg     TYPE ty_sht_f4.

  PERFORM zsp26_sync_cfg_active_vs_ddic.

  " Step 1: Read tables with active config from ZSP26_ARCH_CFG
  SELECT table_name, description
    FROM zsp26_arch_cfg
    WHERE is_active = 'X'
    INTO TABLE @DATA(lt_cfg_tmp)
    UP TO 999 ROWS.
  lt_cfg = CORRESPONDING #( lt_cfg_tmp ).

  " Step 2: Read all Z* transparent tables from DDIC
  SELECT tabname AS table_name, ddtext AS description
    FROM dd02v
    INTO TABLE @DATA(lt_sht_tmp)
    WHERE tabname  LIKE 'Z%'
      AND tabclass = 'TRANSP'.
  lt_sht = CORRESPONDING #( lt_sht_tmp ).

  " Step 3: Mark tables that have config
  LOOP AT lt_sht ASSIGNING FIELD-SYMBOL(<row>).
    READ TABLE lt_cfg INTO ls_cfg WITH KEY table_name = <row>-table_name.
    IF sy-subrc = 0.
      <row>-configured = 'YES'.
      IF <row>-description IS INITIAL AND ls_cfg-description IS NOT INITIAL.
        <row>-description = ls_cfg-description.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " If DDIC returns empty (system restricts dd02v) → fallback to CFG
  IF lt_sht IS INITIAL.
    LOOP AT lt_cfg INTO ls_cfg.
      CLEAR ls_sht.
      ls_sht-table_name  = ls_cfg-table_name.
      ls_sht-description = ls_cfg-description.
      ls_sht-configured  = 'YES'.
      APPEND ls_sht TO lt_sht.
    ENDLOOP.
  ENDIF.

  SORT lt_sht BY configured DESCENDING table_name.  " YES first

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield     = 'TABLE_NAME'
      window_title = 'Z Tables (YES=archive configured)' ##NO_TEXT
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
      OTHERS     = 0.
  READ TABLE lt_df INTO ls_df INDEX 1.
  IF sy-subrc = 0 AND ls_df-fieldvalue IS NOT INITIAL.
    cv_tabname = CONV tabname( ls_df-fieldvalue ).
    CONDENSE cv_tabname.
    TRANSLATE cv_tabname TO UPPER CASE.
  ENDIF.
ENDFORM.
