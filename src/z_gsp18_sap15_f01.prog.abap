*&---------------------------------------------------------------------*
*& Include Z_GSP18_SAP15_F01
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form GET_ARCHIVE_PROGRAMS
*&---------------------------------------------------------------------*
FORM GET_ARCHIVE_PROGRAMS.
  " --- BẮT ĐẦU PHẦN SỬA ĐỔI ---
  " Sửa tên cột APPL_DEL thành APPL_DELE (đây là tên chuẩn trong bảng ARCH_OBJ)
  "SELECT SINGLE appl_writ, appl_dele
  "FROM arch_obj
  "INTO (@gv_prog_write, @gv_prog_del)
  "WHERE object = @gv_object.
  SELECT SINGLE REORGA_PRG, DELETE_PRG
  FROM ARCH_OBJ
  INTO (@GV_PROG_WRITE, @GV_PROG_DEL)
  WHERE OBJECT = @GV_OBJECT.

  IF SY-SUBRC <> 0.
    CLEAR: GV_PROG_WRITE, GV_PROG_DEL.
    MESSAGE 'Archiving Object không hợp lệ hoặc chưa cấu hình trong AOBJ' TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
  " --- KẾT THÚC PHẦN SỬA ĐỔI ---
ENDFORM.

*&---------------------------------------------------------------------*
*& Form POPUP_SELECT_VARIANT
*&---------------------------------------------------------------------*
FORM POPUP_SELECT_VARIANT USING P_PROGRAM TYPE PROGRAMM.
  DATA: LV_SEL_VARIANT TYPE VARIANT.

  IF P_PROGRAM IS INITIAL.
    MESSAGE 'Không tìm thấy chương trình tương ứng cho Object này' TYPE 'E'.
    RETURN.
  ENDIF.

  " --- BẮT ĐẦU PHẦN SỬA ĐỔI ---
  " Sửa tên cột REPID thành NAME (đây là tên cột chuẩn trong bảng TRDIR)
  SELECT SINGLE NAME FROM TRDIR INTO @DATA(LV_EXISTS) WHERE NAME = @P_PROGRAM.
  IF SY-SUBRC <> 0.
    MESSAGE 'Chương trình ' && P_PROGRAM && ' chưa được cài đặt (SE38)' TYPE 'E'.
    RETURN.
  ENDIF.
  " --- KẾT THÚC PHẦN SỬA ĐỔI ---

  CALL FUNCTION 'RS_VARIANT_CATALOG'
    EXPORTING
      REPORT              = P_PROGRAM
    IMPORTING
      SEL_VARIANT         = LV_SEL_VARIANT
    EXCEPTIONS
      NO_REPORT           = 1
      REPORT_NOT_EXTENDED = 2
      NOT_EXECUTED        = 3
      INVALID_REPORT_TYPE = 4
      NO_VARIANTS         = 5
      OTHERS              = 6.

  IF SY-SUBRC = 0.
    GV_VARIANT = LV_SEL_VARIANT.
  ELSEIF SY-SUBRC = 5.
    MESSAGE 'Vui lòng tạo ít nhất 1 Variant cho ' && P_PROGRAM TYPE 'W'.
    CLEAR GV_VARIANT.
  ELSE.
    CLEAR GV_VARIANT.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form MAINTENANCE_SPOOL_PARAMS
*&---------------------------------------------------------------------*
FORM maintenance_spool_params.
* --- BẮT ĐẦU PHẦN THÊM MỚI ---
  CALL FUNCTION 'ARCHIVE_ADMIN_SET_PRINT_PARAMS'
    EXPORTING
      object             = gv_object
    EXCEPTIONS
      no_write_privilege = 1
      others             = 2.
  IF sy-subrc = 0.
    gv_spool_set = 'X'.
    MESSAGE 'Đã thiết lập tham số máy in (Spool)' TYPE 'S'.
  ENDIF.
* --- KẾT THÚC PHẦN THÊM MỚI ---
ENDFORM.

