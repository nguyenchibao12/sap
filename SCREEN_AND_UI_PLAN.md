# Kế hoạch màn hình & giao diện — Z_GSP18_SAP15 / ADK Archive

Tài liệu tra cứu nhanh khi vẽ SE51, gán FCODE, pull abapGit hoặc debug. Cập nhật theo repo `sap-project/src`.

---

## 1. Tổng quan object

| Thành phần | Tên | Ghi chú |
|------------|-----|---------|
| Program chính | `Z_GSP18_SAP15_MAIN` | Module pool–style: `INCLUDE` TOP, F01, O01, I01 |
| T-code | `Z_GSP18_SARA` | → program trên, dynpro **0400** (mở đầu), sau đó **0100** |
| Archiving object ADK | `Z_ARCH_EKK` | Write: `Z_ARCH_EKK_WRITE`, Delete: `Z_ARCH_EKK_DELETE`, Read: `Z_ARCH_EKK_READ` |

**Luồng chạy thực tế:** `START-OF-SELECTION` → `CALL SCREEN 0400` (nhập bảng + **Continue**) → **0100** (thao tác Write / Restore / …). **Back** trên 0100 về **0400**. Các màn **0200 / 0300** vẫn **chưa** được `CALL SCREEN` từ MAIN.

**Nguyên tắc vận hành (khớp `PLAN_FINAL.md` §1.4):** Một transaction/report đồ án là **cửa vào** chính; **không** bắt end-user mở **SARA** chuẩn SAP trong luồng hằng ngày. **0400** là nguồn **`GV_TABNAME`**: preview, `SUBMIT` write/delete/read phải **khớp bảng đã chọn** ở đây. **SARA** / **AOBJ** vẫn có thể dùng cho **thiết lập** hệ thống (archive object, kiểm tra file), tách khỏi story người dùng cuối.

---

## 2. Bảng dynpro — vẽ SE51

### 2.0 Screen **0400** — Chọn bảng trước khi vào hub (bắt buộc)

| Mục đích | Nhập `GV_TABNAME` (F4), bấm **Continue** → sang **0100**. |
|----------|-----------------------------------------------------------|

| Loại | Tên (SE51) | Ghi chú |
|------|------------|---------|
| Text | `LBL_STEP1` | Gợi ý bước 1 |
| Text | `LBL_TABNAME` | Nhãn Table Name (F4) |
| Input | `GV_TABNAME` | 30 ký tự, F4 |
| Push | `CONTINUE_BTN` | **Continue** |
| OK | `OK_CODE` | |

| FCODE | Xử lý (`USER_COMMAND_0400`) |
|-------|-------------------------------|
| `BT_CONTINUE` | Kiểm tra bảng khác rỗng → `SET SCREEN 0100` |
| `BACK` / `EXIT` / `CANC` | `LEAVE PROGRAM` |

**Flow:** `z_gsp18_sap15_main.prog.screen_0400.abap` — PBO `status_0400`; PAI `f4_tabname` + `user_command_0400`.

---

### 2.1 Screen **0100** — Hub thao tác (sau 0400)

| Mục đích | Mô tả ngắn |
|----------|------------|
| Hiển thị bảng đã chọn | `GV_TABNAME` **chỉ output** (read-only) |
| Đổi bảng | Nút **Change table** → về **0400** |
| Write ADK | Preview retention/rules → `SUBMIT Z_ARCH_EKK_WRITE` |
| Restore / đọc file .ARC | `SUBMIT Z_ARCH_EKK_READ` |
| Config | SALV trên `ZSP26_ARCH_CFG` |
| Monitor | SALV thống kê (không dùng dynpro 0200 trong code hiện tại) |

**Field / control**

