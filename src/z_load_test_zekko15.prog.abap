*&---------------------------------------------------------------------*
*& Report Z_LOAD_TEST_ZEKKO15
*& Mục đích : Tạo dữ liệu test trong ZEKKO_15 để demo Full Flow
*&
*&   Kết quả sau khi chạy:
*&    5 PO rất cũ  (> 365 ngày)  → READY   [BuKrs 1000, NB]
*&    5 PO đủ tuổi (180-364 ngày) → READY   [BuKrs 1000, FO]
*&    5 PO còn mới (30- 90 ngày)  → TOO NEW [BuKrs 2000, NB]
*&    5 PO rất mới (1-  20 ngày)  → TOO NEW [BuKrs 2000, FO]
*&   Tổng: 20 records, 10 READY / 10 TOO NEW
*&---------------------------------------------------------------------*
REPORT z_load_test_zekko15.

TABLES: zekko_15.

PARAMETERS: p_reset TYPE c AS CHECKBOX DEFAULT ' '
              MODIF ID rst.

SELECTION-SCREEN COMMENT /1(60) txt_info.

INITIALIZATION.
  txt_info = 'Tick "Reset" để xóa hết data cũ trước khi load mới'.

START-OF-SELECTION.
  DATA: lt_ekko  TYPE TABLE OF zekko_15,
        ls_ekko  TYPE zekko_15,
        lv_count TYPE i,
        lv_ebeln TYPE zekko_15-ebeln.

  " Reset nếu được yêu cầu
  IF p_reset = 'X'.
    DELETE FROM zekko_15 WHERE ebeln LIKE '%'.
    COMMIT WORK AND WAIT.
    WRITE: / '>>> Đã xóa toàn bộ data cũ trong ZEKKO_15'.
  ENDIF.

  " Kiểm tra đã có data chưa
  SELECT COUNT(*) FROM zekko_15 INTO lv_count.
  IF lv_count > 0.
    WRITE: / |ZEKKO_15 đã có { lv_count } records. Tick "Reset" nếu muốn tạo lại.|.
    RETURN.
  ENDIF.

  " ─────────────────────────────────────────────────────────────────
  " Nhóm 1: READY — Rất cũ (450 → 700 ngày trước)  BuKrs=1000 NB
  " ─────────────────────────────────────────────────────────────────
  DO 5 TIMES.
    CLEAR ls_ekko.
    lv_ebeln = |4500000{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ebeln = lv_ebeln.
    ls_ekko-bukrs = '1000'.
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = 'NB'.
    ls_ekko-aedat = sy-datum - ( 450 + sy-index * 50 ).  " 500-700 ngày
    ls_ekko-bedat = ls_ekko-aedat.
    ls_ekko-lifnr = |100{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ekorg = '1000'.
    ls_ekko-ekgrp = '001'.
    ls_ekko-waers = 'USD'.
    ls_ekko-ernam = 'USER01'.
    APPEND ls_ekko TO lt_ekko.
  ENDDO.

  " ─────────────────────────────────────────────────────────────────
  " Nhóm 2: READY — Vừa đủ tuổi (180 → 360 ngày)  BuKrs=1000 FO
  " ─────────────────────────────────────────────────────────────────
  DO 5 TIMES.
    CLEAR ls_ekko.
    lv_ebeln = |4500001{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ebeln = lv_ebeln.
    ls_ekko-bukrs = '1000'.
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = 'FO'.
    ls_ekko-aedat = sy-datum - ( 180 + sy-index * 30 ).  " 210-330 ngày
    ls_ekko-bedat = ls_ekko-aedat.
    ls_ekko-lifnr = |200{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ekorg = '1000'.
    ls_ekko-ekgrp = '001'.
    ls_ekko-waers = 'VND'.
    ls_ekko-ernam = 'USER01'.
    APPEND ls_ekko TO lt_ekko.
  ENDDO.

  " ─────────────────────────────────────────────────────────────────
  " Nhóm 3: TOO NEW — Còn mới (30 → 120 ngày)  BuKrs=2000 NB
  " ─────────────────────────────────────────────────────────────────
  DO 5 TIMES.
    CLEAR ls_ekko.
    lv_ebeln = |4500002{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ebeln = lv_ebeln.
    ls_ekko-bukrs = '2000'.
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = 'NB'.
    ls_ekko-aedat = sy-datum - ( 30 + sy-index * 18 ).   " 48-120 ngày
    ls_ekko-bedat = ls_ekko-aedat.
    ls_ekko-lifnr = |300{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ekorg = '2000'.
    ls_ekko-ekgrp = '002'.
    ls_ekko-waers = 'EUR'.
    ls_ekko-ernam = 'USER02'.
    APPEND ls_ekko TO lt_ekko.
  ENDDO.

  " ─────────────────────────────────────────────────────────────────
  " Nhóm 4: TOO NEW — Rất mới (1 → 20 ngày)  BuKrs=2000 FO
  " ─────────────────────────────────────────────────────────────────
  DO 5 TIMES.
    CLEAR ls_ekko.
    lv_ebeln = |4500003{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ebeln = lv_ebeln.
    ls_ekko-bukrs = '2000'.
    ls_ekko-bstyp = 'F'.
    ls_ekko-bsart = 'FO'.
    ls_ekko-aedat = sy-datum - ( sy-index * 4 ).         " 4-20 ngày
    ls_ekko-bedat = ls_ekko-aedat.
    ls_ekko-lifnr = |400{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
    ls_ekko-ekorg = '2000'.
    ls_ekko-ekgrp = '002'.
    ls_ekko-waers = 'EUR'.
    ls_ekko-ernam = 'USER02'.
    APPEND ls_ekko TO lt_ekko.
  ENDDO.

  " Insert tất cả
  INSERT zekko_15 FROM TABLE lt_ekko.

  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
    WRITE: / ''.
    WRITE: / '============================================'.
    WRITE: / '   ZEKKO_15 TEST DATA LOADED SUCCESSFULLY  '.
    WRITE: / '============================================'.
    WRITE: / ''.
    WRITE: / 'Nhóm 1 — READY  (>180d)  BuKrs=1000  NB :  5 POs  (500-700 ngày tuổi)'.
    WRITE: / 'Nhóm 2 — READY  (>180d)  BuKrs=1000  FO :  5 POs  (210-330 ngày tuổi)'.
    WRITE: / 'Nhóm 3 — TOO NEW         BuKrs=2000  NB :  5 POs  ( 48-120 ngày tuổi)'.
    WRITE: / 'Nhóm 4 — TOO NEW         BuKrs=2000  FO :  5 POs  (   4- 20 ngày tuổi)'.
    WRITE: / ''.
    WRITE: / 'TỔNG: 20 records | 10 READY | 10 TOO NEW'.
    WRITE: / ''.
    WRITE: / '>>> Bây giờ có thể chạy Z_WRITE_Z15_EKKO để test Preview & Archive'.
  ELSE.
    WRITE: / 'LỖI INSERT — sy-subrc =', sy-subrc.
    WRITE: / 'Nếu có lỗi duplicate key, hãy tick "Reset" rồi chạy lại.'.
  ENDIF.
