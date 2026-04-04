# ĐỒ ÁN SAP ABAP — Data Archiving & Purge Management Tool
## Tài liệu kỹ thuật toàn diện — dành cho AI tiếp tục phát triển

**Hệ thống:** SAP ECC / S/4HANA ABAP  
**Archive Object:** `Z_ARCH_EKK`  
**Main Program:** `Z_GSP18_SAP15_MAIN`  
**Ngày cập nhật:** 2026-04-04  
**Trạng thái tổng thể:** ~90% — còn cần activate + test end-to-end

---

## MỤC LỤC

1. [Mô tả đồ án & Requirements](#1-mô-tả-đồ-án--requirements)
2. [Kiến trúc tổng thể](#2-kiến-trúc-tổng-thể)
3. [Custom Tables (DDIC Schema)](#3-custom-tables-ddic-schema)
4. [Chi tiết từng Program/Include](#4-chi-tiết-từng-programinclude)
5. [Luồng nghiệp vụ (Business Flow)](#5-luồng-nghiệp-vụ-business-flow)
6. [Bugs đã biết & Cách fix](#6-bugs-đã-biết--cách-fix)
7. [Hướng dẫn Setup môi trường SAP](#7-hướng-dẫn-setup-môi-trường-sap)
8. [Checklist Test Case đầy đủ](#8-checklist-test-case-đầy-đủ)
9. [Script Demo bảo vệ đồ án](#9-script-demo-bảo-vệ-đồ-án)
10. [Checklist 100% hoàn thành](#10-checklist-100-hoàn-thành)

---

## 1. Mô tả đồ án & Requirements

### 1.1 Mục tiêu đồ án

Xây dựng một **công cụ quản lý lưu trữ và xóa dữ liệu (Data Archiving & Purge Management Tool)** trên nền SAP ABAP sử dụng **ADK (Archive Development Kit)** — bộ công cụ chuẩn của SAP để lưu trữ dữ liệu cũ ra file `.ARC`, xóa khỏi DB, và khôi phục khi cần. Hệ thống phải xử lý 10 loại bảng giao dịch khác nhau (PO, Sales Order, FI Doc, Material Doc, Material Master, Customer Master).

### 1.2 Requirements chính (5 features)

| # | Feature | Mô tả chi tiết | Bảng liên quan |
|---|---|---|---|
| **F1** | **Archive Management Interface** | Màn hình chính quản lý: nhập bảng, preview records đủ điều kiện, nút Archive/Restore/Monitor/Config | Screen 0100, ZSP26_ARCH_CFG |
| **F2** | **ADK Archive Write + Delete** | Ghi records vào file `.ARC` chuẩn SAP ADK, sau đó xóa khỏi DB qua SARA | Z_ARCH_EKK_WRITE, Z_ARCH_EKK_DELETE |
| **F3** | **ADK Archive Read + Restore** | Đọc file `.ARC`, hiển thị danh sách, restore về DB | Z_ARCH_EKK_READ |
| **F4** | **Archive Rules & Dependency Check** | (a) Lọc records theo business rules (field/operator/value). (b) Kiểm tra records con trước khi archive | ZSP26_ARCH_RULE, ZSP26_ARCH_DEP |
| **F5** | **Storage Analysis & Monitoring** | Đếm live records, log archive/restore/delete runs, snapshot vào ZSP26_ARCH_STAT, hiển thị SALV | ZSP26_ARCH_STAT, ZSP26_ARCH_LOG |

### 1.3 Scope: 10 bảng nguồn dữ liệu

| Bảng ZSP26 | Tương đương SAP | Loại | Date Field | Retention |
|---|---|---|---|---|
| ZSP26_EKKO | EKKO | PO Header | AEDAT | 365 ngày |
| ZSP26_EKPO | EKPO | PO Item | AEDAT | (theo EKKO) |
| ZSP26_VBAK | VBAK | SO Header | ERDAT | 365 ngày |
| ZSP26_VBAP | VBAP | SO Item | ERDAT | (theo VBAK) |
| ZSP26_BKPF | BKPF | FI Doc Header | BUDAT | 730 ngày |
| ZSP26_BSEG | BSEG | FI Doc Item | BUDAT | (theo BKPF) |
| ZSP26_MKPF | MKPF | Mat Doc Header | BLDAT | 365 ngày |
| ZSP26_MSEG | MSEG | Mat Doc Item | BLDAT | (theo MKPF) |
| ZSP26_MARA | MARA | Material Master | LAEDA | 730 ngày |
| ZSP26_KNA1 | KNA1 | Customer Master | ERDAT | 730 ngày |

---

## 2. Kiến trúc tổng thể

```
┌─────────────────────────────────────────────────────────────────┐
│                   Z_GSP18_SAP15_MAIN (Report)                   │
│  INCLUDE TOP → INCLUDE F01 → INCLUDE O01 → INCLUDE I01         │
│  START-OF-SELECTION: CALL SCREEN 0100                           │
└──────────┬──────────────────────────────────────────────────────┘
           │ Screen 0100 — Main UI
           │  [Archive Write] [Restore] [Monitor] [Config]
           │
           ├─► [Archive Write] ─────────► do_archive_write (F01)
           │                                  └─► show_archive_preview (F01)
           │                                       ├─► apply_archive_rules (F01) ◄─ ZSP26_ARCH_RULE
           │                                       └─► SALV với ARCH_NOW button
           │                                            └─► lcl_handler::on_cmd (F01)
           │                                                 ├─► check_dependencies (F01) ◄─ ZSP26_ARCH_DEP
           │                                                 └─► SUBMIT Z_ARCH_EKK_WRITE
           │
           ├─► [Restore] ──────────────► do_restore_preview (F01)
           │                               └─► SUBMIT Z_ARCH_EKK_READ
           │
           ├─► [Monitor] ──────────────► do_monitor (F01)
           │                               ├─► SELECT COUNT từ ZSP26_* tables
           │                               ├─► SELECT COUNT từ ZSP26_ARCH_LOG
           │                               ├─► INSERT ZSP26_ARCH_STAT
           │                               └─► SALV popup
           │
           └─► [Config] ───────────────► do_config (F01)
                                          └─► SELECT ZSP26_ARCH_CFG → SALV

ADK Programs (chạy qua SUBMIT hoặc SARA):
  Z_ARCH_EKK_WRITE   → ARCHIVE_OPEN_FOR_WRITE → loop records → ARCHIVE_WRITE_RECORD → ARCHIVE_CLOSE_OBJECT
  Z_ARCH_EKK_DELETE  → ARCHIVE_OPEN_FOR_DELETE (via SARA) → ARCHIVE_GET_NEXT_RECORD → DELETE FROM table → ARCHIVE_DELETE_RECORD
  Z_ARCH_EKK_READ    → ARCHIVE_OPEN_FOR_READ → ARCHIVE_GET_NEXT_RECORD → SALV display → (optional RESTORE)

Support:
  ZSP26_LOAD_SAMPLE_DATA  → load config + rules + deps + transaction data
  Z_ARCH_EKK_CREATE_VARIANTS → tạo 10 SARA variants cho Z_ARCH_EKK_WRITE
```

---

## 3. Custom Tables (DDIC Schema)

### 3.1 ZSP26_ARCH_CFG — Archive Configuration
```
MANDT        MANDT        Client
CONFIG_ID    SYSUUID_X16  UUID (primary key)
TABLE_NAME   TABNAME      Source table (e.g. ZSP26_EKKO)
DESCRIPTION  CHAR50       Human-readable description
RETENTION    INT4         Retention period in days (e.g. 365)
DATA_FIELD   FIELDNAME    Date field used for age calculation (e.g. AEDAT)
IS_ACTIVE    CHAR1        'X' = active, '' = inactive
CREATED_BY   XUBNAME      Created by user
CREATED_ON   DATS         Created date
CHANGED_BY   XUBNAME      Last changed by
CHANGED_ON   DATS         Last changed date
```
**Sample data:** 7 entries (EKKO/VBAK/BKPF/MKPF/MARA/KNA1/EKPO) loaded by ZSP26_LOAD_SAMPLE_DATA

### 3.2 ZSP26_ARCH_RULE — Archive Business Rules
```
MANDT        MANDT        Client
RULE_ID      SYSUUID_X16  UUID (primary key)
CONFIG_ID    SYSUUID_X16  FK → ZSP26_ARCH_CFG-CONFIG_ID
RULE_SEQ     INT1         Sequence (1=first evaluated)
FIELD_NAME   FIELDNAME    Field to check in source table (e.g. LOEKZ)
OPERATOR     CHAR2        EQ/NE/GT/LT/GE/LE/BT
VALUE_LOW    CHAR50       Lower value (or single value for EQ/NE/GT/LT/GE/LE)
VALUE_HIGH   CHAR50       Upper value (only for BT = Between)
AND_OR       CHAR3        'AND' or 'OR' — how this rule chains with next
IS_ACTIVE    CHAR1        'X' = active
```
**Sample data:** 2 rules for ZSP26_EKKO:
- Rule 1: LOEKZ EQ ' ' AND → only archive POs not marked for deletion
- Rule 2: BSTYP EQ 'F'    → only archive standard PO type F

**Logic:** Rules evaluated in RULE_SEQ order. First rule result starts `lv_result`. Each subsequent rule applies AND/OR with `lv_match`. If no rules → record passes (default = archive).

### 3.3 ZSP26_ARCH_DEP — Table Dependencies
```
MANDT          MANDT        Client
DEP_ID         SYSUUID_X16  UUID (primary key)
PARENT_TABLE   TABNAME      Parent table being archived (e.g. ZSP26_EKKO)
CHILD_TABLE    TABNAME      Dependent child table (e.g. ZSP26_EKPO)
DEP_TYPE       CHAR1        'H' = Header-Item relationship
PARENT_FIELD   FIELDNAME    Join field in parent (e.g. EBELN)
CHILD_FIELD    FIELDNAME    Join field in child (e.g. EBELN)
DEL_CASCADE    CHAR1        'X' = warn user if child records exist
```
**Sample data:** 5 entries:
- ZSP26_EKKO → ZSP26_EKPO (EBELN)
- ZSP26_VBAK → ZSP26_VBAP (VBELN)
- ZSP26_BKPF → ZSP26_BSEG (BUKRS), (BELNR), (GJAHR) — compound key

**Logic:** check_dependencies reads all DEP entries for current parent_table, counts total rows in each child_table (SELECT COUNT(*)), shows POPUP_TO_CONFIRM if total > 0.

### 3.4 ZSP26_ARCH_STAT — Storage Statistics Snapshots
```
MANDT        MANDT        Client
STAT_ID      SYSUUID_X16  UUID (primary key)  ← NOTE: may need to be RAW16 type
STAT_DATE    DATS         Date of snapshot
TABLE_NAME   TABNAME      Source table
TOTAL_RECS   INT4         Current live records in source table
ARCH_RECS    INT4         Number of ARCHIVE runs in log (not record count)
REST_RECS    INT4         Number of RESTORE runs in log
DEL_RECS     INT4         Number of DELETE runs in log
LAST_USER    XUBNAME      Last user who performed any action
```
**Written by:** do_monitor FORM (INSERT once per Monitor button click per table)

### 3.5 ZSP26_ARCH_LOG — Operation Log
```
MANDT        MANDT
LOG_ID       SYSUUID_X16  UUID — BUT: in ADK programs declared as CHAR32 via c32_static
ARCH_ID      ZSP26_DE_ARCHID  Archive session ID (optional, not always set)
CONFIG_ID    SYSUUID_X16  FK to config (optional)
TABLE_NAME   TABNAME
ACTION       CHAR10       'ARCHIVE' / 'DELETE' / 'RESTORE'
REC_COUNT    INT4         Records processed
STATUS       CHAR1        'S'=success, 'W'=warning/errors
START_TIME   TIMESTAMPL   (used in F01 legacy code)
END_TIME     TIMESTAMPL   (used in F01 legacy code)
EXEC_USER    XUBNAME
EXEC_DATE    DATS
MESSAGE      CHAR255      Human-readable summary
```
**Writers:** Z_ARCH_EKK_WRITE, Z_ARCH_EKK_DELETE, Z_ARCH_EKK_READ (after restore)

### 3.6 ZSP26_ARCH_DATA — Archive Data Store (Legacy)
```
MANDT        MANDT
ARCH_ID      ZSP26_DE_ARCHID  Session UUID
DATA_SEQ     INT4             Sequence within session
TABLE_NAME   TABNAME
KEY_VALUES   CHAR255          e.g. "EBELN=4500000001"
DATA_JSON    STRING           Serialized record as JSON
ARCHIVED_ON  DATS
ARCHIVED_BY  XUBNAME
ARCH_STATUS  CHAR1            'A'=archived, 'R'=restored
```
**NOTE:** This table is from the OLD non-ADK implementation. The new implementation uses ADK `.ARC` files instead. FORM do_archive (F01:207) writes to this table but is NOT called anymore. Kept for reference only.

### 3.7 ZSP26_ARCH_FMAP — Field Mapping
```
MANDT        MANDT
MAP_ID       SYSUUID_X16
TABLE_NAME   TABNAME
FIELD_NAME   FIELDNAME
FIELD_SEQ    INT4
IS_KEY       CHAR1        'X' = key field
IS_DISPLAY   CHAR1        'X' = show in ALV
IS_SEARCH    CHAR1        'X' = searchable
FIELD_LABEL  CHAR40       Custom column header
```
**Used by:** ZSP26_LOAD_SAMPLE_DATA (loads EKKO/VBAK/BKPF mappings). NOT currently used by main program — available for future enhancement.

### 3.8 Source Data Tables (ZSP26_EKKO, etc.)

**ZSP26_EKKO (PO Header):**
```
MANDT EBELN(10) BUKRS(4) BSTYP(1) BSART(4) LOEKZ(1)
AEDAT(DATS) ERNAM(12) LIFNR(10) EKORG(4) EKGRP(3) WAERS(5) BEDAT(DATS)
```
Key: MANDT + EBELN. Date field: AEDAT. Sample: 20 records, dates sy-datum - (index*35).

**ZSP26_EKPO (PO Item):** Key: MANDT+EBELN+EBELP
**ZSP26_VBAK (SO Header):** Key: MANDT+VBELN, date: ERDAT. 20 records.
**ZSP26_VBAP (SO Item):** Key: MANDT+VBELN+POSNR
**ZSP26_BKPF (FI Header):** Key: MANDT+BUKRS+BELNR+GJAHR, date: BUDAT. 20 records.
**ZSP26_BSEG (FI Item):** Key: MANDT+BUKRS+BELNR+GJAHR+BUZEI
**ZSP26_MKPF (Mat Doc Header):** Key: MANDT+MBLNR+MJAHR, date: BLDAT. 20 records.
**ZSP26_MSEG (Mat Doc Item):** Key: MANDT+MBLNR+MJAHR+ZEILE
**ZSP26_MARA (Material):** Key: MANDT+MATNR, date: LAEDA. 20 records.
**ZSP26_KNA1 (Customer):** Key: MANDT+KUNNR, date: ERDAT. (loaded by sample data)

---

## 4. Chi tiết từng Program/Include

### 4.1 Z_GSP18_SAP15_MAIN (src/z_gsp18_sap15_main.prog.abap)
**Loại:** Executable Report  
**Mục đích:** Entry point — chỉ có INCLUDE statements và START-OF-SELECTION: CALL SCREEN 0100  
**Trạng thái:** ✅ Hoàn chỉnh, không cần sửa

### 4.2 Z_GSP18_SAP15_TOP (src/z_gsp18_sap15_top.prog.abap)
**Loại:** Include  
**Nội dung:**
- `ty_prev`: Preview record (key_vals CHAR100, date_val D, age_days I, status CHAR10, detail CHAR60)
- `ty_arch_row`: Restore row (sel C, arch_id, data_seq, table_name, key_values, archived_on, archived_by, arch_status, data_json STRING)
- `ty_arch_stat`: Monitor summary (table_name, cnt_archived, cnt_restored, cnt_active, last_arch_on, last_arch_by, last_action)
- `ty_log_det`: Log detail (table_name, action, rec_count, status, exec_user, exec_date, message)
- Global data: `gs_cfg TYPE zsp26_arch_cfg`, `gr_all/gr_ready TYPE REF TO data`, `gv_rdy_cnt/gv_skp_cnt TYPE i`
- Field symbols: `<lt_all> <lt_ready> TYPE ANY TABLE`
- `gv_tabname TYPE tabname` — table being processed
- `gv_object TYPE arch_obj-object` — archive object ID (Z_ARCH_EKK) — screen 0300 only
- `lcl_handler CLASS DEFINITION` — event handler for SALV custom button ARCH_NOW

**Trạng thái:** ✅ Hoàn chỉnh

### 4.3 Z_GSP18_SAP15_F01 (src/z_gsp18_sap15_f01.prog.abap)
**Loại:** Include — tất cả FORMs và lcl_handler IMPLEMENTATION  

**FORMs và trạng thái:**

| FORM | Dòng | Mục đích | Trạng thái |
|---|---|---|---|
| lcl_handler::on_cmd | 9-22 | Xử lý SALV button ARCH_NOW: check_dependencies → do_archive_via_adk | ✅ |
| do_archive_write | 28-57 | Đọc config → SELECT all → show_archive_preview | ✅ |
| show_archive_preview | 62-182 | Classify READY/TOO NEW/RULE FAIL → SALV với ARCH_NOW button | ✅ |
| do_archive_via_adk | 187-192 | SUBMIT Z_ARCH_EKK_WRITE với p_table + p_test=' ' | ✅ |
| do_restore_via_adk | 197-202 | SUBMIT Z_ARCH_EKK_READ với p_table + p_rest=' ' | ✅ |
| do_archive | 207-305 | **LEGACY** — ghi vào ZSP26_ARCH_DATA (không còn dùng) | ⚠️ Dead code |
| do_restore_preview | 310-316 | SUBMIT Z_ARCH_EKK_READ | ✅ |
| do_restore_now | 321-389 | **LEGACY** — restore từ ZSP26_ARCH_DATA (không còn dùng) | ⚠️ Dead code |
| do_monitor | 395-509 | Scan ZSP26_ARCH_CFG → count live recs → log stats → SALV | ✅ |
| do_config | 514-566 | SELECT ZSP26_ARCH_CFG → SALV display | ✅ |
| get_data | 571-603 | **LEGACY** — load gt_arch_stat từ log (dùng bởi screen 0200) | ⚠️ Legacy |
| build_fieldcat | 608-627 | **LEGACY** — tạo fieldcat cho screen 0200 ALV | ⚠️ Legacy |
| display_alv | 632-655 | **LEGACY** — hiển thị container ALV trên screen 0200 | ⚠️ Legacy |
| get_archive_programs | 660-670 | Đọc Write/Delete program từ ARCH_OBJ (dùng screen 0300) | ✅ |
| maintenance_spool_params | 675-683 | Thiết lập spool params qua ARCHIVE_ADMIN_SET_PRINT_PARAMS | ✅ |
| maintenance_start_date | 688-696 | Thiết lập start time qua ARCHIVE_ADMIN_SET_START_TIME | ✅ |
| **apply_archive_rules** | **703-770** | **Feature F4a** — evaluate ZSP26_ARCH_RULE cho từng record | ✅ MỚI |
| **check_dependencies** | **778-834** | **Feature F4b** — count child records → POPUP_TO_CONFIRM | ✅ MỚI |

**Logic apply_archive_rules (dòng 703-770):**
```abap
" USING iv_row TYPE any, iv_cfg_id TYPE zsp26_arch_cfg-config_id
" CHANGING cv_pass TYPE abap_bool
" 1. SELECT ZSP26_ARCH_RULE WHERE config_id = iv_cfg_id AND is_active = 'X' ORDER BY rule_seq
" 2. Nếu không có rules → cv_pass = abap_true (RETURN)
" 3. LOOP:
"    ASSIGN COMPONENT ls_rule-field_name OF STRUCTURE iv_row TO <fv>
"    CASE ls_rule-operator: EQ/NE/GT/LT/GE/LE/BT → set lv_match
"    Nếu lv_first → lv_result = lv_match
"    Else if AND_OR = 'OR' → lv_result = true nếu lv_match = true
"    Else (AND) → lv_result = false nếu lv_match = false
" 4. cv_pass = lv_result
```

**Logic check_dependencies (dòng 778-834):**
```abap
" CHANGING cv_ok TYPE abap_bool
" 1. cv_ok = abap_true
" 2. SELECT ZSP26_ARCH_DEP WHERE parent_table = gv_tabname
" 3. LOOP: SELECT COUNT(*) FROM (ls_dep-child_table) → tích lũy lv_total
" 4. Nếu lv_total > 0: POPUP_TO_CONFIRM
"    - Nếu user bấm Cancel (answer <> '1') → cv_ok = abap_false
```

### 4.4 Z_GSP18_SAP15_O01 (src/z_gsp18_sap15_o01.prog.abap)
**Loại:** Include — PBO (Process Before Output) modules  
**Modules:**
- `status_0100`: SET PF-STATUS 'STATUS_100', SET TITLEBAR 'TITLE_100'
- `status_0200`: SET PF-STATUS 'STATUS_100' (reuse), load gt_arch_stat nếu empty
- `display_alv_0200`: PERFORM display_alv (legacy screen 0200)
- `init_fields_0300`: default gv_test_mode='X', gv_det_log='X'
- `status_0300`: SET PF-STATUS 'STATUS_300', SET TITLEBAR 'TITLE_300'

**Trạng thái:** ✅ Hoàn chỉnh (screen 0200 legacy nhưng không gây lỗi)

### 4.5 Z_GSP18_SAP15_I01 (src/z_gsp18_sap15_i01.prog.abap)
**Loại:** Include — PAI (Process After Input) modules  
**Modules:**

**MODULE f4_tabname INPUT (MỚI — dòng 8-35):**
```abap
" Được gọi khi user nhấn F4 trên field GV_TABNAME ở screen 0100
" SELECT DISTINCT table_name FROM zsp26_arch_cfg WHERE is_active = 'X'
" Build help_value table → F4IF_INT_TABLE_VALUE_REQUEST
" → User thấy danh sách 7-10 bảng có config active
```

**MODULE user_command_0100 INPUT:**
- Copy gv_object → gv_tabname (legacy, gv_object thường initial)
- BACK/EXIT/CANC → LEAVE PROGRAM
- BT_WRITE → do_archive_write (nếu gv_tabname không trống)
- BT_DELETE → do_restore_preview
- BT_MONITOR → do_monitor
- BT_MANAGE → do_config

**MODULE user_command_0200 INPUT:** BACK → screen 0100, BT_REFRESH → reload
**MODULE exit_command INPUT:** BACK → 0100, EXIT/CANC → LEAVE PROGRAM
**MODULE check_variant_0300 INPUT:** (commented out trong screen flow)
**MODULE user_command_0300 INPUT:** EDIT_BTN, START_BTN, SPOOL_BTN (screen 0300)

### 4.6 Screens

**Screen 0100 (src/z_gsp18_sap15_main.prog.screen_0100.abap):**
```
PROCESS BEFORE OUTPUT.
  MODULE status_0100.
PROCESS AFTER INPUT.
  FIELD gv_tabname MODULE f4_tabname ON REQUEST.  " F4 help
  MODULE user_command_0100.
```
- Field `gv_tabname` (TYPE tabname): user nhập tên bảng ZSP26_*
- 4 buttons: BT_WRITE, BT_DELETE, BT_MONITOR, BT_MANAGE (defined trong CUA Status STATUS_100)

**Screen 0200 (legacy monitor screen — không còn navigate đến):**
Container ALV with cl_gui_alv_grid. Kept for reference.

**Screen 0300 (SARA scheduler):**
Fields: gv_object, gv_variant, gv_prog_write, gv_prog_del, gv_test_mode, gv_det_log, gv_spool_set, gv_start_date. Buttons: EDIT_BTN, START_BTN, SPOOL_BTN.

### 4.7 Z_ARCH_EKK_WRITE (src/z_arch_ekk_write.prog.abap)
**Mục đích:** ADK Write program — đọc records từ bảng ZSP26_* → ghi vào ADK archive file `.ARC`  
**Chạy qua:** SUBMIT từ main program (Archive Now button) hoặc SARA → Z_ARCH_EKK → Archive

**Selection Screen:**
- `p_table TYPE tabname`: bảng cần archive (OBLIGATORY, default ZSP26_EKKO)
- `s_date`: SELECT-OPTIONS date range (maps tới data_field trong config)
- `p_keyf TYPE char50`: key value filter (optional text filter)
- `p_test TYPE c AS CHECKBOX`: test mode (không ghi file)
- Button [Show All Tables]: hiện SALV với tất cả config + eligible count
- Button [Show Eligible Data]: preview records eligible cho bảng đang chọn

**Luồng START-OF-SELECTION:**
1. `SELECT SINGLE FROM zsp26_arch_cfg` → đọc retention, data_field
2. Tính cutoff date = s_date-high hoặc sy-datum - retention
3. `ARCHIVE_OPEN_FOR_WRITE` (nếu không test mode)
4. `DDIF_FIELDINFO_GET` → lấy key fields
5. Dynamic SELECT với WHERE condition trên data_field
6. (Optional) filter theo p_keyf
7. Loop: build key_vals string, serialize JSON via `/ui2/cl_json=>serialize`, `ARCHIVE_WRITE_RECORD`
8. `ARCHIVE_CLOSE_OBJECT`
9. INSERT ZSP26_ARCH_LOG, COMMIT WORK

**Archive Record Structure (ty_arch_rec):**
```
rec_type   CHAR1   'D' = data record
table_name CHAR30  e.g. 'ZSP26_EKKO'
key_vals   CHAR255 e.g. 'EBELN=4500000001'
data_json  CHAR4990 JSON serialization of full record
```

**Trạng thái:** ✅ Hoàn chỉnh. KEY FIXES đã thực hiện:
- s_date (SELECT-OPTIONS) thay p_datefr/p_dateto
- uuid c32_static thay x16_static (log_id type)
- REFRESH lt_cfg/lt_cfgraw trước mỗi SHOW_TBLS
- SELECT COUNT INTO @lv_cnt2 (với @)

### 4.8 Z_ARCH_EKK_DELETE (src/z_arch_ekk_delete.prog.abap)
**Mục đích:** ADK Delete program — đọc archive file → xóa records khỏi DB  
**QUAN TRỌNG:** CHỈ chạy qua SARA (không standalone). ARCHIVE_OPEN_FOR_DELETE không có ARCHIV_OBJ parameter — SARA tự truyền context.

**Luồng START-OF-SELECTION:**
1. `ARCHIVE_OPEN_FOR_DELETE` (không có EXPORTING — SARA provides context)
2. Loop: `ARCHIVE_GET_NEXT_RECORD` → check rec_type = 'D'
3. Parse key_vals: SPLIT AT '|' → SPLIT AT '=' → build WHERE clause
4. `WHERE = MANDT EQ '...' AND EBELN EQ '...'`
5. `DELETE FROM (ls_arec-table_name) WHERE (lv_where)`
6. `ARCHIVE_DELETE_RECORD` để đánh dấu record đã xử lý
7. Handle sy-subrc=4 (record đã xóa trước) → vẫn ARCHIVE_DELETE_RECORD
8. INSERT ZSP26_ARCH_LOG, COMMIT WORK

**Trạng thái:** ✅ Hoàn chỉnh. KEY FIXES:
- Bỏ EXPORTING archiv_obj trong ARCHIVE_OPEN_FOR_DELETE
- REFRESH lt_pairs trước mỗi record (tránh stale data)
- Handle sy-subrc=4 separately
- uuid c32_static

### 4.9 Z_ARCH_EKK_READ (src/z_arch_ekk_read.prog.abap)
**Mục đích:** ADK Read/Restore program — đọc archive file → hiển thị / restore về DB

**Selection Screen:**
- `p_table TYPE tabname`: filter theo bảng (default ZSP26_EKKO)
- `p_rest TYPE c AS CHECKBOX`: nếu check → restore ALL records về DB

**Luồng:**
1. `ARCHIVE_OPEN_FOR_READ EXPORTING archiv_obj = 'Z_ARCH_EKK'`
2. Loop: `ARCHIVE_GET_NEXT_RECORD` → filter rec_type='D' và p_table
3. Build lt_disp table
4. `ARCHIVE_CLOSE_OBJECT`
5. SALV: cột TABLE_NAME, KEY_VALS (DATA_JSON hidden)
6. Nếu p_rest='X': loop lt_disp → CREATE DATA → `/ui2/cl_json=>deserialize` → INSERT
7. COMMIT WORK, INSERT ZSP26_ARCH_LOG

**Trạng thái:** ✅ Hoàn chỉnh. KEY FIXES:
- `CONV string(ls_disp-data_json)` trước deserialize (CHAR4990 → STRING)
- uuid c32_static
- Restore ALL records (không check selection)

### 4.10 Z_ARCH_EKK_CREATE_VARIANTS (src/z_arch_ekk_create_variants.prog.abap)
**Mục đích:** One-time utility — tạo 10 SARA variants cho Z_ARCH_EKK_WRITE  
**Chạy:** SE38 → Execute 1 lần duy nhất  
**Output:** 10 variants tên = table name, p_table = table name, p_test = 'X'  
**Trạng thái:** ✅ Hoàn chỉnh (file mới)

### 4.11 ZSP26_LOAD_SAMPLE_DATA (src/zsp26_load_sample_data.prog.abap)
**Mục đích:** Load toàn bộ dữ liệu test vào hệ thống  
**Output:**
- ZSP26_ARCH_CFG: 7 configs (EKKO/VBAK/BKPF/MKPF/MARA/KNA1/EKPO)
- ZSP26_ARCH_RULE: 2 rules cho EKKO (LOEKZ EQ ' ' AND BSTYP EQ 'F')
- ZSP26_ARCH_DEP: 5 dependencies (EKKO→EKPO, VBAK→VBAP, BKPF→BSEG x3)
- ZSP26_ARCH_FMAP: field mappings cho EKKO/VBAK/BKPF
- ZSP26_EKKO: 20 records (index 1-20, dates = sy-datum - index*35)
- ZSP26_EKPO: ~40-50 records (2-3 per PO)
- ZSP26_VBAK: 20 records (dates = sy-datum - index*30)
- ZSP26_VBAP: 40 records (2 per SO)
- ZSP26_BKPF: 20 records (dates = sy-datum - index*40)
- ZSP26_BSEG: ~40-50 records
- ZSP26_MKPF: 20 records (dates = sy-datum - index*35)
- ZSP26_MSEG: 40 records
- ZSP26_MARA: 20 records (dates = sy-datum - index*40)

**Trạng thái:** ✅ Không thay đổi

---

## 5. Luồng nghiệp vụ (Business Flow)

### 5.1 Luồng Archive đầy đủ

```
User → SE38 → Z_GSP18_SAP15_MAIN → Execute
  ↓
Screen 0100: nhập "ZSP26_EKKO" → nhấn [Archive Write]
  ↓
do_archive_write:
  1. SELECT ZSP26_ARCH_CFG WHERE table_name='ZSP26_EKKO' AND is_active='X'
     → gs_cfg: retention=365, data_field='AEDAT'
  2. CREATE DATA gr_all TYPE TABLE OF ZSP26_EKKO
     ASSIGN gr_all->* TO <lt_all>
     SELECT * FROM ZSP26_EKKO INTO TABLE <lt_all>
     → 20 records
  3. PERFORM show_archive_preview
  ↓
show_archive_preview:
  - Lấy key field đầu tiên (EBELN) qua DDIF_FIELDINFO_GET
  - LOOP AT <lt_all>:
      ASSIGN COMPONENT 'EBELN' → key_vals
      ASSIGN COMPONENT 'AEDAT' → date_val
      age_days = sy-datum - date_val
      PERFORM apply_archive_rules USING <row> gs_cfg-config_id CHANGING lv_rule_pass
        → Rule 1: LOEKZ EQ ' '? (LOEKZ=' ' for most → PASS)
        → Rule 2: BSTYP EQ 'F'? (all records have BSTYP='F' → PASS)
        → lv_rule_pass = abap_true
      IF lv_rule_pass = false → status='RULE FAIL'
      ELSEIF age_days >= 365 → status='READY', INSERT <lt_ready>
      ELSE → status='TOO NEW'
  - Hiện SALV với header "READY: X  TOO NEW: Y  RULE FAIL: Z"
  - SALV có button [Archive Now]
  ↓
User nhấn [Archive Now]
  ↓
lcl_handler::on_cmd (e_salv_function='ARCH_NOW'):
  PERFORM check_dependencies:
    SELECT ZSP26_ARCH_DEP WHERE parent_table='ZSP26_EKKO'
    → 1 entry: child_table='ZSP26_EKPO'
    SELECT COUNT(*) FROM ZSP26_EKPO → lv_total = 40+
    POPUP_TO_CONFIRM: "ZSP26_EKKO has 40 child records. Archive anyway?"
    User nhấn "Yes, Archive" → cv_ok = abap_true
  PERFORM do_archive_via_adk:
    SUBMIT Z_ARCH_EKK_WRITE
      WITH p_table = 'ZSP26_EKKO'
      WITH p_test  = ' '
      AND RETURN
  ↓
Z_ARCH_EKK_WRITE (START-OF-SELECTION):
  ARCHIVE_OPEN_FOR_WRITE archiv_obj='Z_ARCH_EKK'
  DDIF_FIELDINFO_GET tabname='ZSP26_EKKO' → key fields: EBELN
  SELECT * FROM ZSP26_EKKO WHERE AEDAT <= cutoff_date
  LOOP: serialize JSON, ARCHIVE_WRITE_RECORD
  ARCHIVE_CLOSE_OBJECT object_count=N
  INSERT ZSP26_ARCH_LOG (action='ARCHIVE')
  COMMIT WORK
  ↓
SARA → Z_ARCH_EKK → Delete (hoặc schedule job):
  ARCHIVE_OPEN_FOR_DELETE (SARA context)
  Loop: ARCHIVE_GET_NEXT_RECORD → DELETE FROM ZSP26_EKKO
  ARCHIVE_DELETE_RECORD
  INSERT ZSP26_ARCH_LOG (action='DELETE')
  COMMIT WORK
```

### 5.2 Luồng Restore

```
Screen 0100: "ZSP26_EKKO" → [Restore]
  ↓
do_restore_preview → SUBMIT Z_ARCH_EKK_READ WITH p_table='ZSP26_EKKO' WITH p_rest=' '
  ↓
Z_ARCH_EKK_READ:
  ARCHIVE_OPEN_FOR_READ archiv_obj='Z_ARCH_EKK'
  Loop: GET_NEXT_RECORD → filter p_table='ZSP26_EKKO'
  ARCHIVE_CLOSE_OBJECT
  SALV: TABLE_NAME | KEY_VALS (DATA_JSON hidden)
  (nếu p_rest='X': deserialize JSON → INSERT ZSP26_EKKO)
```

### 5.3 Luồng Monitor

```
[Monitor] → do_monitor:
  SELECT ZSP26_ARCH_CFG → tất cả tables (kể cả inactive)
  LOOP:
    SELECT COUNT(*) FROM ZSP26_EKKO (dynamic)  → live_recs
    SELECT COUNT FROM ZSP26_ARCH_LOG WHERE action='ARCHIVE' → arch_runs
    SELECT COUNT FROM ZSP26_ARCH_LOG WHERE action='RESTORE' → rest_runs
    SELECT COUNT FROM ZSP26_ARCH_LOG WHERE action='DELETE'  → del_runs
    SELECT last log entry → last_action, last_date, last_user
    INSERT ZSP26_ARCH_STAT (snapshot)
  COMMIT WORK
  SALV: TABLE_NAME | LIVE_RECS | ARCH_RUNS | REST_RUNS | DEL_RUNS | LAST_DATE | RETENTION | ACTIVE
```

---

## 6. Bugs đã biết & Cách fix

### Bug 1 — STAT_ID type mismatch (MỨC ĐỘ: MEDIUM)

**Mô tả:** Trong `do_monitor` (F01:460):
```abap
TRY. ls_stat-stat_id = cl_system_uuid=>create_uuid_x16_static( ).
```
`create_uuid_x16_static()` trả về `SYSUUID_X16` (RAW16). Nếu `ZSP26_ARCH_STAT-STAT_ID` là `CHAR32` hoặc khác → type mismatch lúc runtime.

**Fix:** Kiểm tra type của STAT_ID trong SE11:
- Nếu RAW16 (SYSUUID_X16) → giữ nguyên `x16_static`
- Nếu CHAR32 → đổi sang `create_uuid_c32_static()`

**Code fix (F01 dòng 460):**
```abap
" Nếu STAT_ID là CHAR32:
TRY. ls_stat-stat_id = cl_system_uuid=>create_uuid_c32_static( ).
" Nếu STAT_ID là RAW16 (giữ nguyên):
TRY. ls_stat-stat_id = cl_system_uuid=>create_uuid_x16_static( ).
```

---

### Bug 2 — ZSP26_ARCH_LOG-LOG_ID type inconsistency (MỨC ĐỘ: LOW)

**Mô tả:** 
- Trong F01 `do_restore_now` (dòng 369): dùng `lv_log_id TYPE sysuuid_x16` + `x16_static` — nhất quán nội bộ.
- Trong ADK programs (WRITE/DELETE/READ): dùng `ls_log-log_id` với `c32_static` — giả định LOG_ID là CHAR32.
- Nếu ZSP26_ARCH_LOG-LOG_ID là RAW16 → ADK programs sẽ lỗi.

**Fix:** Kiểm tra SE11 → ZSP26_ARCH_LOG → field LOG_ID:
- Nếu RAW16: đổi `c32_static` → `x16_static` trong WRITE/DELETE/READ
- Nếu CHAR32: đổi `x16_static` → `c32_static` trong F01 legacy code

---

### Bug 3 — BT_MONITOR trong I01 gọi do_monitor (SALV popup) — không navigate screen 0200 (MỨC ĐỘ: LOW)

**Mô tả:** Screen 0200 với container ALV không còn được navigate đến. `do_monitor` mới dùng SALV popup trực tiếp. Không có lỗi nhưng screen 0200 là orphaned code.

**Không cần fix** — chức năng Monitor hoạt động đúng qua SALV popup.

---

### Bug 4 — MODULE f4_tabname đã được thêm vào I01 (ĐÃ FIX)

**Mô tả:** Screen 0100 PAI có `FIELD gv_tabname MODULE f4_tabname ON REQUEST` nhưng module chưa tồn tại → runtime error khi F4.

**Fix đã thực hiện:** Thêm `MODULE f4_tabname INPUT` vào đầu I01 (dòng 8-35):
- SELECT DISTINCT table_name FROM zsp26_arch_cfg WHERE is_active='X'
- F4IF_INT_TABLE_VALUE_REQUEST → user thấy danh sách bảng

---

### Bug 5 — SALV display() blocking trong AT SELECTION-SCREEN (thiết kế đúng, không phải bug)

**Mô tả:** `lo_alv->display()` trong `show_archive_preview` là modal (blocking). Sau khi user đóng SALV → control trả về. Event handler `on_cmd` được gọi khi user nhấn ARCH_NOW **trong** SALV. Đây là thiết kế đúng của SALV event model.

---

### Bug 6 — ARCHIVE_OPEN_FOR_DELETE không có ARCHIV_OBJ (ĐÃ FIX)

**Lý do:** FM `ARCHIVE_OPEN_FOR_DELETE` không có parameter EXPORTING ARCHIV_OBJ — SARA truyền context tự động qua memory. Nếu chạy standalone → `MESSAGE 'Cannot open archive for delete. Run via SARA.' TYPE 'A'`.

---

### Bug 7 — config_id type mismatch trong apply_archive_rules (CẦN KIỂM TRA)

**Mô tả:** FORM signature:
```abap
FORM apply_archive_rules
  USING iv_row    TYPE any
        iv_cfg_id TYPE zsp26_arch_cfg-config_id
```
Tham số `gs_cfg-config_id` được truyền từ `show_archive_preview`:
```abap
PERFORM apply_archive_rules USING <row> gs_cfg-config_id CHANGING lv_rule_pass.
```
Nếu `zsp26_arch_cfg-config_id` là `SYSUUID_X16` (RAW16) → SELECT trong FORM:
```abap
SELECT * FROM zsp26_arch_rule INTO TABLE @lt_rules
  WHERE config_id = @iv_cfg_id AND is_active = 'X'
```
Điều này phải nhất quán với kiểu trong ZSP26_ARCH_RULE-CONFIG_ID. Không có vấn đề gì nếu cả hai cùng type.

---

## 7. Hướng dẫn Setup môi trường SAP

### Bước 1 — Paste & Activate programs (THEO THỨ TỰ)

**Nguyên tắc:** Activate includes trước main program. Compile sẽ thất bại nếu include chưa active.

```
1. SE38 → Z_GSP18_SAP15_I01    → Change → Xóa hết → Paste → Save → Activate (Ctrl+F3)
2. SE38 → Z_GSP18_SAP15_F01    → Change → Xóa hết → Paste → Save → Activate
3. SE38 → Z_ARCH_EKK_WRITE     → Change → Xóa hết → Paste → Save → Activate
4. SE38 → Z_ARCH_EKK_DELETE    → Change → Xóa hết → Paste → Save → Activate
5. SE38 → Z_ARCH_EKK_READ      → Change → Xóa hết → Paste → Save → Activate
6. SE38 → Z_ARCH_EKK_CREATE_VARIANTS → Create mới (Executable) → Paste → Activate
7. SE38 → Z_GSP18_SAP15_MAIN   → Check (Ctrl+F2) — không cần paste
```

**Lưu ý:** Nếu Extended Program Check báo warning về TYPE of parameter → kiểm tra Bug 7 ở trên.

### Bước 2 — Kiểm tra AOBJ (Archive Object Configuration)

```
Transaction: AOBJ (hoặc SARA → Customizing)
Object: Z_ARCH_EKK

Các field cần điền:
  Write Program:  Z_ARCH_EKK_WRITE
  Delete Program: Z_ARCH_EKK_DELETE
  Read Program:   Z_ARCH_EKK_READ
  Object Type:    (để trống hoặc theo chuẩn hệ thống)
```

Nếu chưa có → New entries → Save → khi đó SARA mới nhận diện archive object.

### Bước 3 — SARA Customizing (Variant cho Delete program)

```
SARA → Z_ARCH_EKK → Customizing → Delete tab
  - Xóa bỏ hoặc không điền gì nếu không dùng variant cụ thể
  - Hoặc tạo variant tên 'DEFAULT' cho Z_ARCH_EKK_DELETE
    (vào SE38 → Z_ARCH_EKK_DELETE → Goto → Variants → Create)
    Parameter: p_test = 'X' (safe default)
```

### Bước 4 — Tạo SARA Variants cho Write program

```
SE38 → Z_ARCH_EKK_CREATE_VARIANTS → Execute (F8)

Kết quả: tạo 10 variants trong Z_ARCH_EKK_WRITE
Xác minh:
  SARA → Z_ARCH_EKK → Archive → nhấn F4 bên cạnh Variant
  → Phải thấy danh sách: ZSP26_EKKO, ZSP26_EKPO, ZSP26_VBAK...
```

### Bước 5 — Load Sample Data

```
SE38 → ZSP26_LOAD_SAMPLE_DATA → Execute (F8)

Kết quả mong đợi (in ra màn hình):
  >>> Loading ZSP26_ARCH_CFG...
    - ZSP26_EKKO config inserted
    - ZSP26_VBAK config inserted
    - ZSP26_BKPF config inserted
    ...
  Config loaded: 7 entries
  >>> Loading ZSP26_ARCH_RULE...
  Rules loaded: 2 entries
  >>> Loading ZSP26_ARCH_DEP...
  Dependencies loaded: 5 entries
  >>> Loading ZSP26_EKKO / ZSP26_EKPO sample data...
  EKKO loaded: 20 entries
  EKPO loaded: ~40-50 entries
  ...

Verify:
  SE16 → ZSP26_ARCH_CFG → thấy 7 entries is_active='X'
  SE16 → ZSP26_EKKO → thấy 20 records
  SE16 → ZSP26_ARCH_RULE → thấy 2 rules
  SE16 → ZSP26_ARCH_DEP → thấy 5 dependencies
```

---

## 8. Checklist Test Case đầy đủ

### TC-01: F4 Help trên Table Name field
```
Điều kiện: ZSP26_ARCH_CFG có entries, I01 đã activate với f4_tabname module
Bước:
  1. SE38 → Z_GSP18_SAP15_MAIN → F8
  2. Screen 0100 hiện
  3. Click vào ô Table Name → nhấn F4 (hoặc click search icon)
Kỳ vọng:
  - Popup danh sách hiện: ZSP26_BKPF, ZSP26_EKKO, ZSP26_EKPO, ZSP26_KNA1, ZSP26_MARA, ZSP26_MKPF, ZSP26_VBAK (7 items)
  - Chọn ZSP26_EKKO → field được điền
Pass/Fail: [ ]
```

### TC-02: Config View (do_config)
```
Điều kiện: ZSP26_ARCH_CFG có dữ liệu
Bước:
  1. Main screen → nhấn [Config/Manage]
Kỳ vọng:
  - SALV popup "ARCHIVE CONFIG — 7 entries"
  - Columns: Table Name | Description | Retention (days) | Date Field | Active
  - Không thấy CONFIG_ID, MANDT (hidden)
  - 7 rows: EKKO(365), VBAK(365), BKPF(730), MKPF(365), MARA(730), KNA1(730), EKPO
Pass/Fail: [ ]
```

### TC-03: Archive Preview với READY/TOO NEW/RULE FAIL
```
Điều kiện: ZSP26_EKKO có 20 records, config retention=365
  - Records index 1-10: aedat = sy-datum - (index*35) → ~35-350 days old
  - Records index 11-20: aedat = sy-datum - (index*35) → ~385-700 days old
  - Record index 5: LOEKZ='L' (marked for deletion) → RULE FAIL
  - Records BSTYP='F' → all pass Rule 2
Bước:
  1. Table Name: ZSP26_EKKO → [Archive Write]
Kỳ vọng:
  - SALV Preview hiện với header: "PREVIEW — ZSP26_EKKO  [ Total: 20  READY: X  TOO NEW: Y  RULE FAIL: 1 / Retention: 365d / Field: AEDAT ]"
  - Records index 11-20: status=READY (age >= 365)
  - Records index 1-10 nhỏ: status=TOO NEW
  - Record index 5: status=RULE FAIL (LOEKZ='L' → Rule 1 fails: LOEKZ EQ ' ')
  - Nút [Archive Now] visible (vì có READY records)
Pass/Fail: [ ]
```

### TC-04: Dependency Check Popup
```
Điều kiện: ZSP26_ARCH_DEP có entry EKKO→EKPO, ZSP26_EKPO có records
Bước:
  1. Từ SALV Preview → nhấn [Archive Now]
Kỳ vọng:
  - Popup: "Dependency Check Warning"
    "ZSP26_EKKO has dependent child records (X total). Archive anyway?"
    Buttons: "Yes, Archive" | "Cancel"
  - Nhấn Cancel: popup đóng, không archive, message "Archive cancelled"
  - Nhấn "Yes, Archive": đóng popup, submit Z_ARCH_EKK_WRITE
Pass/Fail: [ ]
```

### TC-05: ADK Write — Test Mode
```
Điều kiện: Z_ARCH_EKK_WRITE activated
Bước:
  1. SE38 → Z_ARCH_EKK_WRITE → F8
  2. p_table = ZSP26_EKKO, p_test = X (checked)
  3. s_date: để trống (sẽ dùng cutoff = sy-datum - 365)
  4. Execute
Kỳ vọng:
  - In: "=== ADK Write: ZSP26_EKKO ==="
  - In: "Date To    : 20250404" (sy-datum - 365)
  - In: "*** TEST MODE — no data written to archive ***"
  - In: "Records eligible: 10" (records index 11-20)
  - In: "[TEST] EBELN=4500000011" ... etc
  - In: "=== Summary ===" Written: 10, Errors: 0
  - KHÔNG ghi file archive thật
  - KHÔNG ghi ZSP26_ARCH_LOG
Pass/Fail: [ ]
```

### TC-06: ADK Write — Thật (không test mode)
```
Điều kiện: AOBJ configured, TC-05 passed
Bước:
  1. SE38 → Z_ARCH_EKK_WRITE → F8
  2. p_table = ZSP26_EKKO, p_test = ' ' (unchecked)
  3. Execute
Kỳ vọng:
  - Message: "Cannot open archive Z_ARCH_EKK. Check AOBJ/SARA config." → ERROR nếu AOBJ chưa config
  - Nếu AOBJ OK: in "Written to archive: 10 records"
  - ZSP26_ARCH_LOG có 1 entry mới: action='ARCHIVE', rec_count=10, status='S'
  - File archive .ARC được tạo trên server (SARA → Z_ARCH_EKK → Management → thấy file)
Pass/Fail: [ ]
```

### TC-07: ADK Read — Display Only
```
Bước:
  1. SE38 → Z_ARCH_EKK_READ → F8
  2. p_table = ZSP26_EKKO, p_rest = ' ' (unchecked)
  3. Execute
Kỳ vọng:
  - Popup: chọn archive file (nếu nhiều files)
  - SALV: "ARCHIVED RECORDS — ZSP26_EKKO  [ 10 records ]"
  - Columns: Table Name | Key Values | (Data JSON hidden)
  - 10 rows với key_vals = "EBELN=4500000011" etc
  - Không restore về DB
Pass/Fail: [ ]
```

### TC-08: SARA Delete
```
Điều kiện: TC-06 đã tạo archive file, AOBJ config đúng
Bước:
  1. SARA → Z_ARCH_EKK → Delete
  2. Chọn archive file từ TC-06
  3. Variant: ZSP26_EKKO (hoặc để trống, set p_test='X' trước)
  4. Execute với p_test='X' trước
Kỳ vọng TEST MODE:
  - In: "=== ADK Delete: Z_ARCH_EKK ==="
  - In: "*** TEST MODE — no records deleted ***"
  - In: list records: "ZSP26_EKKO / EBELN=4500000011" etc
  - In: "=== Summary: 10 deleted / 0 errors ===" (test count, không xóa thật)
Sau khi xác nhận OK → bỏ p_test → chạy thật:
  - SE16 → ZSP26_EKKO → 20-10=10 records còn lại
  - ZSP26_ARCH_LOG: 1 entry mới action='DELETE'
Pass/Fail: [ ]
```

### TC-09: ADK Read + Restore
```
Điều kiện: TC-08 đã xóa records, archive file còn tồn tại
Bước:
  1. SE38 → Z_ARCH_EKK_READ → F8
  2. p_table = ZSP26_EKKO, p_rest = 'X' (checked)
Kỳ vọng:
  - Các records được restore về ZSP26_EKKO
  - SE16 → ZSP26_EKKO → 20 records (10 + 10 restored)
  - ZSP26_ARCH_LOG: 1 entry mới action='RESTORE'
  - Message: "Restored 10 records to ZSP26_EKKO. Errors: 0"
Pass/Fail: [ ]
```

### TC-10: Monitor — Storage Analysis
```
Bước:
  1. Main screen → [Monitor]
Kỳ vọng (sau khi đã chạy TC-06, TC-08, TC-09):
  - SALV: "STORAGE ANALYSIS & MONITORING — 7 tables — 20260404"
  - Row ZSP26_EKKO: LIVE_RECS=20, ARCH_RUNS=1, REST_RUNS=1, DEL_RUNS=1, LAST_ACTION=RESTORE/DELETE
  - Các tables khác: LIVE_RECS=20, ARCH_RUNS=0, REST_RUNS=0, DEL_RUNS=0
  - ZSP26_ARCH_STAT: 7 new rows với stat_date=sy-datum
Pass/Fail: [ ]
```

### TC-11: Show All Tables button trong Z_ARCH_EKK_WRITE
```
Bước:
  1. SE38 → Z_ARCH_EKK_WRITE → F8 (chỉ mở selection screen)
  2. Nhấn [Show All Tables] button
Kỳ vọng:
  - SALV popup "Archive Configuration — All Active Tables"
  - Columns: Table Name | Date Field | Retention (Days) | Active | Eligible Records | Cutoff Date
  - 7 rows, cột Eligible Records hiển thị số records cũ hơn cutoff
Pass/Fail: [ ]
```

### TC-12: Show Eligible Data button trong Z_ARCH_EKK_WRITE
```
Bước:
  1. Z_ARCH_EKK_WRITE selection screen
  2. p_table = ZSP26_EKKO
  3. Nhấn [Show Eligible Data]
Kỳ vọng:
  - SALV "[PREVIEW] ZSP26_EKKO — ... — 10 records"
  - Hiện actual records từ ZSP26_EKKO đủ điều kiện
Pass/Fail: [ ]
```

### TC-13: Variant tạo bởi CREATE_VARIANTS
```
Bước:
  1. SE38 → Z_ARCH_EKK_CREATE_VARIANTS → Execute
Kỳ vọng:
  - In: "✓ Variant ZSP26_EKKO created — Archive PO Header (EKKO)"
  - ... 10 lines tương tự
  - "=== Done. Check SARA → Z_ARCH_EKK → Archive → Variant (F4) ==="
  Verify: SARA → Archive → F4 bên Variant → thấy 10 variants
Pass/Fail: [ ]
```

---

## 9. Script Demo bảo vệ đồ án

### Thứ tự demo (20-25 phút)

**Phần 1: Giới thiệu kiến trúc (3 phút)**
```
Mở slide / sơ đồ kiến trúc:
"Hệ thống bao gồm:
- Main program Z_GSP18_SAP15_MAIN với 4 chức năng chính
- Archive Development Kit (ADK) với 3 programs: Write, Delete, Read
- 7 bảng config + 10 bảng nguồn dữ liệu
- 5 bảng hỗ trợ: ARCH_CFG, ARCH_RULE, ARCH_DEP, ARCH_STAT, ARCH_LOG"
```

**Phần 2: Cấu hình Archive (2 phút)**
```
1. SE38 → Z_GSP18_SAP15_MAIN → Execute
2. [Config/Manage] → SALV với 7 cấu hình
   Giải thích: "Table ZSP26_EKKO được archive sau 365 ngày
   tính từ ngày tạo (AEDAT). Config cho phép quản trị viên
   điều chỉnh retention period mà không cần sửa code."
```

**Phần 3: Business Rules & Dependency (5 phút)**
```
3. F4 trên Table Name → chọn ZSP26_EKKO
4. [Archive Write]
   Giải thích Preview:
   "Hệ thống phân loại 20 records thành 3 nhóm:
   - READY: đủ tuổi retention, qua rules → archive được
   - TOO NEW: chưa đủ tuổi retention
   - RULE FAIL: vi phạm business rules (e.g. LOEKZ='L' = đã đánh dấu xóa, không nên archive)"

5. [Archive Now]
   Popup dependency:
   "Trước khi archive, hệ thống kiểm tra bảng con.
   ZSP26_EKKO có 40 records con trong ZSP26_EKPO.
   Cảnh báo này giúp tránh mất tính toàn vẹn dữ liệu."
   → Nhấn Yes, Archive
```

**Phần 4: ADK Write (3 phút)**
```
6. Z_ARCH_EKK_WRITE chạy (SUBMIT AND RETURN)
   "Records được serialize thành JSON và ghi vào file .ARC
   chuẩn SAP ADK. File này an toàn, có checksum,
   và SARA quản lý lifecycle."
7. SE16 → ZSP26_ARCH_LOG → thấy entry ARCHIVE
```

**Phần 5: SARA Delete (3 phút)**
```
8. SARA → Z_ARCH_EKK → Delete → chọn file → TEST MODE trước
   "Delete program đọc lại file .ARC, xác minh từng record,
   sau đó xóa khỏi DB. TEST MODE cho phép preview trước."
9. Chạy thật → SE16 → ZSP26_EKKO → còn 10 records
```

**Phần 6: Restore (3 phút)**
```
10. Main screen → [Restore] hoặc Z_ARCH_EKK_READ
    p_rest = ' ' → xem danh sách archived records
    p_rest = 'X' → restore
    SE16 → ZSP26_EKKO → 20 records trở lại
    "ADK đảm bảo dữ liệu không bao giờ mất — 
    chỉ di chuyển ra file .ARC và restore được bất kỳ lúc nào."
```

**Phần 7: Storage Analysis (3 phút)**
```
11. [Monitor]
    "Storage Analysis quét tất cả 7 bảng có config,
    đếm live records, tổng hợp số lần archive/restore/delete,
    và ghi snapshot vào ZSP26_ARCH_STAT.
    Cho phép quản trị viên theo dõi xu hướng theo thời gian."
12. SE16 → ZSP26_ARCH_LOG → thấy đủ ARCHIVE/DELETE/RESTORE entries
```

**Phần 8: Q&A (câu hỏi thường gặp)**
```
Q: Tại sao dùng ADK thay vì tự ghi vào bảng custom?
A: ADK là chuẩn SAP: có file checksum, lifecycle management qua SARA,
   tích hợp với SAP ILM, được chứng nhận compliance.

Q: Làm sao hệ thống biết field nào là ngày archive?
A: Config trong ZSP26_ARCH_CFG-DATA_FIELD, admin có thể thay đổi
   mà không cần sửa code (generic architecture).

Q: Business rules hoạt động như thế nào?
A: Mỗi bảng có rules riêng trong ZSP26_ARCH_RULE với logic AND/OR.
   Ví dụ EKKO: chỉ archive nếu LOEKZ='' AND BSTYP='F'.

Q: Nếu archive nhầm có khôi phục được không?
A: Có, Z_ARCH_EKK_READ với p_rest='X' restore hoàn toàn.
   Log ghi đầy đủ trong ZSP26_ARCH_LOG.
```

---

## 10. Checklist 100% hoàn thành

### Code (đã xong trên local)
- [x] F01: lcl_handler::on_cmd với check_dependencies trước archive
- [x] F01: show_archive_preview với RULE FAIL status
- [x] F01: apply_archive_rules (EQ/NE/GT/LT/GE/LE/BT operators, AND/OR chain)
- [x] F01: check_dependencies (SELECT COUNT child tables, POPUP_TO_CONFIRM)
- [x] F01: do_monitor enhanced (scan all configs, ZSP26_ARCH_STAT snapshot, SALV)
- [x] I01: MODULE f4_tabname (F4 help từ ZSP26_ARCH_CFG)
- [x] Z_ARCH_EKK_WRITE: SELECT-OPTIONS s_date, 2 buttons, uuid c32
- [x] Z_ARCH_EKK_DELETE: bỏ ARCHIV_OBJ, fix REFRESH lt_pairs, uuid c32
- [x] Z_ARCH_EKK_READ: CONV string, uuid c32, restore ALL
- [x] Z_ARCH_EKK_CREATE_VARIANTS: file mới, 10 variants

### Cần làm trong hệ thống SAP
- [ ] Paste + Activate I01 (có f4_tabname mới)
- [ ] Paste + Activate F01 (có apply_archive_rules, check_dependencies, do_monitor)
- [ ] Paste + Activate Z_ARCH_EKK_WRITE
- [ ] Paste + Activate Z_ARCH_EKK_DELETE
- [ ] Paste + Activate Z_ARCH_EKK_READ
- [ ] Create + Paste + Activate Z_ARCH_EKK_CREATE_VARIANTS
- [ ] Check AOBJ: Z_ARCH_EKK với Write/Delete/Read programs
- [ ] Chạy Z_ARCH_EKK_CREATE_VARIANTS → 10 SARA variants
- [ ] Chạy ZSP26_LOAD_SAMPLE_DATA → data mẫu
- [ ] Fix Bug 1 (STAT_ID type) nếu runtime error
- [ ] Fix Bug 2 (LOG_ID type) nếu runtime error

### Test
- [ ] TC-01: F4 help Table Name
- [ ] TC-02: Config view
- [ ] TC-03: Archive Preview READY/TOO NEW/RULE FAIL
- [ ] TC-04: Dependency Check Popup
- [ ] TC-05: ADK Write TEST MODE
- [ ] TC-06: ADK Write thật
- [ ] TC-07: ADK Read display
- [ ] TC-08: SARA Delete
- [ ] TC-09: ADK Read + Restore
- [ ] TC-10: Monitor Storage Analysis
- [ ] TC-11: Show All Tables button
- [ ] TC-12: Show Eligible Data button
- [ ] TC-13: CREATE_VARIANTS verify

---

## PHỤ LỤC — Cấu trúc File Project

```
sap-project/
├── PLAN_FINAL.md                              ← tài liệu này
├── src/
│   ├── z_gsp18_sap15_main.prog.abap          ← main report (entry point)
│   ├── z_gsp18_sap15_top.prog.abap           ← global types/data/class def
│   ├── z_gsp18_sap15_f01.prog.abap           ← ALL FORMs + lcl_handler impl ← THAY ĐỔI NHIỀU
│   ├── z_gsp18_sap15_i01.prog.abap           ← PAI modules (f4_tabname MỚI) ← THAY ĐỔI
│   ├── z_gsp18_sap15_o01.prog.abap           ← PBO modules (không thay đổi)
│   ├── z_gsp18_sap15_main.prog.screen_0100.abap  ← screen 0100 flow
│   ├── z_gsp18_sap15_main.prog.screen_0200.abap  ← screen 0200 (legacy)
│   ├── z_gsp18_sap15_main.prog.screen_0300.abap  ← screen 0300 (SARA sched)
│   ├── z_arch_ekk_write.prog.abap            ← ADK Write ← THAY ĐỔI
│   ├── z_arch_ekk_delete.prog.abap           ← ADK Delete ← THAY ĐỔI
│   ├── z_arch_ekk_read.prog.abap             ← ADK Read/Restore ← THAY ĐỔI
│   ├── z_arch_ekk_create_variants.prog.abap  ← Variant utility (MỚI)
│   └── zsp26_load_sample_data.prog.abap      ← Sample data loader
```

---

*Tài liệu được tạo bởi Claude Code (Anthropic) — 2026-04-04*  
*Dự án: Đồ án SAP ABAP — Data Archiving & Purge Management Tool*