*&---------------------------------------------------------------------*
*& Form ARCHIVE_SELECTION
*&---------------------------------------------------------------------*
FORM ARCHIVE_SELECTION.
*  " --- BẮT ĐẦU PHẦN SỬA ĐỔI ---
*  " Sử dụng cấu trúc as_selected_files (Table Type chuẩn) thay cho tên struct lạ
*  DATA: lt_selected_files TYPE as_selected_files.
*
*  CALL FUNCTION 'ARCHIVE_SELECT_FILES'
*    EXPORTING
*      object                 = gv_object
*    TABLES
*      selected_files         = lt_selected_files
*    EXCEPTIONS
*      no_files_selected      = 1
*      no_files_found         = 2
*      object_not_found       = 3
*      OTHERS                 = 4.
*
*  IF sy-subrc <> 0.
*    MESSAGE 'Bạn phải chọn ít nhất một archive file' TYPE 'S' DISPLAY LIKE 'E'.
*    CLEAR gv_variant.
*  ENDIF.
*  " --- KẾT THÚC PHẦN SỬA ĐỔI ---
  " Khai báo biến để nhận ID (Handle) của phiên làm việc Archive
  DATA: LV_ARCHIVE_HANDLE TYPE SY-TABIX.

  " Gọi hàm chuẩn của SAP để tự động mở Popup cho người dùng chọn file Archive
  CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
    EXPORTING
      OBJECT                  = GV_OBJECT
    IMPORTING
      ARCHIVE_HANDLE          = LV_ARCHIVE_HANDLE
    EXCEPTIONS
      FILE_ALREADY_OPEN       = 1
      FILE_IO_ERROR           = 2
      INTERNAL_ERROR          = 3
      NO_FILES_AVAILABLE      = 4
      OBJECT_NOT_FOUND        = 5
      OPEN_ERROR              = 6
      NOT_AUTHORIZED          = 7
      ARCH_ENV_NOT_CUSTOMIZED = 8
      OTHERS                  = 9.

  IF SY-SUBRC <> 0.
    " Nếu người dùng bấm Cancel ở màn hình Popup hoặc hệ thống lỗi
    MESSAGE 'Bạn chưa chọn file Archive nào hoặc có lỗi hệ thống!' TYPE 'S' DISPLAY LIKE 'E'.
    CLEAR GV_VARIANT.
    RETURN. " Thoát khỏi FORM nếu không chọn file
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form build_fieldcat
*&---------------------------------------------------------------------*
*& text
*&---------------------------------------------------------------------*
*& -->  p1        text
*& <--  p2        text
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Form GET_DATA — Đọc thống kê archive từ ZSP26_ARCH_LOG + ZSP26_ARCH_DATA
*&---------------------------------------------------------------------*
FORM GET_DATA.
  DATA: lv_cnt     TYPE i,
        lv_tabname TYPE zsp26_arch_log-table_name.

  CLEAR gt_arch_stat.

  " Lấy danh sách bảng có log
  SELECT DISTINCT table_name FROM zsp26_arch_log
    INTO TABLE @DATA(lt_tables).

  LOOP AT lt_tables INTO DATA(ls_tab).
    lv_tabname = ls_tab-table_name.
    APPEND INITIAL LINE TO gt_arch_stat ASSIGNING FIELD-SYMBOL(<stat>).
    <stat>-table_name = lv_tabname.

    " Tổng archived
    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @lv_tabname AND action = 'ARCHIVE'.
    <stat>-cnt_archived = lv_cnt.

    " Tổng restored
    SELECT COUNT(*) FROM zsp26_arch_log INTO @lv_cnt
      WHERE table_name = @lv_tabname AND action = 'RESTORE'.
    <stat>-cnt_restored = lv_cnt.

    " Active records in archive
    SELECT COUNT(*) FROM zsp26_arch_data INTO @lv_cnt
      WHERE table_name = @lv_tabname AND arch_status = 'A'.
    <stat>-cnt_active = lv_cnt.

    " Last activity (SELECT + ORDER BY — không dùng SINGLE)
    SELECT exec_date, exec_user, action FROM zsp26_arch_log
      INTO (@<stat>-last_arch_on, @<stat>-last_arch_by, @<stat>-last_action)
      WHERE table_name = @lv_tabname
      ORDER BY exec_date DESCENDING.
      EXIT.
    ENDSELECT.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form BUILD_FIELDCAT — Định nghĩa cột cho ALV Screen 0200
*&---------------------------------------------------------------------*
FORM BUILD_FIELDCAT.
  DATA: ls_fc TYPE lvc_s_fcat.
  CLEAR gt_fcat_200.

  DEFINE m_col.
    CLEAR ls_fc.
    ls_fc-fieldname = &1.
    ls_fc-coltext   = &2.
    ls_fc-outputlen = &3.
    APPEND ls_fc TO gt_fcat_200.
  END-OF-DEFINITION.

  m_col 'TABLE_NAME'   'Table Name'         20.
  m_col 'CNT_ARCHIVED' 'Total Archived'     14.
  m_col 'CNT_RESTORED' 'Total Restored'     14.
  m_col 'CNT_ACTIVE'   'Active in Archive'  18.
  m_col 'LAST_ARCH_ON' 'Last Activity Date' 18.
  m_col 'LAST_ARCH_BY' 'Last By'            12.
  m_col 'LAST_ACTION'  'Last Action'        12.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form DISPLAY_ALV — Hiển thị ALV trong container CONT_0200 (Screen 0200)
