# Codebase index — ZSP26GSP18_SAP15

Quick map of this abapGit repository (`/src/`, see `.abapgit.xml`). For behavior and architecture, see `CLAUDE.md`. For documentation handoff facts, see `DOCUMENTATION_SOURCE.md`.

## Root

| Path | Role |
|------|------|
| `.abapgit.xml` | abapGit: `STARTING_FOLDER` `/src/`, `PREFIX` folder logic |
| `CLAUDE.md` | Agent/developer guide (layers, patterns, tables) |
| `DOCUMENTATION_SOURCE.md` | Structured facts for user/tech docs |
| `Technical_Specification.xlsx` | External spec (not parsed by tooling) |

## `src/` — Packages

| Object | Path | Notes |
|--------|------|-------|
| Package (root) | `src/package.devc.xml` | Top-level devclass |
| Package **HUB** | `src/hub/package.devc.xml` | Module pool UI |
| Package **ADK** | `src/adk/package.devc.xml` | Archive write/read/delete |
| Package **UTIL** | `src/util/package.devc.xml` | Setup, demo, registration |

## Hub — module pool `Z_GSP18_SAP15_MAIN`

Entry: `src/hub/z_gsp18_sap15_main.prog.abap` (+ `.prog.xml`).

| Include / artifact | File(s) | Role |
|---------------------|---------|------|
| TOP (types, globals, local classes) | `z_gsp18_sap15_top.prog.abap` | Global definitions |
| F01 (implementations, FORMs) | `z_gsp18_sap15_f01.prog.abap` | Class methods, subroutines |
| O01 (PBO) | `z_gsp18_sap15_o01.prog.abap` | Screen output modules |
| I01 (PAI) | `z_gsp18_sap15_i01.prog.abap` | Screen input modules |
| Dynpros | `z_gsp18_sap15_main.prog.screen_*.abap` | Screens **0100, 0200, 0300, 0400, 0500, 0600, 0700, 0800, 0810** |

## ADK programs (`src/adk/`)

| Program | Files | Role |
|---------|-------|------|
| `Z_ARCH_EKK_WRITE` | `z_arch_ekk_write.prog.abap`, `.prog.xml` | Archive to ADK |
| `Z_ARCH_EKK_READ` | `z_arch_ekk_read.prog.abap`, `.prog.xml` | Restore from ADK |
| `Z_ARCH_EKK_DELETE` | `z_arch_ekk_delete.prog.abap`, `.prog.xml` | Physical delete |
| `Z_ARCH_EKK_CREATE_VARIANTS` | `z_arch_ekk_create_variants.prog.abap` | Variants for ADK jobs |

## Utilities (`src/util/`)

| Program | Files | Role |
|---------|-------|------|
| `ZSP26_ARCH_ADMIN_SETUP` | `zsp26_arch_admin_setup.prog.abap`, `.prog.xml` | Admin setup |
| `ZSP26_ARCH_REGISTER` | `zsp26_arch_register.prog.abap`, `.prog.xml` | Table registration |
| `ZSP26_LOAD_SAMPLE_DATA` | `zsp26_load_sample_data.prog.abap`, `.prog.xml` | Sample data |
| `ZSP26_DEMO_FULL_FLOW_DATA` | `zsp26_demo_full_flow_data.prog.abap`, `.prog.xml` | End-to-end demo data |
| `ZARCH_HUB_DEMO_DATA` | `zarch_hub_demo_data.prog.abap`, `.prog.xml` | Hub demo |

## Shared include

| Object | File(s) | Role |
|--------|---------|------|
| `Z_GSP18_ARCH_DYN` | `z_gsp18_arch_dyn.prog.abap`, `.prog.xml` | Dynamic SQL, validation, F4 helpers |

## Transaction

| Object | File |
|--------|------|
| `Z_GSP18_SARA` | `z_gsp18_sara.tran.xml` |

## DDIC — configuration & control (`src/*.tabl.xml`)

