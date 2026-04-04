*&---------------------------------------------------------------------*
*& Include  Z_GSP18_APPLY_RULES
*& Shared FORM apply_archive_rules (main UI + ADK write)
*& AND_OR on rule N = how rule N links to rule N+1 (evaluated when
*& processing rule N+1).
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
