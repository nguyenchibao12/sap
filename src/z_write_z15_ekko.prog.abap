REPORT z_write_z15_ekko.

TABLES: zekko_15.

DATA: gt_ready  TYPE TABLE OF zekko_15,
      lv_handle TYPE handle,
      lt_zekko  TYPE TABLE OF zekko_15,
      ls_zekko  TYPE zekko_15.

*----------------------------------------------------------------------*
* Class xử lý nút bấm
*----------------------------------------------------------------------*
CLASS lcl_handler DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS: on_user_command
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

CLASS lcl_handler IMPLEMENTATION.
  METHOD on_user_command.
    CASE e_salv_function.
      WHEN 'ARCH_NOW'.
        DATA: lv_answer TYPE c.
        CALL FUNCTION 'POPUP_TO_CONFIRM'
          EXPORTING
            titlebar       = 'Confirm Archive'
            text_question  = |Archive { lines( gt_ready ) } READY records?|
            text_button_1  = 'Yes, Archive'
            text_button_2  = 'Cancel'
            default_button = '2'
          IMPORTING
            answer         = lv_answer.
        IF lv_answer = '1'.
          PERFORM do_archive.
        ENDIF.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Selection Screen — có nút PREVIEW ngay trên màn hình
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  " Nút Preview ngay trên selection screen
  SELECTION-SCREEN PUSHBUTTON /1(20) but_prev USER-COMMAND prev.
  SELECTION-SCREEN SKIP 1.

  SELECT-OPTIONS: s_bukrs FOR zekko_15-bukrs,
                  s_aedat FOR zekko_15-aedat,
                  s_ebeln FOR zekko_15-ebeln.

  PARAMETERS: p_test TYPE c AS CHECKBOX DEFAULT 'X'.

SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
INITIALIZATION.
*----------------------------------------------------------------------*
  but_prev = icon_display. " Icon + text
  but_prev = '@ Preview Data @'.

  s_aedat-low    = sy-datum - 365.
  s_aedat-high   = sy-datum.
  s_aedat-sign   = 'I'.
  s_aedat-option = 'BT'.
  APPEND s_aedat.

*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
*----------------------------------------------------------------------*
  " Bấm nút Preview trên selection screen
  IF sy-ucomm = 'PREV'.
    PERFORM load_data.
    IF lt_zekko IS NOT INITIAL.
      PERFORM show_preview.
    ELSE.
      MESSAGE 'No data found for selected criteria' TYPE 'S'
              DISPLAY LIKE 'W'.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*
  PERFORM load_data.

  IF lt_zekko IS INITIAL.
    MESSAGE 'No data found. Please adjust filter.' TYPE 'S'
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF p_test = 'X'.
    PERFORM show_preview.
  ELSE.
    CLEAR gt_ready.
    LOOP AT lt_zekko INTO ls_zekko.
      IF sy-datum - ls_zekko-aedat >= 180.
        APPEND ls_zekko TO gt_ready.
      ENDIF.
    ENDLOOP.
    PERFORM do_archive.
  ENDIF.

*----------------------------------------------------------------------*
FORM load_data.
*----------------------------------------------------------------------*
  CLEAR lt_zekko.
  SELECT * FROM zekko_15
    INTO TABLE lt_zekko
    WHERE bukrs IN s_bukrs
      AND ebeln IN s_ebeln
      AND aedat IN s_aedat.
ENDFORM.