| Loại | Tên (SE51) | Ghi chú |
|------|------------|---------|
| Text | `LBL_CURTAB` | Nhãn Current table |
| Output | `GV_TABNAME` | Chỉ hiển thị (không nhập trực tiếp) |
| Push | `CHANGE_TAB_BTN` | **Change table** |
| Push | `WRITE_BUTTON` | Write |
| Push | `DELETE_BUTTON` | Nhãn **Restore** |
| Push | `MANAGE_BUTTON` | Config |
| Push | `MONITOR_BUTTON` | Monitor |
| OK | `OK_CODE` | |

**Function code (`USER_COMMAND_0100`)**

| Nút / hành động | FCODE | Xử lý |
|-----------------|-------|--------|
| Change table | `BT_CHG_TAB` | `SET SCREEN 0400` |
| Back | `BACK` | `SET SCREEN 0400` |
| Exit / Cancel | `EXIT` / `CANC` | `LEAVE PROGRAM` |
| Write | `BT_WRITE` | `do_archive_write` |
| Restore | `BT_DELETE` | `do_restore_preview` |
| Config | `BT_MANAGE` | `do_config` |
| Monitor | `BT_MONITOR` | `do_monitor` |

> **Lưu ý:** FCODE `BT_DELETE` = **Restore/Read**, không phải Delete ADK.

**PBO / PAI (`screen_0100.abap`):** `status_0100`; **không** F4 trên 0100 (F4 chỉ ở **0400**).

---

### 2.2 Screen **0200** — ALV Grid (tùy chọn / dự phòng)

| Mục đích | Chứa **Custom Control** tên `ALV_CONTAINER` — hiển thị `CL_GUI_ALV_GRID` (`get_data`, `build_fieldcat`, `display_alv`). |
|----------|------------------------------------------------------------------------------------------------------------------------|

**FCODE (`USER_COMMAND_0200`)**

| FCODE | Hành động |
|-------|-----------|
| `BACK` / `EXIT` / `CANC` | Giải phóng container, `SET SCREEN 0100` |
| `BT_REFRESH` | `get_data` + `build_fieldcat` + `display_alv` |

> **Lưu ý:** Trong MAIN **không** có `CALL SCREEN 0200`. Monitor đang dùng **SALV toàn màn hình** từ `do_monitor`. Nếu sau này muốn Monitor trên dynpro: thêm `CALL SCREEN 0200` và nối từ nút Monitor.

---

### 2.3 Screen **0300** — Variant / Start date / Spool

| Mục đích | Màn phụ cho job archive (tương thích SARA): variant report write, `ARCHIVE_ADMIN_SET_START_TIME`, `ARCHIVE_ADMIN_SET_PRINT_PARAMS`. |
|----------|-------------------------------------------------------------------------------------------------------------------------------------|

**Field:** `GV_VARIANT` (variant). Nút Edit, Start Date, Spool.

**FCODE (`USER_COMMAND_0300`)** — code chấp nhận **hai kiểu** tên (nút dynpro vs thanh công cụ):

| Chức năng | FCODE gán trên nút dynpro | FCODE trên GUI status / PF-key (nếu dùng) |
|------------|---------------------------|-------------------------------------------|
| Edit variant | `BT_EDIT` | `EDIT_BTN` |
| Start date | `BT_START` | `START_BTN` |
| Spool | `BT_SPOOL` | `SPOOL_BTN` |
| Về hub | `BACK` | |

PBO: `STATUS_0300`, `INIT_FIELDS_0300` (mặc định `gv_object = Z_ARCH_EKK`).  
PAI: `EXIT_COMMAND` (AT EXIT-COMMAND); `USER_COMMAND_0300`.  
Module `CHECK_VARIANT_0300` có thể gắn `FIELD GV_VARIANT` (trong repo có thể đang comment).

> **Lưu ý:** MAIN **chưa** `CALL SCREEN 0300`. Chỉ cần khi bạn nối luồng job/variant.

---

## 3. GUI status (Menu Painter)

| Status | Dùng cho | Ghi chú |
|--------|----------|---------|
| `STATUS_100` | 0100 (và tạm 0200 trong O01) | Khai báo đủ FCODE dùng (Back, Exit, Cancel, `BT_WRITE`, …) trong function list |
| `STATUS_300` | 0300 | `STATUS_300` trong `status_0300` |