| Table | File |
|-------|------|
| `ZSP26_ARCH_CFG` | `zsp26_arch_cfg.tabl.xml` |
| `ZSP26_ARCH_RULE` | `zsp26_arch_rule.tabl.xml` |
| `ZSP26_ARCH_LOG` | `zsp26_arch_log.tabl.xml` |
| `ZSP26_ARCH_ADMIN` | `zsp26_arch_admin.tabl.xml` |
| `ZSP26_ARCH_STAT` | `zsp26_arch_stat.tabl.xml` |
| `ZSP26_ARCH_DEP` | `zsp26_arch_dep.tabl.xml` |
| `ZSP26_ARCH_FMAP` | `zsp26_arch_fmap.tabl.xml` |
| `ZSP26_ARCH_IDX` | `zsp26_arch_idx.tabl.xml` |
| `ZSP26_ARCH_DATA` | `zsp26_arch_data.tabl.xml` |
| `ZSP26GSP18_SAP15` | `zsp26gsp18_sap15.tabl.xml` |
| `ZARCH_HUB_DEMO` | `zarch_hub_demo.tabl.xml` |

## DDIC — business (Z-copies) (`src/*.tabl.xml`)

| Table | File |
|-------|------|
| `ZSP26_EKKO` / `ZSP26_EKPO` | `zsp26_ekko.tabl.xml`, `zsp26_ekpo.tabl.xml` |
| `ZSP26_VBAK` / `ZSP26_VBAP` | `zsp26_vbak.tabl.xml`, `zsp26_vbap.tabl.xml` |
| `ZSP26_BKPF` / `ZSP26_BSEG` | `zsp26_bkpf.tabl.xml`, `zsp26_bseg.tabl.xml` |
| `ZSP26_MKPF` / `ZSP26_MSEG` | `zsp26_mkpf.tabl.xml`, `zsp26_mseg.tabl.xml` |
| `ZSP26_MARA` | `zsp26_mara.tabl.xml` |
| `ZSP26_KNA1` | `zsp26_kna1.tabl.xml` |

## DDIC — structures / legacy

| Object | File |
|--------|------|
| `ZSTR_ARCH_REC` | `zstr_arch_rec.tabl.xml` |

## Domains (`src/zsp26_dom_*.doma.xml`, `zsp26_dom_*.xml`)

`ZSP26_DOM_ARCHID`, `ZSP26_DOM_ARCHJSON`, `ZSP26_DOM_COUNTER`, `ZSP26_DOM_CRITERIA`, `ZSP26_DOM_DEPTYPE`, `ZSP26_DOM_FIELDNM`, `ZSP26_DOM_RETDAYS`, `ZSP26_DOM_TABNAM`, `ZSP26_DOM_TABNAME`, `ZSP26_DOM_XFLAG`

## Data elements (`src/zsp26_de_*.dtel.xml`)

`ZSP26_DE_ARCHID`, `ZSP26_DE_ARCHJSON`, `ZSP26_DE_COUNTER`, `ZSP26_DE_CRITERIA`, `ZSP26_DE_DEPTYPE`, `ZSP26_DE_FIELDNM`, `ZSP26_DE_RETDAYS`, `ZSP26_DE_STATUS`, `ZSP26_DE_TABNAME`, `ZSP26_DE_XFLAG`

## Search helps (`src/zsp26_sh_*.shlp.xml`)

`ZSP26_SH_ARCHID`, `ZSP26_SH_STATUS`, `ZSP26_SH_TABLES`

## File type legend

| Suffix | Meaning |
|--------|---------|
| `*.prog.abap` | ABAP source |
| `*.prog.xml` | abapGit program metadata |
| `*.tabl.xml` | Table / structure |
| `*.doma.xml` | Domain |
| `*.dtel.xml` | Data element |
| `*.shlp.xml` | Search help |
| `*.tran.xml` | Transaction |
| `*.devc.xml` | Package |

---

*Generated for repository navigation; keep in sync when adding objects.*
