*&---------------------------------------------------------------------*
*& Report ZARCH_HUB_DEMO_DATA
*&---------------------------------------------------------------------*
*& Load sample data into ZARCH_HUB_DEMO (MANDT + SEQNO + BUDAT + TITLE).
*& Used to test Hub → Config → Register: table ZARCH_HUB_DEMO, date BUDAT.
*& Activate table ZARCH_HUB_DEMO (abapGit/SE11) then run via SE38.
*&---------------------------------------------------------------------*
REPORT zarch_hub_demo_data.

PARAMETERS:
  p_rows  TYPE i DEFAULT 25 OBLIGATORY,
  p_clear TYPE xfeld AS CHECKBOX DEFAULT ' '.

START-OF-SELECTION.

  DATA: ls_row TYPE zarch_hub_demo,
        lv_i   TYPE i,
        lv_off TYPE i.

  IF p_rows < 1 OR p_rows > 9999.
    MESSAGE 'Valid row count: 1-9999.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF p_clear = 'X'.
    DELETE FROM zarch_hub_demo.
    COMMIT WORK.
    WRITE: / |Deleted from ZARCH_HUB_DEMO ({ sy-dbcnt } rows).|.
  ENDIF.

  CLEAR lv_i.
  WHILE lv_i < p_rows.
    lv_i = lv_i + 1.

    CLEAR ls_row.
    ls_row-mandt = sy-mandt.
    ls_row-seqno = lv_i.

    " BUDAT offset by weeks to test retention / preview
    lv_off = ( lv_i - 1 ) * 7.
    ls_row-budat = sy-datum - lv_off.

    ls_row-title = |Hub demo #{ lv_i } / BUDAT={ ls_row-budat DATE = ISO }|.

    INSERT zarch_hub_demo FROM ls_row.
    IF sy-subrc <> 0.
      WRITE: / |INSERT error SEQNO={ ls_row-seqno } (may already exist).|.
    ENDIF.
  ENDWHILE.

  COMMIT WORK.

  SELECT COUNT(*) FROM zarch_hub_demo INTO @DATA(lv_cnt).
  SKIP.
  WRITE: / |Done. Total rows in ZARCH_HUB_DEMO (current client): { lv_cnt }|.
  WRITE: / 'Next: Hub > Config > Register - ZARCH_HUB_DEMO, Date field BUDAT.'.