Nếu FCODE trên dynpro **không** có trong danh sách function của status, tùy release có thể cảnh báo hoặc hành vi lạ — nên khai báo đủ.

---

## 4. Selection screen (không phải dynpro SE51)

| Report | Mục đích ngắn |
|--------|----------------|
| `Z_ARCH_EKK_WRITE` | `p_table`, `s_date`, `p_keyf`, `p_test`, nút Show Tables / Show Data |
| `Z_ARCH_EKK_READ` | `p_table`, `p_rest` (restore) |
| `Z_ARCH_EKK_DELETE` | `p_test` — **chỉ chạy đúng ngữ cảnh qua SARA** |

---

## 5. Pull abapGit & activate — checklist

1. Pull repo đầy đủ (program + XML dynpro + CUA + tcode).
2. Activate theo thứ tự: **GUI status** → **Screens** → **Program**.
3. Kiểm tra SE51 screen **0100**: text nút đầu có phải **Write** (theo bản XML mới) hay vẫn Archive (bản cũ trên server).
4. Đóng session SAP, chạy lại `Z_GSP18_SARA`.

**Nếu sau pull vẫn thấy màn cũ:** dynpro trên SAP chưa được ghi đè — activate lại screen 0100, hoặc kiểm tra đúng branch/commit; không paste file `.prog.xml` thủ công vào SE80.

---

## 6. Rủi ro / hạn chế (đọc trước khi demo)

1. **Delete ADK:** `Z_ARCH_EKK_DELETE` cần ngữ cảnh file/session do **SARA** cung cấp — không `SUBMIT` đơn độc như Write.
2. **Tên FCODE `BT_DELETE`:** Dễ hiểu nhầm là xóa DB; thực tế là **Restore** trên UI.
3. **0200 / 0300:** Có trong object nhưng **không** nằm trong luồng `CALL SCREEN` hiện tại — không bắt buộc cho demo “4 nút trên 0100”.
4. **Monitor / Config:** Dùng **SALV** — sau khi đóng list mới về lại 0100 (tùy stack màn hình).

---

## 7. File nguồn trong repo (tham chiếu)

| Nội dung | File |
|----------|------|
| Dynpro + CUA (XML) | `src/z_gsp18_sap15_main.prog.xml` |
| Flow 0400 / 0100 / 0200 / 0300 | `src/z_gsp18_sap15_main.prog.screen_*.abap` |
| PAI | `src/z_gsp18_sap15_i01.prog.abap` |
| PBO | `src/z_gsp18_sap15_o01.prog.abap` |
| Form / SALV / SUBMIT | `src/z_gsp18_sap15_f01.prog.abap` |
| TOP (field global) | `src/z_gsp18_sap15_top.prog.abap` |
| T-code | `src/z_gsp18_sara.tran.xml` |

---

## 8. Vì sao cảm giác “thiếu rất nhiều screen” là đúng

Dự án **không** thiết kế theo kiểu “mỗi bước một dynpro” như **SARA** (nhiều màn chuyển tiếp). Phần lớn chức năng dùng **một hub dynpro (0100)** + **SALV / list toàn màn hình** + **selection screen của report con** + **popup**. Vì vậy so với kỳ vọng “nhiều screen”, bạn sẽ thấy **thiếu** — đó là **khoảng trống thiết kế**, không phải lỗi kích hoạt.

### 8.1 Bản đồ UI thực tế trong repo (tất cả “màn” người dùng thấy)

