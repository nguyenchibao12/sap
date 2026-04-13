*&---------------------------------------------------------------------*
*& Report ZSP26_ARCH_ADMIN_SETUP
*&---------------------------------------------------------------------*
*& Tiện ích thêm/xóa user admin cho hệ thống archive hub
*& Chạy 1 lần từ SE38 sau khi activate bảng ZSP26_ARCH_ADMIN
*&---------------------------------------------------------------------*
REPORT zsp26_arch_admin_setup.

PARAMETERS:
  p_uname TYPE syuname DEFAULT sy-uname OBLIGATORY,
  p_del   TYPE char1  AS CHECKBOX DEFAULT ' '.  " Tick = XÓA khỏi admin

START-OF-SELECTION.

  DATA: ls_adm    TYPE zsp26_arch_admin,
        lt_admins TYPE TABLE OF zsp26_arch_admin,
        ls_u      TYPE zsp26_arch_admin.

  ls_adm-mandt = sy-mandt.
  ls_adm-uname = p_uname.

  IF p_del = 'X'.
    " Xóa khỏi danh sách admin
    DELETE FROM zsp26_arch_admin
      WHERE uname = @p_uname.
    IF sy-subrc = 0.
      WRITE: / |User { p_uname } đã bị XÓA khỏi danh sách admin.|.
    ELSE.
      WRITE: / |User { p_uname } không có trong danh sách admin.|.
    ENDIF.
  ELSE.
    " Thêm vào danh sách admin
    INSERT zsp26_arch_admin FROM ls_adm.
    IF sy-subrc = 0.
      WRITE: / |User { p_uname } đã được thêm làm ADMIN.|.
    ELSEIF sy-subrc = 4.
      WRITE: / |User { p_uname } đã là ADMIN rồi (không thay đổi).|.
    ELSE.
      WRITE: / |Lỗi khi thêm user { p_uname } (sy-subrc={ sy-subrc }).|.
    ENDIF.
  ENDIF.

  COMMIT WORK.

  " Hiển thị danh sách admin hiện tại
  SKIP.
  WRITE: / '--- Danh sách Admin hiện tại ---'.
  SELECT * FROM zsp26_arch_admin
    INTO TABLE lt_admins
    ORDER BY uname.
  IF lt_admins IS INITIAL.
    WRITE: / '(Chưa có admin nào)'.
  ELSE.
    LOOP AT lt_admins INTO ls_u.
      WRITE: / ls_u-uname.
    ENDLOOP.
  ENDIF.
