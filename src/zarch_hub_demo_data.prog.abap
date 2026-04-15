*&---------------------------------------------------------------------*
*& Report ZARCH_HUB_DEMO_DATA
*&---------------------------------------------------------------------*
*& Nạp dữ liệu mẫu vào ZARCH_HUB_DEMO (MANDT + SEQNO + BUDAT + TITLE).
*& Dùng test Hub → Config → Register: table ZARCH_HUB_DEMO, date BUDAT.
*& Activate bảng ZARCH_HUB_DEMO (abapGit/SE11) rồi chạy SE38.
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
    MESSAGE 'Số dòng hợp lệ: 1–9999.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF p_clear = 'X'.
    DELETE FROM zarch_hub_demo.
    COMMIT WORK.
    WRITE: / |Đã DELETE FROM ZARCH_HUB_DEMO ({ sy-dbcnt } dòng).|.
  ENDIF.

  CLEAR lv_i.
  WHILE lv_i < p_rows.
    lv_i = lv_i + 1.

    CLEAR ls_row.
    ls_row-mandt = sy-mandt.
    ls_row-seqno = lv_i.

    " BUDAT lệch theo tuần để test retention / preview
    lv_off = ( lv_i - 1 ) * 7.
    ls_row-budat = sy-datum - lv_off.

    ls_row-title = |Hub demo #{ lv_i } / BUDAT={ ls_row-budat DATE = ISO }|.

    INSERT zarch_hub_demo FROM ls_row.
    IF sy-subrc <> 0.
      WRITE: / |Lỗi INSERT SEQNO={ ls_row-seqno } (có thể đã tồn tại).|.
    ENDIF.
  ENDWHILE.

  COMMIT WORK.

  SELECT COUNT(*) FROM zarch_hub_demo INTO @DATA(lv_cnt).
  SKIP.
  WRITE: / |Xong. Tổng dòng ZARCH_HUB_DEMO (client hiện tại): { lv_cnt }|.
  WRITE: / 'Tiếp theo: Hub → Config → Register — ZARCH_HUB_DEMO, Date field BUDAT.'.