| # | Loại UI | Object / chỗ gọi | Ghi chú |
|---|---------|------------------|---------|
| 1 | **Dynpro** | `Z_GSP18_SAP15_MAIN` **0400** → **0100** | `CALL SCREEN 0400` từ MAIN; 0100 sau Continue / Back |
| 2 | **Dynpro (có file, chưa nối luồng)** | **0200**, **0300** | Có trong program, **không** `CALL SCREEN` → user **không** vào được từ t-code hiện tại |
| 3 | **SALV** | `do_archive_write` → preview READY/TOO NEW + nút Archive Now | Không phải SE51; đóng list = thoát khỏi “màn” đó |
| 4 | **SALV** | `do_monitor` | Thống kê bảng |
| 5 | **SALV** | `do_config` | Xem `ZSP26_ARCH_CFG` (hướng dẫn sửa bằng tool khác) |
| 6 | **Selection screen** | `Z_ARCH_EKK_WRITE` | Khi `SUBMIT` từ MAIN hoặc chạy SE38 |
| 7 | **Selection screen** | `Z_ARCH_EKK_READ` | Khi Restore / list archive |
| 8 | **List (WRITE / list)** | `Z_ARCH_EKK_DELETE` | Chỉ `p_test` + output list — không phải hub |
| 9 | **Popup** | `POPUP_TO_CONFIRM` (dependency, variant, …) | Không phải dynpro riêng |

**Kết luận:** Trên **MAIN**, bạn chỉ **vẽ/vận hành 1 dynpro “đích”** (0100). Các bước còn lại là **report + SALV** — không xuất hiện trong cây Screen của MAIN.

---

### 8.2 Các “screen” / màn hình còn thiếu nếu muốn gần chuẩn SARA hoặc UX đầy đủ

Dưới đây là **đề xuất** (chưa có trong code); có thể dùng làm backlog vẽ SE51 hoặc mở rộng sau.

| Ưu tiên | Màn (dynpro) đề xuất | Mục đích | Ghi chú / lưu ý |
|--------|----------------------|----------|------------------|
| Cao | **Hub nối Delete** hoặc nút **CALL TRANSACTION 'SARA'** | Sau Write, user chọn session/file và chạy Delete mà không tự gõ SARA | Delete ADK cần ngữ cảnh SARA; hoặc thiết kế màn chọn file + API archive (nặng) |
| Cao | **Nối 0200** vào **Monitor** | Monitor trên dynpro + ALV Grid thay vì chỉ SALV | Code `get_data` / `display_alv` đã có; thiếu `CALL SCREEN 0200` |
| Cao | **Nối 0300** từ hub (nút “Job / Variant”) | Variant, start date, spool cho batch | Flow + `CALL SCREEN 0300` chưa viết |
| Trung bình | **Màn log** (`ZSP26_ARCH_LOG`) | Xem lịch sử ARCHIVE/RESTORE/DELETE theo bảng | Hiện có thể chỉ xem SE16 |
| Trung bình | **Màn maintain rules** (`ZSP26_ARCH_RULE`) | Sửa rule không cần SE16 | `apply_rules` đọc bảng; chưa có UI riêng |
| Trung bình | **Màn dependency** (`ZSP26_ARCH_DEP`) | Cấu hình bảng cha–con | Hiện chỉ popup khi archive |
| Thấp | **Wizard nhiều bước** (Table → Date → Preview → Xác nhận) | Tách SALV preview thành nhiều dynpro | Ảnh hưởng lớn tới code hiện tại |
| Thấp | **Màn chọn file .ARC** (custom) | Thay SARA một phần | Cần hiểu ADK + phiên bản hệ thống |

---

### 8.3 Tóm tắt cho người làm UI

- **Đã có trong object MAIN:** 4 dynpro (**0400, 0100, 0200, 0300**). Luồng t-code: **0400 → 0100**; 0200/0300 vẫn chưa nối.  
- **Cảm giác thiếu screen:** đúng — vì **Write preview, Monitor, Config** không phải dynpro; **Write/Read/Delete** là **report riêng**.  
- **Muốn nhiều screen hơn:** cần **roadmap** (bảng 8.2) + thêm `CALL SCREEN` / transaction phụ + (tuỳ chọn) chuyển SALV → ALV trên dynpro.

---

*Tài liệu này là bản hướng dẫn vận hành/UI; logic nghiệp vụ chi tiết xem thêm `PLAN_FINAL.md` nếu có.*
