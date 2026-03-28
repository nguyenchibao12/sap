*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0100 INPUT
*&---------------------------------------------------------------------*
MODULE USER_COMMAND_0100 INPUT.
  DATA: LV_OK_CODE TYPE SY-UCOMM.

  LV_OK_CODE = OK_CODE.
  CLEAR OK_CODE.

  CASE LV_OK_CODE.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE PROGRAM.

    WHEN 'BT_WRITE'.
      " --- BẮT ĐẦU PHẦN SỬA ĐỔI ---
      " Thay vì chạy Job trực tiếp, kiểm tra Object và gọi Screen 0300
      IF GV_OBJECT IS INITIAL.
        MESSAGE 'Vui lòng nhập Archiving Object' TYPE 'E'.
      ELSE.
        TRANSLATE GV_OBJECT TO UPPER CASE.
        PERFORM GET_ARCHIVE_PROGRAMS.

        IF GV_PROG_WRITE IS NOT INITIAL.
          CALL SCREEN 0300. " Điều hướng sang màn hình Write
        ELSE.
          MESSAGE 'Archiving Object không hợp lệ hoặc chưa có chương trình Write' TYPE 'E'.
        ENDIF.
      ENDIF.
      " --- KẾT THÚC PHẦN SỬA ĐỔI ---

    WHEN 'BT_DELETE'.
      " Xử lý nút Delete cũ (nếu cần)
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Module CHECK_VARIANT_0300 INPUT
*&---------------------------------------------------------------------*
MODULE CHECK_VARIANT_0300 INPUT.
* --- BẮT ĐẦU PHẦN SỬA ĐỔI: Sửa lỗi hàm bảo trì Variant ---
  DATA: LV_RC     TYPE SY-SUBRC,
        LV_ANSWER TYPE CHAR1.

  CHECK GV_VARIANT IS NOT INITIAL.

  IF GV_PROG_WRITE IS INITIAL.
    PERFORM GET_ARCHIVE_PROGRAMS.
  ENDIF.

  " Kiểm tra Variant tồn tại
  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      REPORT  = GV_PROG_WRITE
      VARIANT = GV_VARIANT
    IMPORTING
      R_C     = LV_RC.

  " Nếu chưa có, hỏi tạo mới
  IF LV_RC <> 0.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        TITLEBAR              = 'Thông báo'
        TEXT_QUESTION         = 'Variant này chưa tồn tại. Bạn có muốn tạo mới không?'
        TEXT_BUTTON_1         = 'Có (Tạo)'
        TEXT_BUTTON_2         = 'Không'
        DISPLAY_CANCEL_BUTTON = ' '
      IMPORTING
        ANSWER                = LV_ANSWER.

    IF LV_ANSWER = '1'.
      " ĐÃ FIX: Đang tạo mới thì không được gọi USING SELECTION-SET
      SUBMIT (GV_PROG_WRITE) VIA SELECTION-SCREEN AND RETURN.
    ELSE.
      CLEAR GV_VARIANT.
    ENDIF.
  ENDIF.
* --- KẾT THÚC PHẦN SỬA ĐỔI ---
ENDMODULE.

**&---------------------------------------------------------------------*
**& Module USER_COMMAND_0300 INPUT
**&---------------------------------------------------------------------*
*MODULE USER_COMMAND_0300 INPUT.
*  CASE OK_CODE.
** --- BẮT ĐẦU PHẦN SỬA ĐỔI: Cập nhật nút bấm Edit ---
*    WHEN 'EDIT_BTN'.
*      IF GV_VARIANT IS NOT INITIAL.
*
*        " Kiểm tra xem Variant đã tồn tại trong Database chưa
*        CALL FUNCTION 'RS_VARIANT_EXISTS'
*          EXPORTING
*            REPORT  = GV_PROG_WRITE
*            VARIANT = GV_VARIANT
*          IMPORTING
*            R_C     = LV_RC.
*
*        IF LV_RC = 0.
*          " Đã tồn tại -> Mở lên để sửa kèm dữ liệu cũ
*          SUBMIT (GV_PROG_WRITE) VIA SELECTION-SCREEN USING SELECTION-SET GV_VARIANT AND RETURN.
*        ELSE.
*          " Chưa tồn tại -> Mở màn hình trắng để tạo mới
*          SUBMIT (GV_PROG_WRITE) VIA SELECTION-SCREEN AND RETURN.
*        ENDIF.
*
*      ELSE.
*        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
*      ENDIF.
** --- KẾT THÚC PHẦN SỬA ĐỔI ---
*    WHEN 'START_BTN'.
*      PERFORM MAINTENANCE_START_DATE.
*    WHEN 'SPOOL_BTN'.
*      PERFORM MAINTENANCE_SPOOL_PARAMS.
*    WHEN 'EXECUTE'.
*      PERFORM EXECUTE_WRITE_JOB.
*    WHEN 'BACK'.
*      SET SCREEN 0100. LEAVE SCREEN.
*  ENDCASE.
*  CLEAR OK_CODE.
*ENDMODULE.

*&---------------------------------------------------------------------*
*& Module USER_COMMAND_0300 INPUT
*&---------------------------------------------------------------------*
MODULE USER_COMMAND_0300 INPUT.
  DATA: LV_UCOMM  TYPE SY-UCOMM.


  LV_UCOMM = SY-UCOMM.
  CLEAR OK_CODE.

  CASE LV_UCOMM.
    WHEN 'EDIT_BTN'.
      IF GV_VARIANT IS NOT INITIAL.
        CALL FUNCTION 'RS_VARIANT_EXISTS'
          EXPORTING REPORT  = GV_PROG_WRITE
                    VARIANT = GV_VARIANT
          IMPORTING R_C     = LV_RC.

        IF LV_RC = 0.
          SUBMIT (GV_PROG_WRITE) VIA SELECTION-SCREEN USING SELECTION-SET GV_VARIANT AND RETURN.
        ELSE.
          CALL FUNCTION 'POPUP_TO_CONFIRM'
            EXPORTING
              TITLEBAR              = 'Thông báo'
              TEXT_QUESTION         = 'Variant này chưa tồn tại. Bạn có muốn tạo mới không?'
              TEXT_BUTTON_1         = 'Có (Tạo)'
              TEXT_BUTTON_2         = 'Không'
              DISPLAY_CANCEL_BUTTON = ' '
            IMPORTING
              ANSWER                = LV_ANSWER.

          IF LV_ANSWER = '1'.
            SUBMIT (GV_PROG_WRITE) VIA SELECTION-SCREEN AND RETURN.
          ELSE.
            CLEAR GV_VARIANT.
          ENDIF.
        ENDIF.
      ELSE.
        MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
      ENDIF.

    WHEN 'START_BTN'.
      PERFORM MAINTENANCE_START_DATE.
    WHEN 'SPOOL_BTN'.
      PERFORM MAINTENANCE_SPOOL_PARAMS.
    WHEN 'EXECUTE'.
      PERFORM EXECUTE_WRITE_JOB.
    WHEN 'BACK'.
      SET SCREEN 0100. LEAVE SCREEN.
  ENDCASE.
ENDMODULE.
