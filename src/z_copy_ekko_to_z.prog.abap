REPORT z_copy_ekko_to_z.

DATA: lt_ekko  TYPE TABLE OF ekko,
      lv_count TYPE i.

" Kiểm tra ZEKKO_15 có trống không
SELECT COUNT(*) FROM zekko_15 INTO lv_count.
IF lv_count > 0.
  WRITE: / |ZEKKO_15 vẫn còn { lv_count } records!|.
  WRITE: / 'Hãy chạy Z_RESET_ZEKKO trước'.
  RETURN.   " Dừng lại, không INSERT
ENDIF.

" ZEKKO_15 đã trống → copy từ EKKO
SELECT * FROM ekko INTO TABLE lt_ekko.

IF lt_ekko IS NOT INITIAL.
  INSERT zekko_15 FROM TABLE lt_ekko.
  COMMIT WORK AND WAIT.
  WRITE: / |Copy thành công: { lines( lt_ekko ) } records|.
ELSE.
  WRITE: / 'EKKO không có data'.
ENDIF.
