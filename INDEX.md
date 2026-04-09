# Codebase Index

## Overview

This repository is an SAP ABAP project for data archiving and restore, built around ADK and a custom archive object.

- Main archive object: `Z_ARCH_EKK`
- Main report/hub: `Z_GSP18_SAP15_MAIN`
- Main process: preview eligible records -> archive write -> delete via SARA -> read/restore

## Root Files

- `PLAN_FINAL.md` - full technical/project plan and test checklist
- `SCREEN_AND_UI_PLAN.md` - dynpro/UI flow reference
- `.abapgit.xml` - abapGit metadata
- `src/` - ABAP sources and DDIC object definitions

## Main Program Structure

- `src/z_gsp18_sap15_main.prog.abap` - entry point (`CALL SCREEN 0400`)
- `src/z_gsp18_sap15_top.prog.abap` - global data/types/class definition
- `src/z_gsp18_sap15_f01.prog.abap` - core FORM logic (preview, monitor, config, background jobs)
- `src/z_gsp18_sap15_o01.prog.abap` - PBO modules
- `src/z_gsp18_sap15_i01.prog.abap` - PAI modules (commands, F4, navigation)
- `src/z_gsp18_arch_dyn.prog.abap` - dynamic helper include used by F01

## Dynpro Screens

- `src/z_gsp18_sap15_main.prog.screen_0400.abap` - initial table select screen
- `src/z_gsp18_sap15_main.prog.screen_0100.abap` - operation hub screen
- `src/z_gsp18_sap15_main.prog.screen_0200.abap` - ALV screen (legacy/optional)
- `src/z_gsp18_sap15_main.prog.screen_0300.abap` - variant/scheduler support screen
- `src/z_gsp18_sap15_main.prog.screen_0500.abap` - status/support screen
- `src/z_gsp18_sap15_main.prog.screen_0600.abap` - status/support screen
- `src/z_gsp18_sap15_main.prog.xml` - dynpro/CUA metadata

## ADK Programs

- `src/z_arch_ekk_write.prog.abap` - write eligible records to ADK archive
- `src/z_arch_ekk_delete.prog.abap` - delete archived records (run in SARA context)
- `src/z_arch_ekk_read.prog.abap` - read archive and optionally restore records
- `src/z_arch_ekk_create_variants.prog.abap` - utility to create write variants

## Transaction and Package

- `src/z_gsp18_sara.tran.xml` - custom transaction object
- `src/package.devc.xml` - package definition

## Custom DDIC Objects

### Core configuration and log tables

- `src/zsp26_arch_cfg.tabl.xml`
- `src/zsp26_arch_rule.tabl.xml`
- `src/zsp26_arch_dep.tabl.xml`
- `src/zsp26_arch_log.tabl.xml`
- `src/zsp26_arch_stat.tabl.xml`
- `src/zsp26_arch_data.tabl.xml`
- `src/zsp26_arch_fmap.tabl.xml`
- `src/zsp26_arch_idx.tabl.xml`
- `src/zstr_arch_rec.tabl.xml` (DDIC structure, generic ADK payload)

### Business/source tables

- `src/zsp26_ekko.tabl.xml`, `src/zsp26_ekpo.tabl.xml`
- `src/zsp26_vbak.tabl.xml`, `src/zsp26_vbap.tabl.xml`
- `src/zsp26_bkpf.tabl.xml`, `src/zsp26_bseg.tabl.xml`
- `src/zsp26_mkpf.tabl.xml`, `src/zsp26_mseg.tabl.xml`
- `src/zsp26_mara.tabl.xml`, `src/zsp26_kna1.tabl.xml`

### Domains, data elements, and search helps

- Domains: `src/zsp26_dom_*.doma.xml`
- Data elements: `src/zsp26_de_*.dtel.xml`
- Search helps: `src/zsp26_sh_*.shlp.xml`

## Utility Programs

- `src/zsp26_load_sample_data.prog.abap` - loads sample config/rules/dependencies/data

## High-Level Runtime Flow

1. Run `Z_GSP18_SAP15_MAIN`
2. Select table on screen `0400`
3. Use hub actions on screen `0100`:
   - Write preview/archive
   - Restore/read
   - Monitor
   - Config view
4. ADK write/read/delete programs handle archive file operations
5. Logs and stats persist to `ZSP26_ARCH_LOG` and `ZSP26_ARCH_STAT`
