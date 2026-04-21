# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an **abapGit** repository for SAP system `ZSP26GSP18_SAP15` — a data archiving hub for SAP transparent tables using ADK (Archive Development Kit). It is managed via transaction `Z_GSP18_SARA` and deployed by syncing with abapGit in SE38/ZABAPGIT.

There are no build, lint, or test commands — all development, activation, and testing happen inside the SAP system via SE38, SE80, or ADT. Changes pushed here are pulled into SAP via abapGit.

## Architecture

### Three-Layer Structure

```
src/
├── hub/      — Module pool UI (Z_GSP18_SAP15_MAIN): screens, user interaction, job scheduling
├── adk/      — ADK programs: write (archive), read/restore, delete (purge from DB)
└── util/     — Setup, registration, sample/demo data loaders
```

Plus `src/z_gsp18_arch_dyn.prog.abap` (shared include) used by both `hub/` and `adk/`.

### Module Pool — `Z_GSP18_SAP15_MAIN`

Organized as four includes:
- **TOP** (`z_gsp18_sap15_top.prog.abap`) — global types, data declarations, local class definitions (no implementations)
- **F01** (`z_gsp18_sap15_f01.prog.abap`) — class implementations + all `FORM` subroutines; also includes `z_gsp18_arch_dyn`
- **O01** (`z_gsp18_sap15_o01.prog.abap`) — PBO (screen output) modules
- **I01** (`z_gsp18_sap15_i01.prog.abap`) — PAI (screen input / user command) modules

Entry point: `START-OF-SELECTION` in `z_gsp18_sap15_main.prog.abap` — checks admin status, then routes to screen 0100 (admin) or 0400 (table-selection for non-admins).

### Screen Flow

```
0400 (table select) ──BT_CONTINUE──► 0100 (main hub)
                                           │
              ┌────────────────────────────┼────────────────────┐
              ▼                            ▼                     ▼
          0500/0300                     0200                  0600
        (write/schedule)             (monitor ALV)          (delete/purge)
              │
          0700 (admin mgmt)
          0800 (register table popup)
          0810 (config list → calls 0800)
```

- Screen 0400 is the entry for non-admins; admins bypass it directly to 0100.
- `gv_hub_allowed` flag guards screen 0100 from direct TSTC DYPNO access.
- Selected table name is passed between screens via `EXPORT/IMPORT` to `MEMORY ID 'Z_GSP18_ARCH_TAB'`.

### ADK Programs

All three share the archive object `Z_ARCH_EKK`:
- **`Z_ARCH_EKK_WRITE`** — dynamic SELECT using `ZSP26_ARCH_CFG` config + optional `ZSP26_ARCH_RULE` EQ rules; writes to ADK file, logs to `ZSP26_ARCH_LOG`
- **`Z_ARCH_EKK_READ`** — reads archive sessions, optionally restores via `MODIFY` (upsert); supports both structured `GET_TABLE` and legacy flat JSON fallback
- **`Z_ARCH_EKK_DELETE`** — physical DB delete of records already archived
- **`Z_ARCH_EKK_CREATE_VARIANTS`** — creates SAP selection variants for the above programs

### Shared Include — `Z_GSP18_ARCH_DYN`

Used by both `hub/F01` and `adk/` programs. Contains:
- `validate_table_against_cfg` — checks `ZSP26_ARCH_CFG` + DDIC (must be active, have a date field)
- `build_where_from_arch_cfg` — builds Open SQL WHERE clause from retention config
- `apply_archive_rules` — applies `ZSP26_ARCH_RULE` EQ filters
- F4 helpers for `P_TABLE` (table name selection from `ZSP26_ARCH_CFG`)

### Key Configuration Tables

| Table | Purpose |
|-------|---------|
| `ZSP26_ARCH_CFG` | Per-table archiving config: `DATA_FIELD` (date), `RETENTION` (days), `IS_ACTIVE` flag |
| `ZSP26_ARCH_RULE` | Optional EQ filter rules per config (e.g. restrict by BUKRS) |
| `ZSP26_ARCH_LOG` | Audit log of archive/restore/delete runs |
| `ZSP26_ARCH_ADMIN` | Users authorized as archive admins |
| `ZSP26_ARCH_STAT` | Run statistics per table |
| `ZSP26_ARCH_DEP` | Table dependency order for full-session restore |
| `ZSP26_ARCH_DATA` | Archived record data (JSON) — used by restore read path |
| `ZSP26_ARCH_FMAP` | Field mapping for archive structures |
| `ZSP26_ARCH_IDX` | Archive index for fast lookup |

### Variant Naming Convention

ADK write/delete variants are named using the pattern `<TABLE>_<ID>` (e.g. `ZSP26_EKKO_VAR01`). The hub builds the technical variant name with `arch_build_write_var_tech` and validates against VARID. The user-visible "Variant" field stores only the short ID suffix (after the first `_`).

### Admin vs. Non-Admin Flow

Admin status is checked via `PERFORM is_arch_admin` (reads `ZSP26_ARCH_ADMIN`). Admins see all buttons (Manage, Admin, full Restore). Non-admins are restricted and enter via screen 0400 (table select) only.

### SALV vs. ALV Grid

- Monitor (0200-style summary): uses `cl_gui_alv_grid` with custom container
- Monitor drill-down, BTC run log, ADM session view: use `cl_salv_table` with custom toolbar buttons via `lcl_mon_handler`, `lcl_btc_handler`, `lcl_run_handler`
- Config list (0810): uses `cl_salv_table` + `lcl_cfg_handler` which opens screen 0800 as a popup for new table registration
