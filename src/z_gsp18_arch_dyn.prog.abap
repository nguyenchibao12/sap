*&---------------------------------------------------------------------*
*& Include  Z_GSP18_ARCH_DYN
*& Shared helpers: validate table vs ZSP26_ARCH_CFG, dynamic WHERE,
*& apply_archive_rules (ZSP26_ARCH_RULE row evaluation)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Validate archive target table against ZSP26_ARCH_CFG + DDIC
*& 1) Row exists, IS_ACTIVE, DATA_FIELD non-initial
*& 2) Table exists in DDIC and DATA_FIELD is a real column
*&---------------------------------------------------------------------*
FORM validate_table_against_cfg
  USING    VALUE(pv_table) TYPE tabname
  CHANGING ps_cfg          TYPE zsp26_arch_cfg
           cv_ok           TYPE abap_bool.

  DATA: lt_df TYPE TABLE OF dfies.

  CLEAR: ps_cfg, cv_ok.
  cv_ok = abap_false.

  SELECT SINGLE * FROM zsp26_arch_cfg INTO @ps_cfg
    WHERE table_name = @pv_table AND is_active = 'X'.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  IF ps_cfg-data_field IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = pv_table
    TABLES     dfies_tab = lt_df
    EXCEPTIONS OTHERS    = 7.
  IF sy-subrc <> 0 OR lt_df IS INITIAL.
    RETURN.
  ENDIF.

  READ TABLE lt_df WITH KEY fieldname = ps_cfg-data_field TRANSPORTING NO FIELDS.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
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

  DATA: lv_hi TYPE d.

  IF pv_dhigh IS NOT INITIAL.
    lv_hi = pv_dhigh.
  ELSE.
    lv_hi = sy-datum - ps_cfg-retention.
  ENDIF.

  IF pv_dlow IS NOT INITIAL.
    cv_where = |{ ps_cfg-data_field } GE '{ pv_dlow }' AND { ps_cfg-data_field } LE '{ lv_hi }'|.
  ELSE.
    cv_where = |{ ps_cfg-data_field } LE '{ lv_hi }'|.
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
*& Shared: main UI (F01) + Z_ARCH_EKK_WRITE
*&---------------------------------------------------------------------*
FORM apply_archive_rules
  USING    iv_row    TYPE any
           iv_cfg_id TYPE zsp26_arch_cfg-config_id
  CHANGING cv_pass   TYPE abap_bool.

  DATA: lt_rules     TYPE TABLE OF zsp26_arch_rule,
        ls_rule      TYPE zsp26_arch_rule,
        ls_prev_rule TYPE zsp26_arch_rule,
        lv_result    TYPE abap_bool,
        lv_match     TYPE abap_bool,
        lv_fv_s      TYPE string,
        lv_first     TYPE abap_bool.

  cv_pass  = abap_true.
  lv_first = abap_true.

  SELECT * FROM zsp26_arch_rule INTO TABLE @lt_rules
    WHERE config_id = @iv_cfg_id
      AND is_active = 'X'
    ORDER BY rule_seq.

  IF lt_rules IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR ls_prev_rule.

  LOOP AT lt_rules INTO ls_rule.
    ASSIGN COMPONENT ls_rule-field_name OF STRUCTURE iv_row
      TO FIELD-SYMBOL(<fv>).

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
          lv_match = abap_true.
      ENDCASE.
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
