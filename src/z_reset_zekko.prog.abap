REPORT z_reset_zekko.

DATA: lv_count TYPE i.

" Đếm xem còn bao nhiêu record
SELECT COUNT(*) FROM zekko_15 INTO lv_count.
WRITE: / |Trước khi xóa: { lv_count } records|.

" Xóa toàn bộ
DELETE FROM zekko_15 WHERE ebeln LIKE '%'.
COMMIT WORK AND WAIT.


" Kiểm tra lại
SELECT COUNT(*) FROM zekko_15 INTO lv_count.
WRITE: / |Sau khi xóa: { lv_count } records|.

IF lv_count = 0.
  WRITE: / '>>> XÓA THÀNH CÔNG - Có thể copy lại data <<<'.
ELSE.
  WRITE: / '>>> VẪN CÒN DATA - Chưa xóa hết <<<'.
ENDIF.
