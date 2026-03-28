*&---------------------------------------------------------------------*
*& Report  Z_ARCH_EKK_DELETE
*& ADK Delete Program — Archive Object Z_ARCH_EKK
*& Reads archive file → deletes records from source table
*& Run via SARA after verifying archive file from Write run
*&---------------------------------------------------------------------*
REPORT z_arch_ekk_delete.

TYPES: BEGIN OF ty_arch_rec,
         rec_type   TYPE c LENGTH 1,
         table_name TYPE c LENGTH 30,
         key_vals   TYPE c LENGTH 255,
         data_json  TYPE c LENGTH 4990,
       END OF ty_arch_rec.

DATA: ls_arec  TYPE ty_arch_rec,
      lv_where TYPE string,
      lv_cnt   TYPE i VALUE 0,
      lv_err   TYPE i VALUE 0.

PARAMETERS: p_test TYPE c AS CHECKBOX DEFAULT 'X'.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  WRITE: / '=== ADK Delete: Z_ARCH_EKK ==='.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no records deleted ***'. ENDIF.
  WRITE: /.

  " Open archive for delete (called from SARA — archive key passed automatically)
  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    EXPORTING  archiv_obj = 'Z_ARCH_EKK'
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive for delete. Run via SARA.' TYPE 'A'.
  ENDIF.

  " Process all records in archive file
  DO.
    CLEAR ls_arec.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
      IMPORTING  record     = ls_arec
      EXCEPTIONS end_of_file = 1
                 OTHERS      = 2.
    IF sy-subrc = 1. EXIT.   " End of archive file
    ELSEIF sy-subrc > 1. ADD 1 TO lv_err. CONTINUE. ENDIF.

    CHECK ls_arec-rec_type = 'D'.

    " Build WHERE clause from key_vals (format: FIELD1=VAL1|FIELD2=VAL2)
    CLEAR lv_where.
    DATA: lt_pairs TYPE TABLE OF string,
          lv_pair  TYPE string,
          lv_kf    TYPE string,
          lv_kv    TYPE string.
    SPLIT ls_arec-key_vals AT '|' INTO TABLE lt_pairs.
    LOOP AT lt_pairs INTO lv_pair.
      SPLIT lv_pair AT '=' INTO lv_kf lv_kv.
      IF lv_where IS NOT INITIAL. lv_where &&= ' AND '. ENDIF.
      lv_where &&= lv_kf && ` EQ '` && lv_kv && `'`.
    ENDLOOP.
    lv_where = |MANDT EQ '{ sy-mandt }' AND | && lv_where.

    WRITE: / |  { ls_arec-table_name } / { ls_arec-key_vals }|.

    IF p_test = ' '.
      " Delete from source table
      DELETE FROM (ls_arec-table_name) WHERE (lv_where).
      IF sy-subrc = 0.
        " Mark record as processed in archive file
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD'
          EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt.
      ELSE.
        ADD 1 TO lv_err.
        WRITE: / |    WARN: delete failed (sy-subrc={ sy-subrc })|.
      ENDIF.
    ELSE.
      ADD 1 TO lv_cnt.
    ENDIF.
  ENDDO.

  IF p_test = ' '. COMMIT WORK. ENDIF.

  " Log
  IF p_test = ' '.
    DATA: ls_log TYPE zsp26_arch_log.
    TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error. ENDTRY.
    ls_log-action    = 'DELETE'.
    ls_log-rec_count = lv_cnt.
    ls_log-status    = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
    ls_log-exec_user = sy-uname.
    ls_log-exec_date = sy-datum.
    ls_log-message   = |ADK Delete: { lv_cnt } records deleted. Errors: { lv_err }|.
    INSERT zsp26_arch_log FROM ls_log.
    COMMIT WORK.
  ENDIF.

  WRITE: /.
  WRITE: / |=== Summary: { lv_cnt } deleted / { lv_err } errors ===|.
  IF p_test = 'X'. WRITE: / 'Uncheck Test Mode to actually delete.'. ENDIF.