*&---------------------------------------------------------------------*
FORM DISPLAY_ALV.
  " Giải phóng đối tượng cũ khi vào lại màn hình
  IF go_cont_200 IS BOUND.
    go_cont_200->free( ).
    CLEAR: go_cont_200, go_alv_200.
  ENDIF.

  CREATE OBJECT go_cont_200
    EXPORTING
      container_name        = 'ALV_CONTAINER'
    EXCEPTIONS
      cntl_error            = 1
      cntl_system_error     = 2
      create_error          = 3
      lifetime_error        = 4
      OTHERS                = 5.

  IF sy-subrc <> 0.
    MESSAGE 'Lỗi tạo container ALV (kiểm tra CONT_0200 trong SE51)' TYPE 'S'
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CREATE OBJECT go_alv_200
    EXPORTING
      i_parent          = go_cont_200
    EXCEPTIONS
      error_cntl_create = 1
      error_cntl_init   = 2
      error_cntl_link   = 3
      error_dp_create   = 4
      OTHERS            = 5.

  IF sy-subrc <> 0. RETURN. ENDIF.

  CALL METHOD go_alv_200->set_table_for_first_display
    CHANGING
      it_outtab       = gt_arch_stat
      it_fieldcatalog = gt_fcat_200.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form CHECK_AND_CREATE_VARIANT
*&---------------------------------------------------------------------*
FORM check_and_create_variant.
  DATA: lv_answer TYPE c,
        lv_rc     TYPE sy-subrc. " Biến phụ để nhận giá trị trả về

  IF gv_variant IS INITIAL.
    MESSAGE 'Vui lòng nhập tên Variant' TYPE 'I'.
    RETURN.
  ENDIF.

  " --- BẮT ĐẦU PHẦN SỬA ĐỔI ---
  " Thay đổi sy-subrc thành lv_rc để tránh lỗi biên dịch
  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      report  = gv_prog_write
      variant = gv_variant
    IMPORTING
      r_c     = lv_rc. " Sử dụng biến trung gian thay vì sy-subrc

  IF lv_rc <> 0.
  " --- KẾT THÚC PHẦN SỬA ĐỔI ---

    " Nếu không tồn tại, hiển thị Popup hỏi người dùng
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar       = 'Variant không tồn tại'
        text_question  = 'Variant này chưa có. Bạn có muốn tạo mới không?'
        text_button_1  = 'Có'
        text_button_2  = 'Không'
      IMPORTING
        answer         = lv_answer.

    IF lv_answer = '1'.
      " Gọi màn hình tạo Variant của SAP
      CALL FUNCTION 'RS_VARIANT_MAINTAIN'
        EXPORTING
          curr_report = gv_prog_write
          curr_variant = gv_variant
          action      = 'MAINT'
        EXCEPTIONS
          others      = 1.
    ENDIF.
  ELSE.
    " Nếu đã tồn tại, gọi vào màn hình Edit
    IF ok_code = 'BT_EDIT' OR ok_code = 'CHECK_VARI'.
       CALL FUNCTION 'RS_VARIANT_MAINTAIN'
        EXPORTING
          curr_report = gv_prog_write
          curr_variant = gv_variant
          action      = 'MAINT'.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form MAINTENANCE_START_DATE
*&---------------------------------------------------------------------*
FORM maintenance_start_date.
* --- BẮT ĐẦU PHẦN THÊM MỚI ---
  CALL FUNCTION 'ARCHIVE_ADMIN_SET_START_TIME'
    EXPORTING
      object             = gv_object
    EXCEPTIONS
      no_write_privilege = 1
      others             = 2.
  IF sy-subrc = 0.
    gv_start_date = 'X'.
    MESSAGE 'Đã thiết lập thời gian bắt đầu' TYPE 'S'.
  ENDIF.
* --- KẾT THÚC PHẦN THÊM MỚI ---
ENDFORM.
*&---------------------------------------------------------------------*
*& Form EXECUTE_WRITE_JOB
*&---------------------------------------------------------------------*
FORM execute_write_job.
  IF gv_variant IS INITIAL OR gv_start_date IS INITIAL OR gv_spool_set IS INITIAL.
    MESSAGE 'Bạn phải nhập Variant, Start Date và Spool Parameter' TYPE 'E'.
    RETURN.
  ENDIF.

  " Thực hiện gọi SUBMIT qua SARA handle hoặc Job Open như bước trước
  " Ở đây dùng Submit đơn giản để minh họa:
  SUBMIT (gv_prog_write) USING SELECTION-SET gv_variant
    WITH p_test = gv_test_mode
    WITH p_log  = gv_det_log
    VIA JOB 'ARCH_WRITE' NUMBER '1' " Thực tế cần lấy Jobcount từ JOB_OPEN
    AND RETURN.

  MESSAGE 'Chương trình Write đã được lập lịch' TYPE 'S'.
ENDFORM.