*----------------------------------------------------------------------*
FORM show_preview.
*----------------------------------------------------------------------*
  TYPES: BEGIN OF ty_prev,
           ebeln  TYPE zekko_15-ebeln,
           aedat  TYPE zekko_15-aedat,
           bukrs  TYPE zekko_15-bukrs,
           lifnr  TYPE zekko_15-lifnr,
           bsart  TYPE zekko_15-bsart,
           age    TYPE i,
           status TYPE char10,
           reason TYPE char60,
         END OF ty_prev.

  DATA: lt_prev TYPE TABLE OF ty_prev,
        ls_prev TYPE ty_prev,
        lv_rdy  TYPE i VALUE 0,
        lv_skp  TYPE i VALUE 0.

  CONSTANTS: c_min_age TYPE i VALUE 180.

  CLEAR gt_ready.

  LOOP AT lt_zekko INTO ls_zekko.
    CLEAR ls_prev.
    ls_prev-ebeln = ls_zekko-ebeln.
    ls_prev-aedat = ls_zekko-aedat.
    ls_prev-bukrs = ls_zekko-bukrs.
    ls_prev-lifnr = ls_zekko-lifnr.
    ls_prev-bsart = ls_zekko-bsart.
    ls_prev-age   = sy-datum - ls_zekko-aedat.

    IF ls_prev-age >= c_min_age.
      ls_prev-status = 'READY'.
      ls_prev-reason = |Eligible - { ls_prev-age } days|.
      ADD 1 TO lv_rdy.
      APPEND ls_zekko TO gt_ready.
    ELSE.
      ls_prev-status = 'SKIP'.
      ls_prev-reason = |Too new - { ls_prev-age }/{ c_min_age } days|.
      ADD 1 TO lv_skp.
    ENDIF.

    APPEND ls_prev TO lt_prev.
  ENDLOOP.

  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lo_funcs TYPE REF TO cl_salv_functions.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_prev ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    TRY.
      lo_funcs->add_function(
        name     = 'ARCH_NOW'
        icon     = '@2L@'
        text     = 'Archive Now'
        tooltip  = |Archive { lv_rdy } READY records|
        position = if_salv_c_function_position=>right_of_salv_functions ).
    CATCH cx_salv_method_not_supported.
    ENDTRY.

    DATA(lo_events) = lo_alv->get_event( ).
    SET HANDLER lcl_handler=>on_user_command FOR lo_events.

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
    lo_col ?= lo_cols->get_column( 'AGE' ).
    lo_col->set_long_text( 'Age (days)' ).
    lo_col ?= lo_cols->get_column( 'STATUS' ).
    lo_col->set_long_text( 'Archive Status' ).
    lo_col ?= lo_cols->get_column( 'REASON' ).
    lo_col->set_long_text( 'Reason / Detail' ).

    lo_disp = lo_alv->get_display_settings( ).
    lo_disp->set_list_header(
      |PREVIEW — Total: { lines( lt_prev ) } POs  | &&
      |[ READY: { lv_rdy }  /  SKIP: { lv_skp } ]| ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO DATA(lx).
    MESSAGE lx->get_text( ) TYPE 'E'.
  ENDTRY.

ENDFORM.

*----------------------------------------------------------------------*
FORM do_archive.
*----------------------------------------------------------------------*
  IF gt_ready IS INITIAL.
    MESSAGE 'No READY records to archive' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'ARCHIVE_OPEN_FOR_WRITE'
    EXPORTING
      object         = 'Z_ARCH_EKK'
    IMPORTING
      archive_handle = lv_handle
    EXCEPTIONS
      error_opening  = 1
      OTHERS         = 2.

  IF sy-subrc <> 0.
    MESSAGE 'Error: Cannot open archive session' TYPE 'E'.
    RETURN.
  ENDIF.

  LOOP AT gt_ready INTO ls_zekko.
    CALL FUNCTION 'ARCHIVE_NEW_OBJECT'
      EXPORTING
        archive_handle = lv_handle
        object_id      = ls_zekko-ebeln.

    CALL FUNCTION 'ARCHIVE_PUT_RECORD'
      EXPORTING
        archive_handle   = lv_handle
        record_structure = 'ZEKKO_15'
        record           = ls_zekko.

    CALL FUNCTION 'ARCHIVE_SAVE_OBJECT'
      EXPORTING
        archive_handle = lv_handle.
  ENDLOOP.

  CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
    EXPORTING
      archive_handle = lv_handle.

  MESSAGE |Archive complete: { lines( gt_ready ) } records|
          TYPE 'S'.

ENDFORM.
