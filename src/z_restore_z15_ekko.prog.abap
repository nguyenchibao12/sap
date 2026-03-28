REPORT z_restore_z15_ekko.

TABLES: zekko_15.

DATA: lv_handle TYPE handle,
      ls_ekko   TYPE zekko_15,
      lv_count  TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS: s_ebeln FOR zekko_15-ebeln,
                  s_aedat FOR zekko_15-aedat,
                  s_bukrs FOR zekko_15-bukrs.
  " Nút Show Archived Data
  SELECTION-SCREEN PUSHBUTTON /1(25) but_show USER-COMMAND show.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  but_show       = 'Show Archived Data'.

AT SELECTION-SCREEN.
  IF sy-ucomm = 'SHOW'.
    PERFORM show_archived_data.
  ENDIF.

START-OF-SELECTION.
  " Restore thẳng không hỏi
  PERFORM do_restore.

*----------------------------------------------------------------------*
FORM show_archived_data.
*----------------------------------------------------------------------*
  DATA: lt_preview TYPE TABLE OF zekko_15,
        lo_alv     TYPE REF TO cl_salv_table,
        lo_cols    TYPE REF TO cl_salv_columns_table,
        lo_col     TYPE REF TO cl_salv_column_table,
        lo_disp    TYPE REF TO cl_salv_display_settings,
        lo_funcs   TYPE REF TO cl_salv_functions.

  " Mở archive để đọc
  CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
    EXPORTING
      object         = 'Z_ARCH_EKK'
    IMPORTING
      archive_handle = lv_handle
    EXCEPTIONS
      error_opening  = 1
      OTHERS         = 2.

  IF sy-subrc <> 0.
    MESSAGE 'Không tìm thấy archive file' TYPE 'S'
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

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

      IF ls_ekko-ebeln IN s_ebeln
        AND ls_ekko-aedat IN s_aedat
        AND ls_ekko-bukrs IN s_bukrs.
        APPEND ls_ekko TO lt_preview.
      ENDIF.
    ENDDO.
  ENDDO.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_handle.

  IF lt_preview IS INITIAL.
    MESSAGE 'Không tìm thấy data trong archive' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " Hiện ALV
  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_preview ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    lo_col ?= lo_cols->get_column( 'EBELN' ).
    lo_col->set_long_text( 'Purchase Order' ).
    lo_col ?= lo_cols->get_column( 'AEDAT' ).
    lo_col->set_long_text( 'Created On' ).
    lo_col ?= lo_cols->get_column( 'BUKRS' ).
    lo_col->set_long_text( 'Company Code' ).
    lo_col ?= lo_cols->get_column( 'LIFNR' ).
    lo_col->set_long_text( 'Supplier' ).
    lo_col ?= lo_cols->get_column( 'BSART' ).
    lo_col->set_long_text( 'PO Type' ).

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |ARCHIVED DATA — { lines( lt_preview ) } records| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.

ENDFORM.

*----------------------------------------------------------------------*
FORM do_restore.
*----------------------------------------------------------------------*
  CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
    EXPORTING
      object         = 'Z_ARCH_EKK'
    IMPORTING
      archive_handle = lv_handle
    EXCEPTIONS
      error_opening  = 1
      OTHERS         = 2.

  IF sy-subrc <> 0.
    MESSAGE 'Không tìm thấy archive file' TYPE 'E'.
    RETURN.
  ENDIF.

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

      IF ls_ekko-ebeln IN s_ebeln
        AND ls_ekko-aedat IN s_aedat
        AND ls_ekko-bukrs IN s_bukrs.

        INSERT zekko_15 FROM ls_ekko.
        IF sy-subrc <> 0.
          MODIFY zekko_15 FROM ls_ekko.
          IF sy-subrc = 0.
            ADD 1 TO lv_count.
          ELSE.
            ADD 1 TO lv_err.
          ENDIF.
        ELSE.
          ADD 1 TO lv_count.
        ENDIF.

      ENDIF.
    ENDDO.
  ENDDO.

  IF lv_count > 0.
    COMMIT WORK AND WAIT.
  ENDIF.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_handle.

  MESSAGE |Restore xong: { lv_count } records vào ZEKKO_15|
          TYPE 'S'.

ENDFORM.
