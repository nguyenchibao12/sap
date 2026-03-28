REPORT z_delete_z15_ekko.

DATA: lv_handle TYPE handle,
      ls_ekko   TYPE zekko_15,
      lv_count  TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_test TYPE c AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b1.

START-OF-SELECTION.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    EXPORTING
      object         = 'Z_ARCH_EKK'
    IMPORTING
      archive_handle = lv_handle
    EXCEPTIONS
      error_opening  = 1
      OTHERS         = 2.

  IF sy-subrc <> 0.
    MESSAGE 'Lỗi: Không mở được archive file' TYPE 'E'.
    RETURN.
  ENDIF.

  " ── TEST MODE ──────────────────────────────────────────────
  IF p_test = 'X'.

    DO.
      CALL FUNCTION 'ARCHIVE_GET_NEXT_OBJECT'
        EXPORTING
          archive_handle          = lv_handle
        EXCEPTIONS
          end_of_file             = 1
          OTHERS                  = 2.
      IF sy-subrc <> 0. EXIT. ENDIF.

      DO.
        CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
          EXPORTING
            archive_handle = lv_handle
          IMPORTING
            record         = ls_ekko
          EXCEPTIONS
            end_of_object  = 1
            OTHERS         = 2.
        IF sy-subrc <> 0. EXIT. ENDIF.
        ADD 1 TO lv_count.
      ENDDO.
    ENDDO.

    CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
      EXPORTING
        archive_handle = lv_handle.

    WRITE: / '=== TEST MODE — Không xóa gì cả ==='.
    WRITE: / |Dự kiến sẽ xóa: { lv_count } records từ ZEKKO_15|.
    WRITE: / 'Bỏ tick P_TEST rồi chạy lại để xóa thật.'.

  " ── REAL MODE ──────────────────────────────────────────────
  ELSE.

    DO.
      CALL FUNCTION 'ARCHIVE_GET_NEXT_OBJECT'
        EXPORTING
          archive_handle          = lv_handle
        EXCEPTIONS
          end_of_file             = 1
          OTHERS                  = 2.
      IF sy-subrc <> 0. EXIT. ENDIF.

      DO.
        CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
          EXPORTING
            archive_handle = lv_handle
          IMPORTING
            record         = ls_ekko
          EXCEPTIONS
            end_of_object  = 1
            OTHERS         = 2.
        IF sy-subrc <> 0. EXIT. ENDIF.

        DELETE FROM zekko_15
          WHERE ebeln = ls_ekko-ebeln.

        IF sy-subrc = 0.
          ADD 1 TO lv_count.
        ELSE.
          ADD 1 TO lv_err.
        ENDIF.

      ENDDO.
    ENDDO.

    IF lv_count > 0.
      COMMIT WORK AND WAIT.
    ENDIF.

    CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
      EXPORTING
        archive_handle = lv_handle.

    WRITE: / '=== DELETE COMPLETE ==='.
    WRITE: / |Đã xóa thành công : { lv_count } records|.
    IF lv_err > 0.
      WRITE: / |Không tìm thấy   : { lv_err } records|.
    ENDIF.
    WRITE: / '========================'.

  ENDIF.
