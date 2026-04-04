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

TYPES: BEGIN OF ty_del_agg,
         table_name TYPE tabname,
         cnt        TYPE i,
       END OF ty_del_agg.

DATA: ls_arec   TYPE ty_arch_rec,
      lv_where  TYPE string,
      lv_cnt    TYPE i VALUE 0,
      lv_err    TYPE i VALUE 0,
      lt_pairs  TYPE TABLE OF string,
      lv_pair   TYPE string,
      lv_kf     TYPE string,
      lv_kv     TYPE string,
      lt_del_agg TYPE HASHED TABLE OF ty_del_agg WITH UNIQUE KEY table_name,
      ls_del_agg TYPE ty_del_agg.

PARAMETERS: p_test TYPE c AS CHECKBOX DEFAULT 'X'.

*----------------------------------------------------------------------*
START-OF-SELECTION.
*----------------------------------------------------------------------*

  WRITE: / '=== ADK Delete: Z_ARCH_EKK ==='.
  IF p_test = 'X'. WRITE: / '*** TEST MODE — no records deleted ***'. ENDIF.
  WRITE: /.

  " Open archive for delete (SARA passes archive file context automatically)
  CALL FUNCTION 'ARCHIVE_OPEN_FOR_DELETE'
    EXCEPTIONS OTHERS = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot open archive for delete. Run via SARA.' TYPE 'A'.
  ENDIF.

  " Process all records in archive file
  DO.
    CLEAR ls_arec.
    CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
      IMPORTING  record      = ls_arec
      EXCEPTIONS end_of_file = 1
                 OTHERS      = 2.
    IF sy-subrc = 1. EXIT.          " End of archive file
    ELSEIF sy-subrc > 1.
      ADD 1 TO lv_err.
      CONTINUE.
    ENDIF.

    CHECK ls_arec-rec_type = 'D'.

    " Build WHERE clause from key_vals (format: FIELD1=VAL1|FIELD2=VAL2)
    CLEAR: lv_where, lv_pair, lv_kf, lv_kv.
    REFRESH lt_pairs.
    SPLIT ls_arec-key_vals AT '|' INTO TABLE lt_pairs.
    LOOP AT lt_pairs INTO lv_pair.
      SPLIT lv_pair AT '=' INTO lv_kf lv_kv.
      IF lv_where IS NOT INITIAL. lv_where &&= ' AND '. ENDIF.
      lv_where &&= lv_kf && ` EQ '` && lv_kv && `'`.
    ENDLOOP.
    lv_where = |MANDT EQ '{ sy-mandt }' AND | && lv_where.

    WRITE: / |  { ls_arec-table_name } / { ls_arec-key_vals }|.

    IF p_test = ' '.
      DELETE FROM (ls_arec-table_name) WHERE (lv_where).
      IF sy-subrc = 0.
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD'
          EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt.
        PERFORM del_agg_bump USING ls_arec-table_name.
      ELSEIF sy-subrc = 4.
        " Record already gone — still mark as processed in archive
        CALL FUNCTION 'ARCHIVE_DELETE_RECORD'
          EXCEPTIONS OTHERS = 1.
        ADD 1 TO lv_cnt.
        PERFORM del_agg_bump USING ls_arec-table_name.
        WRITE: / |    INFO: already deleted ({ ls_arec-key_vals })|.
      ELSE.
        ADD 1 TO lv_err.
        WRITE: / |    WARN: delete failed sy-subrc={ sy-subrc }|.
      ENDIF.
    ELSE.
      ADD 1 TO lv_cnt.
    ENDIF.
  ENDDO.

  " Log per source table (ZSP26_ARCH_LOG-TABLE_NAME must match ZSP26_* for Monitor)
  IF p_test = ' '.
    DATA: ls_log TYPE zsp26_arch_log.
    IF lines( lt_del_agg ) > 0.
      LOOP AT lt_del_agg INTO ls_del_agg.
        CLEAR ls_log.
        TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error. ENDTRY.
        ls_log-table_name = ls_del_agg-table_name.
        ls_log-action     = 'DELETE'.
        ls_log-rec_count  = ls_del_agg-cnt.
        ls_log-status     = COND #( WHEN lv_err = 0 THEN 'S' ELSE 'W' ).
        ls_log-exec_user  = sy-uname.
        ls_log-exec_date  = sy-datum.
        ls_log-message    = |ADK Delete: { ls_del_agg-cnt } from { ls_del_agg-table_name }. Errors: { lv_err }|.
        INSERT zsp26_arch_log FROM ls_log.
      ENDLOOP.
    ELSEIF lv_err > 0.
      CLEAR ls_log.
      TRY. ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error. ENDTRY.
      ls_log-table_name = 'Z_ARCH_EKK'.
      ls_log-action     = 'DELETE'.
      ls_log-rec_count  = 0.
      ls_log-status     = 'W'.
      ls_log-exec_user  = sy-uname.
      ls_log-exec_date  = sy-datum.
      ls_log-message    = |ADK Delete: { lv_err } read/process error(s), no rows logged per table.|.
      INSERT zsp26_arch_log FROM ls_log.
    ENDIF.
    COMMIT WORK.
  ENDIF.

  WRITE: /.
  WRITE: / |=== Summary: { lv_cnt } deleted / { lv_err } errors ===|.
  IF p_test = 'X'. WRITE: / 'Uncheck Test Mode to actually delete.'. ENDIF.

*&---------------------------------------------------------------------*
FORM del_agg_bump USING pv_tab TYPE tabname.
  FIELD-SYMBOLS: <dg> LIKE LINE OF lt_del_agg.
  READ TABLE lt_del_agg WITH TABLE KEY table_name = pv_tab ASSIGNING <dg>.
  IF sy-subrc = 0.
    <dg>-cnt = <dg>-cnt + 1.
  ELSE.
    CLEAR ls_del_agg.
    ls_del_agg-table_name = pv_tab.
    ls_del_agg-cnt        = 1.
    INSERT ls_del_agg INTO TABLE lt_del_agg.
  ENDIF.
ENDFORM.
