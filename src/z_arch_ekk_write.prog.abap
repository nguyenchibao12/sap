*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_WRITE
*& ADK Write Program — Archive Object Z_ARCH_EKK
*& Generic: archives any ZSP26_* table configured in ZSP26_ARCH_CFG
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_write.

"----------------------------------------------------------------------
" Archive record structure written to ADK file — fixed length, no string
"----------------------------------------------------------------------
TYPES: BEGIN OF ty_arch_rec,
         rec_type   TYPE c LENGTH 1,     " 'D' = data record
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_arch_rec.

DATA: gs_cfg    TYPE zsp26_arch_cfg,
      ls_arec   TYPE ty_arch_rec,
      gr_src    TYPE REF TO data,
      lt_dd     TYPE TABLE OF dfies,
      lv_cutoff TYPE d,
      lv_cnt    TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0.

FIELD-SYMBOLS: <lt_src> TYPE ANY TABLE,
               <row>    TYPE any.

PARAMETERS: p_table TYPE tabname  OBLIGATORY DEFAULT 'ZSP26_EKKO',
            p_test  TYPE c        AS CHECKBOX DEFAULT ' '.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  " 1. Read archive config
  SELECT SINGLE * FROM zsp26_arch_cfg INTO @gs_cfg
    WHERE table_name = @p_table AND is_active = 'X'.
  IF sy-subrc <> 0.
    MESSAGE |Chưa có config active cho '{ p_table }'.| TYPE 'A'.
  ENDIF.
  IF gs_cfg-data_field IS INITIAL.
    MESSAGE |Config cho '{ p_table }' thiếu Date Field.| TYPE 'A'.
  ENDIF.

  " 2. Cutoff date
  lv_cutoff = sy-datum - gs_cfg-retention.

  WRITE: /.
  WRITE: / |=== ADK Write: { p_table } ===|.
  WRITE: / |Date Field: { gs_cfg-data_field }  /  Retention: { gs_cfg-retention } days  /  Cutoff: { lv_cutoff }|.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no data written to archive ***'. ENDIF.
  WRITE: /.

  " 3. Open archive for write (skip in test mode)
  IF p_test = ' '.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_WRITE'
      EXPORTING
        archiv_obj = 'Z_ARCH_EKK'
      EXCEPTIONS
        open_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      MESSAGE 'Cannot open archive Z_ARCH_EKK. Check AOBJ/SARA config.' TYPE 'A'.
    ENDIF.
  ENDIF.

  " 4. Get key fields from DDIC
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING  tabname   = p_table
    TABLES     dfies_tab = lt_dd
    EXCEPTIONS OTHERS    = 1.

  " 5. Dynamic SELECT — only eligible records
  CREATE DATA gr_src TYPE TABLE OF (p_table).
  ASSIGN gr_src->* TO <lt_src>.
  DATA(lv_where) = |{ gs_cfg-data_field } LE '{ lv_cutoff }'|.
  SELECT * FROM (p_table) INTO TABLE <lt_src> WHERE (lv_where).

  WRITE: / |Records eligible: { lines( <lt_src> ) }|.

  IF <lt_src> IS INITIAL.
    WRITE: / 'Không có records đủ điều kiện.'.
    IF p_test = ' '.
      CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
        EXPORTING object_count = 0
        EXCEPTIONS OTHERS      = 1.
    ENDIF.
    RETURN.
  ENDIF.

  " 6. Write each record to archive file
  LOOP AT <lt_src> ASSIGNING <row>.
    " Build key string: FIELD1=VAL1|FIELD2=VAL2
    DATA: lv_kv TYPE char255.
    CLEAR lv_kv.
    LOOP AT lt_dd INTO DATA(ls_dd) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
      ASSIGN COMPONENT ls_dd-fieldname OF STRUCTURE <row> TO FIELD-SYMBOL(<fv>).
      IF <fv> IS ASSIGNED.
        IF lv_kv IS NOT INITIAL. lv_kv &&= '|'. ENDIF.
        lv_kv &&= ls_dd-fieldname && '=' && <fv>.
      ENDIF.
    ENDLOOP.

    " Serialize to JSON
    DATA: lv_json TYPE string,
          lv_jc   TYPE c LENGTH 4990.
    TRY.
      lv_json = /ui2/cl_json=>serialize( data = <row> ).
    CATCH cx_root.
      lv_json = lv_kv.
    ENDTRY.
    lv_jc = lv_json.  " string → C (auto-truncate at 4990)

    " Build archive record
    CLEAR ls_arec.
    ls_arec-rec_type   = 'D'.
    ls_arec-table_name = p_table.
    ls_arec-key_vals   = lv_kv.
    ls_arec-data_json  = lv_jc.

    IF p_test = ' '.
      CALL FUNCTION 'ARCHIVE_WRITE_RECORD'
        EXPORTING  record        = ls_arec
        EXCEPTIONS end_of_object = 1
                   OTHERS        = 2.
      IF sy-subrc <> 0.
        ADD 1 TO lv_err.
        WRITE: / |  ERROR: { lv_kv }|.
        CONTINUE.
      ENDIF.
    ELSE.
      WRITE: / |  [TEST] { lv_kv }|.
    ENDIF.

    ADD 1 TO lv_cnt.
  ENDLOOP.

  " 7. Close archive object
  IF p_test = ' '.
    CALL FUNCTION 'ARCHIVE_CLOSE_OBJECT'
      EXPORTING  object_count = lv_cnt
      EXCEPTIONS OTHERS       = 1.
  ENDIF.

  " 8. Log to ZSP26_ARCH_LOG
  IF p_test = ' '.
    DATA: ls_log TYPE zsp26_arch_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-table_name = p_table.
    ls_log-action     = 'ARCHIVE'.
    ls_log-rec_count  = lv_cnt.
    ls_log-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-exec_user  = sy-uname.
    ls_log-exec_date  = sy-datum.
    ls_log-message    = |ADK Archive: { lv_cnt } records written. Errors: { lv_err }|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.
  ENDIF.

  " 9. Summary
  WRITE: /.
  WRITE: / '=== Summary ==='.
  WRITE: / |Written to archive: { lv_cnt } records|.
  WRITE: / |Errors            : { lv_err }|.
  IF p_test = ' '.
    WRITE: / 'Next step: run Z_ARCH_EKK_DELETE via SARA to remove from DB.'.
  ELSE.
    WRITE: / 'Uncheck Test Mode and re-run to actually archive.'.
  ENDIF.
