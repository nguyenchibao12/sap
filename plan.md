# VALIDATION REPORT & BUG TRACKER
## So sánh PLAN_FINAL vs Code thực tế + Danh sách Bug cần kiểm tra
**Ngày tạo:** 2026-04-11  
**Tác giả:** Review tự động (Claude Code)  
**Dựa trên:** PLAN_FINAL.md (cập nhật 2026-04-04) vs code hiện tại sau pull

---

## MỤC LỤC

1. [Tổng quan so sánh](#1-tổng-quan-so-sánh)
2. [Code đã vượt Plan (Plan lỗi thời)](#2-code-đã-vượt-plan)
3. [Plan mô tả sai so với Code](#3-plan-mô-tả-sai)
4. [Bug cần validate — Nhóm Critical](#4-bug-critical)
5. [Bug cần validate — Nhóm High](#5-bug-high)
6. [Bug cần validate — Nhóm Medium/Low](#6-bug-medium-low)
7. [Việc còn thiếu chưa làm](#7-việc-còn-thiếu)
8. [Checklist tổng hợp](#8-checklist)

---

## 1. Tổng quan so sánh

| Hạng mục | PLAN_FINAL nói | Code thực tế |
|---|---|---|
| Trạng thái tổng | ~90% hoàn thành | **Code vượt plan ~30%** |
| Plan cập nhật lần cuối | 2026-04-04 | Code đã thay đổi đáng kể sau đó |
| Screens | 0100, 0200, 0300 | 0100, 0200, 0300, **0400, 0500, 0600** (3 screens mới) |
| Delete flow | SARA bắt buộc | **Standalone hoàn toàn** (hub + session picker) |
| Archive format | `ty_arch_rec` CHAR4990 | **`ZSTR_ARCH_REC` + PUT_TABLE + JSON chunking** |
| Job scheduling | SUBMIT AND RETURN | **JOB_OPEN + JOB_CLOSE + SM37** |
| Kết luận | PLAN_FINAL **cần cập nhật lại** | Code kiến trúc tốt hơn plan |

---

## 2. Code đã vượt Plan

Những phần code đã implement nhưng PLAN_FINAL không mô tả hoặc mô tả sai:

### 2.1 Screen 0400 — Chọn bảng (Plan §1.4 đề ra nhưng không mô tả kỹ)
- **File:** `src/z_gsp18_sap15_i01.prog.abap` — MODULE user_command_0400
- `gv_hub_allowed` flag: chặn user bypass thẳng vào screen 0100 mà không qua 0400
- `EXPORT arch_tabname TO MEMORY ID 'Z_GSP18_ARCH_TAB'` để Write program đọc đúng bảng

### 2.2 Screen 0500 — Write execution (Plan không có)
- **File:** `src/z_gsp18_sap15_main.prog.screen_0500.abap`
- Màn hình thực thi Write: chọn variant + maintain Start Date + Spool + Preview + bg job
- Plan §4.6 chỉ liệt kê screens 0100/0200/0300 — **0500 hoàn toàn mới**

### 2.3 Screen 0600 — Delete execution (Plan không có)
- **File:** `src/z_gsp18_sap15_main.prog.screen_0600.abap`
- Màn hình thực thi Delete: session picker + test mode + variant + bg job
- Plan §4.6 chỉ liệt kê screens 0100/0200/0300 — **0600 hoàn toàn mới**

### 2.4 Z_ARCH_EKK_WRITE — Kiến trúc mới hoàn toàn
- **File:** `src/z_arch_ekk_write.prog.abap`
- Plan §4.7 mô tả: `ARCHIVE_WRITE_RECORD` + `ty_arch_rec` + `data_json CHAR4990`
- **Thực tế:** `ARCHIVE_PUT_TABLE` + `ZSTR_ARCH_REC` + JSON chunking (255 chars/chunk, rec_type='2' là continuation)
- Chuẩn hơn, generic hơn, không bị giới hạn 4990 chars

### 2.5 Z_ARCH_EKK_DELETE — Standalone (Plan nói SARA bắt buộc)
- **File:** `src/z_arch_ekk_delete.prog.abap`
- Plan §4.8 nói rõ: _"CHỈ chạy qua SARA"_
- **Thực tế:** Standalone hoàn toàn — tự resolve `ARCHIV_KEY` từ `ADMI_FILES`, fallback scan, nhận `p_doc` từ hub

### 2.6 Background Job Scheduling
- **File:** `src/z_gsp18_sap15_f01.prog.abap` — FORM do_archive_write_bg_job, do_archive_delete_bg_job
- Plan mô tả: `SUBMIT ... AND RETURN` trực tiếp
- **Thực tế:** `JOB_OPEN` → `SUBMIT VIA JOB` → `JOB_CLOSE (strtimmed='X')` → traceable qua SM37

### 2.7 Variant Management đầy đủ
- **File:** `src/z_gsp18_sap15_f01.prog.abap` — FORM arch_build_write_var_tech, arch_ensure_write_variant, arch_log_from_write_var
- Plan không mô tả bất kỳ logic variant nào
- Code có: build tên kỹ thuật, auto-create variant, F4 help variant theo bảng

### 2.8 Session Picker Popup
- **File:** `src/z_gsp18_sap15_f01.prog.abap` — FORM arch_del_pick_session_popup
- Plan không có, code implement F4 nội bộ chọn session từ `ADMI_RUN`

### 2.9 ZSTR_ARCH_REC — Generic ADK structure (Plan không có)
- **File:** `src/zstr_arch_rec.tabl.xml` — file mới trong pull mới nhất
- Structure dùng làm payload generic trong PUT_TABLE / GET_TABLE
- Fields: rec_type, table_name, key_vals, data_json (CHAR255), exec_user, exec_ts

---

## 3. Plan mô tả sai so với Code

| # | Điểm sai | Plan §4.x nói | Code thực tế |
|---|---|---|---|
| M1 | BT_WRITE trên 0100 | → gọi `do_archive_write` trực tiếp | → `SET SCREEN 0500` |
| M2 | BT_DELETE / BT_RESTORE | 1 nút `BT_DELETE` → do_restore_preview | 2 nút: `BT_RESTORE` + `BT_ADK_DELETE` (→ 0600) |
| M3 | F4 bảng từ đâu | `f4_tabname` MODULE trên screen 0100 | Chuyển sang screen 0400, 0100 không còn F4 bảng |
| M4 | Delete cần SARA | SARA cung cấp context, không standalone | Hub + session picker + SUBMIT standalone |
| M5 | Archive record format | `ty_arch_rec` CHAR4990, WRITE_RECORD | `ZSTR_ARCH_REC` CHAR255 chunks, PUT_TABLE |
| M6 | Bug #6 (plan) | "OPEN_FOR_DELETE cần SARA context" | Đã fix, standalone OK |
| M7 | do_archive_via_adk | SUBMIT Z_ARCH_EKK_WRITE AND RETURN | Gọi `do_archive_write_bg_job` (bg job) |

---

## 4. Bug Critical

> Các bug này có thể gây **mất dữ liệu** hoặc **archive/delete/restore sai**.

---

### B-C1: `do_restore_from_hub` không truyền session khi restore
- **File:** `src/z_gsp18_sap15_f01.prog.abap` ~dòng 840
- **Mô tả:** SUBMIT z_arch_ekk_read chỉ truyền `p_table` và `p_rest='X'`, **không truyền `p_doc`**. ADK `ARCHIVE_OPEN_FOR_READ` khi không có `archive_document` sẽ mở bất kỳ file available — có thể đọc sai session, restore nhầm dữ liệu.
- **Code hiện tại:**
  ```abap
  SUBMIT z_arch_ekk_read
    WITH p_table = lv_rtab
    WITH p_rest  = 'X'
    AND RETURN.
  ```
- **Nguy cơ:** Nếu có nhiều archive sessions, restore có thể đọc session cũ/sai
- **Validate:** Kiểm tra `gv_f4_sess` hoặc `gs_del_admi-document` có được EXPORT memory trước SUBMIT không

---

### B-C2: `do_archive` (legacy) vẫn tồn tại — DELETE trực tiếp không qua ADK
- **File:** `src/z_gsp18_sap15_f01.prog.abap` ~dòng 849–947
- **Mô tả:** FORM này làm `INSERT zsp26_arch_data` rồi ngay lập tức `DELETE FROM (gv_tabname)` không qua ADK. Nếu vô tình được gọi lại, dữ liệu bị xóa khỏi DB nhưng không có file `.ARC` — không thể restore bằng ADK.
- **Validate:** Grep `PERFORM do_archive` trên toàn bộ F01 và I01 — đảm bảo không có PERFORM nào gọi FORM này (chỉ được gọi từ `lcl_handler::on_cmd` trước đây đã bị thay thế).
- **Status:** Plan §4.3 đã đánh dấu "Dead code ⚠️" — cần xác nhận thực sự không ai gọi

---

### B-C3: `MODIFY` trong restore có thể ghi đè dữ liệu live
- **File:** `src/z_arch_ekk_read.prog.abap` ~dòng 354
- **Mô tả:** `MODIFY (lv_tn_row) FROM <rec_dyn>` là UPSERT — nếu record cùng key đang tồn tại trong DB (chưa xóa, hoặc đã có dữ liệu mới), restore sẽ **ghi đè không cảnh báo**.
- **Validate:** Kiểm tra có check duplicate trước MODIFY không, hoặc đây là intentional (plan §4.9 nói "restore ALL records")
- **Quyết định cần đưa ra:** Dùng `INSERT` (fail nếu trùng) hay `MODIFY` (ghi đè). Hiện tại là MODIFY.

---

## 5. Bug High

---

### B-H1: `process_delete_adk_object` — field name không được validate trước khi đưa vào WHERE
- **File:** `src/z_arch_ekk_delete.prog.abap` ~dòng 504–512
- **Mô tả:** `lv_kf_gen` (tên field lấy từ archive file) được đưa thẳng vào dynamic WHERE string mà không validate. Khác với `append_rules_eq_to_where` (có kiểm tra `CO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789'`), path DELETE không làm vậy.
- **Code:**
  ```abap
  SPLIT lv_pair_gen AT '=' INTO lv_kf_gen lv_kv_gen.
  CHECK lv_kf_gen IS NOT INITIAL.
  lv_kv_esc = lv_kv_gen.
  REPLACE ALL OCCURRENCES OF `'` IN lv_kv_esc WITH `''`.
  lv_where_gen = lv_where_gen && lv_kf_gen && ` EQ '` && lv_kv_esc && `'`.
  ```
- **Nguy cơ:** Field name từ file archive bị tamper → inject SQL vào dynamic WHERE
- **Validate:** Thêm validate field name giống như `append_rules_eq_to_where`

---

### B-H2: Memory ID không được FREE trên các RETURN path lỗi
- **File:** `src/z_gsp18_sap15_f01.prog.abap` ~dòng 585–640 (do_archive_delete_bg_job)
- **Mô tả:** `EXPORT del_admi TO MEMORY ID 'Z_GSP18_ADMI_DEL'` được gọi trước JOB_OPEN. Nếu JOB_OPEN thất bại → `RETURN` mà không `FREE MEMORY ID`. Lần chạy Delete tiếp theo trong cùng session có thể đọc nhầm session cũ.
- **Validate:** Trace mọi RETURN path trong FORM, đếm số lần FREE MEMORY vs số nhánh RETURN

---

### B-H3: `lv_skip_rec_fm` không reset giữa các record trong process_delete_adk_object
- **File:** `src/z_arch_ekk_delete.prog.abap` ~dòng 466–578
- **Mô tả:** `lv_skip_rec_fm TYPE abap_bool VALUE abap_false` là local bool. Sau khi 1 record set nó = `abap_true` (ARCHIVE_DELETE_RECORD không available), tất cả record sau sẽ bỏ qua `mark_deleted_row` và dùng `mark_del_obj` thay thế — có thể mark object quá sớm.
- **Validate:** Kiểm tra `lv_skip_rec_fm` có được CLEAR trong LOOP không

---

### B-H4: `BT_EDIT` trên screen 0600 — cả 2 nhánh IF/ELSE giống nhau
- **File:** `src/z_gsp18_sap15_i01.prog.abap` ~dòng 513–525 (MODULE user_command_0600)
- **Mô tả:** Cả khi `lv_rc_600 = 0` (variant tồn tại) lẫn `<> 0` (không tồn tại), code đều `SUBMIT (gv_prog_del) VIA SELECTION-SCREEN AND RETURN` với cùng params. Hai nhánh không có sự khác biệt thực sự.
- **Code:**
  ```abap
  IF lv_rc_600 = 0.
    SUBMIT (gv_prog_del) WITH p_table = gv_tabname WITH p_test = gv_test_mode VIA SELECTION-SCREEN AND RETURN.
  ELSE.
    SUBMIT (gv_prog_del) WITH p_table = gv_tabname WITH p_test = gv_test_mode VIA SELECTION-SCREEN AND RETURN.
  ENDIF.
  ```
- **Validate:** Xác nhận đây có phải intentional hay dead branch. Nếu variant tồn tại, nên SUBMIT `USING SELECTION-SET gv_variant`.

---

### B-H5: Fallback scan ADMI_FILES dùng `CS` thay vì `=` — false positive
- **File:** `src/z_arch_ekk_delete.prog.abap` ~dòng 213
- **Mô tả:**
  ```abap
  IF lv_doc_db = lv_doc_in OR lv_doc_db CS lv_doc_in OR lv_doc_in CS lv_doc_db.
  ```
  `CS` (contains string) — nếu `lv_doc_in = '001'`, nó sẽ match `'001X'`, `'10012'`, `'X001'` → lấy nhầm session.
- **Thêm vào:** Scan `SELECT * FROM admi_files UP TO 5000 ROWS` không có WHERE — performance risk trên production lớn.
- **Validate:** Cân nhắc chỉ dùng `=` trong fallback, bỏ `CS` match.

---

## 6. Bug Medium/Low

---

### B-M1: `apply_archive_rules` — không có short-circuit với OR
- **File:** `src/z_gsp18_arch_dyn.prog.abap` ~dòng 225–311
- **Mô tả:** Logic duyệt hết tất cả rules dù đã có kết quả. Với OR chain, nếu rule 1 = true thì kết quả đã là true nhưng vẫn tiếp tục evaluate rule 2, 3... Không gây bug về kết quả nhưng lãng phí.
- **Validate:** Test case 3 rules với OR — kết quả có đúng không (functional test)

---

### B-M2: `append_rules_eq_to_where` — guard kiểm tra OR quá rộng
- **File:** `src/z_gsp18_arch_dyn.prog.abap` ~dòng 149–153
- **Mô tả:** Nếu bất kỳ EQ rule nào dùng OR → `RETURN` toàn bộ, bỏ qua tất cả EQ rules. Nếu có 2 EQ rules liên tiếp dùng AND, nhưng 1 EQ rule khác ở cuối dùng OR với non-EQ rule → tất cả EQ rules bị skip.
- **Validate:** Test với config: EQ rule 1 AND EQ rule 2, sau đó OR rule 3 (non-EQ) → kiểm tra rule 1 và 2 có được push vào SQL không

---

### B-M3: `gr_all` và `gr_ready` không được FREE sau SALV preview
- **File:** `src/z_gsp18_sap15_f01.prog.abap` ~dòng 41–43, 61–62
- **Mô tả:** Global `REF TO data` được `CREATE DATA` mỗi lần `do_archive_write` chạy nhưng không được `FREE` sau khi SALV display xong. Nếu user preview nhiều lần, memory heap tích lũy.
- **Validate:** Kiểm tra SAP GC có tự giải phóng khi reassign không, hay cần FREE tường minh

---

### B-M4: `build_where_from_arch_cfg` — `data_field` đưa thẳng vào WHERE string
- **File:** `src/z_gsp18_arch_dyn.prog.abap` ~dòng 107–109
- **Mô tả:**
  ```abap
  cv_where = |{ ps_cfg-data_field } LE '{ lv_hi }'|
  ```
  `data_field` lấy từ `ZSP26_ARCH_CFG` không qua validate thêm sau bước ban đầu. Nếu giá trị trong bảng có ký tự đặc biệt → WHERE string sai.
- **Validate:** `validate_table_against_cfg` đã verify field tồn tại trong DDIC — điều đó có đủ để đảm bảo tên field an toàn không?

---

### B-M5: Stat_ID type mismatch (từ Plan §6 Bug #1)
- **File:** `src/z_gsp18_sap15_f01.prog.abap` — FORM do_monitor
- **Mô tả:** `cl_system_uuid=>create_uuid_x16_static()` trả về `SYSUUID_X16` (RAW16). Nếu `ZSP26_ARCH_STAT-STAT_ID` là CHAR32 → type mismatch runtime.
- **Validate:** SE11 → ZSP26_ARCH_STAT → field STAT_ID → kiểm tra type

---

### B-M6: LOG_ID type inconsistency (từ Plan §6 Bug #2)
- **File:** F01 legacy dùng `x16_static`, ADK programs dùng `c32_static`
- **Validate:** SE11 → ZSP26_ARCH_LOG → field LOG_ID → nếu RAW16: đổi c32→x16 trong Write/Delete/Read; nếu CHAR32: đổi x16→c32 trong F01

---

## 7. Việc còn thiếu chưa làm

### 7.1 SAP System Tasks (không thể làm offline)

| # | Việc | Ưu tiên |
|---|---|---|
| S1 | Paste + Activate: I01, F01, Write, Delete, Read, Create_Variants | **Critical** |
| S2 | AOBJ setup: Z_ARCH_EKK với Write/Delete/Read programs | **Critical** |
| S3 | Chạy Z_ARCH_EKK_CREATE_VARIANTS → 10 write variants | **High** |
| S4 | Chạy ZSP26_LOAD_SAMPLE_DATA → data mẫu | **High** |
| S5 | Fix B-M5 (STAT_ID type) nếu runtime error | Medium |
| S6 | Fix B-M6 (LOG_ID type) nếu runtime error | Medium |

### 7.2 Test Cases chưa được thực hiện (Plan §8)

| TC | Mô tả | Status |
|---|---|---|
| TC-01 | F4 Help trên Table Name field (0400) | [ ] |
| TC-02 | Config View (do_config) | [ ] |
| TC-03 | Archive Preview READY / TOO NEW / RULE FAIL | [ ] |
| TC-04 | Dependency Check Popup | [ ] |
| TC-05 | ADK Write — Test Mode | [ ] |
| TC-06 | ADK Write — Thật (AOBJ required) | [ ] |
| TC-07 | ADK Read — Display Only | [ ] |
| TC-08 | ADK Delete từ hub (không qua SARA) | [ ] |
| TC-09 | ADK Read + Restore | [ ] |
| TC-10 | Monitor Storage Analysis | [ ] |
| TC-11 | Show All Tables button (Z_ARCH_EKK_WRITE) | [ ] |
| TC-12 | Show Eligible Data button | [ ] |
| TC-13 | CREATE_VARIANTS verify | [ ] |

### 7.3 Documentation còn lỗi thời

| # | Việc | Ghi chú |
|---|---|---|
| D1 | PLAN_FINAL.md §4.5 mô tả sai hub commands (BT_WRITE/BT_DELETE) | Cập nhật theo flow 0500/0600 mới |
| D2 | PLAN_FINAL.md §4.7 mô tả sai Write program (WRITE_RECORD, ty_arch_rec) | Cập nhật theo PUT_TABLE, ZSTR_ARCH_REC |
| D3 | PLAN_FINAL.md §4.8 nói Delete SARA-only | Cập nhật: standalone OK |
| D4 | PLAN_FINAL.md §5.1 mô tả sai luồng Delete | Cập nhật theo flow hub→0600→job |
| D5 | PLAN_FINAL.md §4.6 thiếu screen 0500 và 0600 | Thêm mô tả 2 screens mới |
| D6 | Wording trong Demo/Q&A còn nhắc SARA | Đổi thành "archive session / chương trình đồ án" |

---

## 8. Checklist tổng hợp

### Code Bugs — Cần quyết định fix hay document

| # | Bug | File | Priority | Action |
|---|---|---|---|---|
| B-C1 | Restore không truyền session | f01:~840 | **Critical** | Fix: EXPORT session trước SUBMIT read |
| B-C2 | `do_archive` (legacy) DELETE trực tiếp | f01:~849 | **Critical** | Verify không ai gọi; xem xét xóa FORM |
| B-C3 | MODIFY ghi đè data live khi restore | read:~354 | **Critical** | Quyết định INSERT vs MODIFY |
| B-H1 | Field name không validate trong DELETE WHERE | delete:~504 | **High** | Thêm CO validate như append_rules |
| B-H2 | Memory ID không FREE trên lỗi path | f01:~585 | **High** | Thêm FREE trên mọi RETURN path |
| B-H3 | `lv_skip_rec_fm` không reset giữa records | delete:~466 | **High** | Kiểm tra, thêm CLEAR nếu cần |
| B-H4 | BT_EDIT trên 0600 — 2 nhánh giống nhau | i01:~513 | **High** | Fix: nhánh IF dùng SELECTION-SET |
| B-H5 | Fallback ADMI_FILES dùng CS — false positive | delete:~213 | **High** | Đổi CS → = trong match |
| B-M1 | apply_archive_rules không short-circuit | dyn:~225 | Medium | Low risk, chỉ performance |
| B-M2 | append_rules_eq_to_where guard quá rộng | dyn:~149 | Medium | Test với mixed EQ+OR config |
| B-M3 | gr_all/gr_ready không FREE | f01:~41 | Medium | Thêm FREE sau SALV display |
| B-M4 | data_field trực tiếp vào WHERE | dyn:~107 | Medium | Đã validate qua DDIF, low risk |
| B-M5 | STAT_ID type mismatch | f01:do_monitor | Medium | Verify trên SAP |
| B-M6 | LOG_ID type inconsistency | f01/write/delete/read | Medium | Verify trên SAP |

### Validate từng Bug theo thứ tự

```
1. [ ] Grep PERFORM do_archive trong F01 + I01 → xác nhận B-C2
2. [ ] Đọc do_restore_from_hub → kiểm tra có EXPORT session không → B-C1
3. [ ] Trace lv_skip_rec_fm trong process_delete_adk_object → B-H3
4. [ ] Đọc USER_COMMAND_0600 BT_EDIT đoạn IF/ELSE → B-H4
5. [ ] Trace mọi RETURN trong do_archive_delete_bg_job → B-H2
6. [ ] Test apply_archive_rules: 1 rule, 2 rules OR, 2 rules AND → B-M1/B-M2
7. [ ] Kiểm tra fallback scan dòng 213 → B-H5
8. [ ] Verify SE11: ZSP26_ARCH_STAT-STAT_ID, ZSP26_ARCH_LOG-LOG_ID → B-M5/B-M6
9. [ ] Quyết định MODIFY vs INSERT trong restore → B-C3
```

---

## PHỤ LỤC — Luồng thực tế hiện tại (sau pull 2026-04-11)

```
Z_GSP18_SAP15_MAIN
  └─► CALL SCREEN 0400
        User nhập GV_TABNAME → BT_CONTINUE
        EXPORT arch_tabname → MEMORY
        gv_hub_allowed = true
        └─► SET SCREEN 0100

  Screen 0100 (Hub)
    ├─► BT_WRITE      → SET SCREEN 0500
    ├─► BT_RESTORE    → do_restore_from_hub → SUBMIT z_arch_ekk_read p_rest=X (B-C1: thiếu p_doc)
    ├─► BT_ADK_DELETE → SET SCREEN 0600
    ├─► BT_MONITOR    → do_monitor → SALV popup
    └─► BT_MANAGE     → do_config → SALV popup

  Screen 0500 (Write)
    ├─► BT_EDIT       → SUBMIT gv_prog_write VIA SELECTION-SCREEN
    ├─► BT_START      → maintenance_start_date
    ├─► BT_SPOOL      → maintenance_spool_params
    ├─► BT_PREVIEW    → do_archive_write → show_archive_preview → SALV
    │                    [Archive Now button] → lcl_handler::on_cmd
    │                    → check_dependencies → do_archive_via_adk
    │                    → do_archive_write_bg_job → JOB_OPEN/CLOSE
    └─► ONLI (F8)     → do_archive_write_bg_job → JOB_OPEN/CLOSE → SUBMIT Z_ARCH_EKK_WRITE

  Screen 0600 (Delete)
    ├─► BT_ARCH_SEL   → arch_del_pick_session_popup → chọn session từ ADMI_RUN
    ├─► BT_EDIT       → SUBMIT gv_prog_del VIA SELECTION-SCREEN (B-H4: cả 2 nhánh giống nhau)
    ├─► BT_RUN_DELETE → do_archive_delete_job → SUBMIT AND RETURN
    └─► ONLI (F8)     → do_archive_delete_bg_job → JOB_OPEN/CLOSE → SUBMIT Z_ARCH_EKK_DELETE

Z_ARCH_EKK_WRITE
  ARCHIVE_OPEN_FOR_WRITE
  → REGISTER_STRUCTURES (ZSTR_ARCH_REC)
  → NEW_OBJECT
  → build ZSTR_ARCH_REC payload (rec_type D + type 2 chunks)
  → PUT_TABLE
  → SAVE_OBJECT → CLOSE_FILE
  → INSERT ZSP26_ARCH_LOG, COMMIT

Z_ARCH_EKK_DELETE
  Resolve ARCHIV_KEY từ ADMI_FILES (p_doc hoặc MEMORY ID Z_GSP18_ADMI_DEL)
  → ARCHIVE_OPEN_FOR_DELETE
  Path 1: READ_OBJECT → process_delete_adk_object
    → GET_TABLE ZSTR_ARCH_REC → parse key_vals → DELETE FROM DB
  Path 2 (fallback): GET_NEXT_OBJECT → process_delete_adk_object
  → ARCHIVE_CLOSE_FILE
  → flush_arch_log_delete, COMMIT

Z_ARCH_EKK_READ
  ARCHIVE_OPEN_FOR_READ (p_doc optional)
  Path 1: GET_NEXT_OBJECT → read_process_zstr_object
    → GET_TABLE ZSTR_ARCH_REC → merge D + type 2 chunks
  Path 2 (fallback): READ_OBJECT → read_process_zstr_object
  → ARCHIVE_CLOSE_FILE
  Nếu p_rest=X: MODIFY (lv_tn_row) FROM <rec> (B-C3)
  → INSERT ZSP26_ARCH_LOG, COMMIT
```

---

## 9. Dự định tương lai

### Giai đoạn 1 — Hoàn thiện đồ án (làm ngay trước demo)

**1. Fix 3 Critical bugs**

| Bug | Việc cần làm |
|---|---|
| B-C1 | `do_restore_from_hub`: EXPORT session vào memory trước SUBMIT z_arch_ekk_read — không thì restore đọc sai file |
| B-C2 | Xác nhận `PERFORM do_archive` không còn được gọi; xem xét xóa hẳn FORM để tránh gọi nhầm |
| B-C3 | Quyết định rõ MODIFY vs INSERT trong restore — INSERT an toàn hơn (fail nếu trùng key, tránh ghi đè) |

**2. SAP system tasks (bắt buộc, không làm được offline)**
- Activate tất cả programs theo thứ tự plan §7 (I01 → F01 → Write → Delete → Read → Create_Variants)
- Setup AOBJ Z_ARCH_EKK (Write/Delete/Read programs)
- Chạy ZSP26_LOAD_SAMPLE_DATA → data mẫu
- Chạy Z_ARCH_EKK_CREATE_VARIANTS → 10 write variants
- Test TC-01 → TC-13 và tick pass/fail vào mục 7.2

**3. Fix B-H4** — `BT_EDIT` trên screen 0600: nhánh `lv_rc_600 = 0` nên thêm `USING SELECTION-SET gv_variant` thay vì mở selection screen trống

---

### Giai đoạn 2 — Nâng chất lượng (sau khi bảo vệ)

**4. Partial Restore** *(UX improvement lớn nhất)*
- Hiện tại: restore ALL hoặc không restore gì
- Cần làm: thêm checkbox selection trên SALV của z_arch_ekk_read
- Chỉ restore những records được tick chọn

**5. Multi-table archive trong 1 session**
- Hiện tại: mỗi lần archive 1 bảng (1 `p_table`) — archive EKKO thì EKPO vẫn còn nguyên trong DB
- Cần làm: archive cả parent + child trong 1 ADK session
- Nền tảng đã sẵn sàng: ZSTR_ARCH_REC generic có `table_name` field — chỉ cần loop nhiều bảng

**6. Dependency-aware Delete**
- Hiện tại: Delete chỉ xóa bảng được chọn (`p_table`), không tự động xóa child records
- Cần làm: cascade delete theo `ZSP26_ARCH_DEP` (xóa EKPO khi xóa EKKO)
- Phải xóa child trước, parent sau (tránh foreign key violation)

**7. Cập nhật PLAN_FINAL.md** cho khớp code thực tế
- §4.5: sửa BT_WRITE → screen 0500 (không gọi do_archive_write trực tiếp)
- §4.7: sửa Write dùng PUT_TABLE + ZSTR_ARCH_REC (không phải WRITE_RECORD + ty_arch_rec)
- §4.8: sửa Delete là standalone (không phải SARA-only)
- §4.6: thêm mô tả screen 0500 và 0600
- Demo script §9: bỏ mention SARA, thay bằng "hub + job"

---

### Giai đoạn 3 — Production-ready (nếu triển khai thật)

**8. Scheduled archiving tự động**
- Tạo job SM36 chạy định kỳ (hàng đêm/tuần)
- Tự archive tất cả bảng active trong `ZSP26_ARCH_CFG` không cần thao tác thủ công
- Hiện tại chỉ trigger thủ công từ hub

**9. Archive status tracking per record**
- Hiện tại: không biết record nào đã được archive rồi
- Cần thêm: field `ARCH_STATUS` vào source tables hoặc index table riêng
- Ngăn archive trùng lần (record đã archived vẫn có thể bị archive lại)

**10. Authorization check**
- Hiện tại: không có `AUTHORITY-CHECK` trước các thao tác destructive (Delete, Archive)
- Cần thêm: ABAP authorization object riêng cho Archive / Delete / Restore
- Quan trọng nếu deploy production: không phải ai cũng nên được xóa DB

**11. ILM integration (S/4HANA)**
- Nếu hệ thống là S/4HANA: tích hợp SAP Information Lifecycle Management
- Dùng retention policies chuẩn SAP thay vì `ZSP26_ARCH_CFG` custom
- Về lâu dài scalable hơn nhưng phức tạp hơn nhiều

---

### Ma trận ưu tiên

| # | Việc | Effort | Impact | Làm khi nào |
|---|---|---|---|---|
| Fix B-C1, B-C2, B-C3 | Nhỏ | Rất cao | **Trước demo** |
| SAP activate + test TC | Trung bình | Bắt buộc | **Trước demo** |
| Fix B-H4 | Nhỏ | Trung bình | **Trước demo** |
| Partial Restore | Trung bình | Cao | Sau bảo vệ |
| Multi-table session | Lớn | Cao | Sau bảo vệ |
| Dependency-aware Delete | Lớn | Cao | Sau bảo vệ |
| Cập nhật PLAN_FINAL.md | Nhỏ | Trung bình | Sau bảo vệ |
| Scheduled auto archive | Trung bình | Trung bình | Production |
| Authorization check | Nhỏ | Cao | Production |
| ILM integration | Rất lớn | Cao | Production |

> **Điểm mạnh nhất hiện tại:** Architecture generic (ZSTR_ARCH_REC + dynamic table name) đã chuẩn bị sẵn cho multi-table — chỉ cần mở rộng loop ở Write/Delete/Read. Nền tảng tốt để scale lên production.

---

*File này được tạo tự động ngày 2026-04-11. Cập nhật khi có fix hoặc kết quả test.*
