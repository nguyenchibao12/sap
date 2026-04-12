*&---------------------------------------------------------------------*
*& Include  Z_GSP18_ARCH_DYN
*& Shared helpers: validate table vs ZSP26_ARCH_CFG, dynamic WHERE,
*& apply_archive_rules, F4 for P_TABLE (ZSP26_ARCH_CFG)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Validate archive target table against ZSP26_ARCH_CFG + DDIC
*& 1 Row exists, IS_ACTIVE, DATA_FIELD non-initial
*& 2 Table exists in DDIC and DATA_FIELD is a real column
*&---------------------------------------------------------------------*
FORM validate_table_against_cfg
  USING    VALUE(pv_table) TYPE tabname
  CHANGING ps_cfg          TYPE zsp26_arch_cfg
           cv_ok           TYPE abap_bool.

  DATA: lt_df       TYPE TABLE OF dfies,
        lt_cfg_pick TYPE STANDARD TABLE OF zsp26_arch_cfg WITH EMPTY KEY,
        lv_tn       TYPE tabname.

  CLEAR: ps_cfg, cv_ok.
  cv_ok = abap_false.

  lv_tn = pv_table.
  CONDENSE lv_tn.
  TRANSLATE lv_tn TO UPPER CASE.
  IF lv_tn IS INITIAL.
    RETURN.
  ENDIF.

  SELECT * FROM zsp26_arch_cfg
    INTO TABLE @lt_cfg_pick
    WHERE table_name = @lv_tn AND is_active = 'X'.
  IF lt_cfg_pick IS INITIAL.
    RETURN.
  ENDIF.
  SORT lt_cfg_pick BY changed_on DESCENDING created_on DESCENDING config_id.
  READ TABLE lt_cfg_pick INTO ps_cfg INDEX 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  IF ps_cfg-data_field IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = lv_tn
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
      cv_where = |{ ps_cfg-data_field } GE '{ pv_dlow }' AND { ps_cfg-data_field } LE '{ lv_hi }'|.
    ELSE.
      cv_where = |{ ps_cfg-data_field } LE '{ lv_hi }'|.
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
      EXCEPTIONS OTHERS    = 7.
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
            lv_match = abap_true.
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
            lv_match = abap_true.
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
*& F4: active ZSP26_ARCH_CFG tables (shared WRITE / READ / DELETE)
*&---------------------------------------------------------------------*
FORM f4_arch_cfg_table CHANGING cv_tabname TYPE tabname.
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
    cv_tabname = CONV tabname( ls_df-fieldvalue ).
    CONDENSE cv_tabname.
    TRANSLATE cv_tabname TO UPPER CASE.
  ENDIF.
ENDFORM.
