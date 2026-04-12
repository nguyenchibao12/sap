PROCESS BEFORE OUTPUT.
  MODULE STATUS_0300.
  " Thiết lập các giá trị mặc định khi vừa mở màn hình
  MODULE INIT_FIELDS_0300.

PROCESS AFTER INPUT.
  " Xử lý các nút thoát/hủy nhanh mà không cần kiểm tra dữ liệu
  MODULE EXIT_COMMAND AT EXIT-COMMAND.

  " Xử lý các lệnh thực thi (Execute, Save, Back)
  MODULE USER_COMMAND_0300.

PROCESS ON VALUE-REQUEST.
  FIELD gv_variant MODULE f4_gv_variant.
