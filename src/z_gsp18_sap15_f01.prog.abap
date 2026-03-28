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
*& Form GET_DATA — Đọc thống kê archive từ ZEKKO_15
*&---------------------------------------------------------------------*
FORM GET_DATA.
  DATA: lt_raw TYPE TABLE OF zekko_15,
        ls_raw TYPE zekko_15.

  CLEAR gt_arch_stat.
  SELECT * FROM zekko_15 INTO TABLE lt_raw.

  LOOP AT lt_raw INTO ls_raw.
    READ TABLE gt_arch_stat ASSIGNING FIELD-SYMBOL(<stat>)
      WITH KEY bukrs = ls_raw-bukrs bsart = ls_raw-bsart.

    IF sy-subrc <> 0.
      APPEND INITIAL LINE TO gt_arch_stat ASSIGNING <stat>.
      <stat>-bukrs    = ls_raw-bukrs.
      <stat>-bsart    = ls_raw-bsart.
      <stat>-min_date = ls_raw-aedat.
      <stat>-max_date = ls_raw-aedat.
    ENDIF.

    <stat>-cnt_total = <stat>-cnt_total + 1.

    IF sy-datum - ls_raw-aedat >= 180.
      <stat>-cnt_ready = <stat>-cnt_ready + 1.
    ELSE.
      <stat>-cnt_new   = <stat>-cnt_new + 1.
    ENDIF.

    IF ls_raw-aedat < <stat>-min_date. <stat>-min_date = ls_raw-aedat. ENDIF.
    IF ls_raw-aedat > <stat>-max_date. <stat>-max_date = ls_raw-aedat. ENDIF.
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

  m_col 'BUKRS'     'Company Code'   12.
  m_col 'BSART'     'Doc. Type'      12.
  m_col 'CNT_TOTAL' 'Total Records'  13.
  m_col 'CNT_READY' 'READY (>=180d)' 13.
  m_col 'CNT_NEW'   'Too New'        10.
  m_col 'MIN_DATE'  'Oldest Date'    12.
  m_col 'MAX_DATE'  'Newest Date'    12.
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
      container_name        = 'CONT_0200'
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
