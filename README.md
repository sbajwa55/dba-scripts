# DBA Scripts

Practical scripts for Oracle and multi-platform database administrators: SQL, KSH/Bash, Python, Terraform and Splunk SPL, collected from years of production database work.

Maintained by **Sandeep S. Bajwa**, Senior Oracle Database Engineer and author of *AWS for Database Administrators: From On-Premises to Cloud*.
Website: [bajwaconsulting.com](https://bajwaconsulting.com) · Tutorials: [bajwaconsulting.com/tutorials](https://bajwaconsulting.com/tutorials/index.html)

> ⚠️ **Read before you run.** These scripts are provided as examples. Test them in a non-production environment first, review every command, and check that they suit your database version and your organization's change process. Some scripts change or remove data; they are clearly marked.

---

## Contents

| Section | Folder | What you'll find |
|---|---|---|
| [Backups](#backups) | [`backups/`](backups) | RMAN, Data Pump and logical backups; restore tests; backup reporting |
| [Tuning](#tuning) | [`tuning/`](tuning) | Top SQL, waits, AWR/ASH queries, execution plans, statistics |
| [High Availability](#high-availability) | [`ha/`](ha) | Data Guard, GoldenGate and RAC checks, switchover and lag monitoring |
| [General](#general) | [`general/`](general) | Space, users, sessions, locks, invalid objects, health checks |
| [OS](#os) | [`os/`](os) | Linux/Unix checks: disk, memory, CPU, processes, alert-log scanning |

### Languages used

`SQL` · `KSH / Bash` · `Python` · `Terraform` · `SPL (Splunk)`

---

## Backups

RMAN backup and recovery, Data Pump exports and restore verification.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`rman_backup_status.sql`](backups/rman_backup_status.sql) | SQL | RMAN jobs for the last N days and age of the last successful backup of each type | 19c, 21c |
| [`backup_coverage_fra.sql`](backups/backup_coverage_fra.sql) | SQL | Datafiles with no recent backup, Fast Recovery Area usage, non-default RMAN settings | 19c, 21c |

## Tuning

Finding and fixing slow SQL and database bottlenecks.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`top_sql_and_active_sessions.sql`](tuning/top_sql_and_active_sessions.sql) | SQL | Active sessions by wait event, blocking sessions, top SQL with Exadata offload % | 19c, 21c |
| [`wait_events_exadata_offload.sql`](tuning/wait_events_exadata_offload.sql) | SQL | Time model, top wait events, Exadata Smart Scan and storage index efficiency | 19c, 21c |

## High Availability

Data Guard, GoldenGate and RAC monitoring and operations.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`dataguard_status.sql`](ha/dataguard/dataguard_status.sql) | SQL | Data Guard role, lag, destinations, gaps and apply processes | 19c, 21c |
| [`dataguard_alerts.sql`](ha/dataguard/dataguard_alerts.sql) | SQL | Data Guard errors from V$DATAGUARD_STATUS and the alert log | 19c, 21c |
| [`gg_db_capture_apply_status.sql`](ha/goldengate/gg_db_capture_apply_status.sql) | SQL | GoldenGate prerequisites, integrated Extract and Replicat status | 19c, 21c |
| [`ggserr_log_scan.ksh`](ha/goldengate/ggserr_log_scan.ksh) | KSH | Scan ggserr.log for ERROR/WARNING lines, summarised by OGG code | 19c, 21c |
| [`rac_cluster_status.sql`](ha/rac/rac_cluster_status.sql) | SQL | RAC instances, services per node, interconnect, global cache waits | 19c, 21c |
| [`crs_asm_status.ksh`](ha/rac/crs_asm_status.ksh) | KSH | Clusterware resources, voting disks, ASM disk groups, CRS/ASM alert errors | 19c, 21c |

## General

Everyday DBA checks and housekeeping.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`db_instance_overview.sql`](general/db_instance_overview.sql) | SQL | Database role and modes, RAC instances, PDBs, key settings, last patches | 19c, 21c |
| [`alert_log_errors.sql`](general/alert_log_errors.sql) | SQL | Alert log errors for the last N hours via SQL, with a count by ORA- code | 19c, 21c |
| [`tablespace_usage.sql`](general/tablespace_usage.sql) | SQL | Tablespace size, used and free space with autoextend limits (run in each PDB) | 12c, 19c, 21c |
| [`tablespace_usage_all_pdbs.sql`](general/tablespace_usage_all_pdbs.sql) | SQL | Tablespace usage for every container at once, run from CDB$ROOT | 12c, 19c, 21c |
| [`pdb_status.sql`](general/pdb_status.sql) | SQL | All PDBs with open mode, restricted flag, size and saved state | 12c, 19c, 21c |

## OS

Operating-system checks that matter to a DBA.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`db_host_check.ksh`](os/db_host_check.ksh) | KSH | Load, memory, HugePages, disk space, instances, listeners, Exadata image | 19c, 21c |
| [`alert_log_scan.ksh`](os/alert_log_scan.ksh) | KSH | Scan every database and ASM alert log on the server for recent errors | 19c, 21c |

---

## Folder layout

```
dba-scripts/
├── README.md
├── LICENSE
├── backups/
├── tuning/
├── ha/
│   ├── dataguard/
│   ├── goldengate/
│   └── rac/
├── general/
└── os/
```

Use subfolders when a section grows (for example `ha/goldengate/`). Name files in lowercase with underscores, and give them the right extension: `.sql`, `.ksh`, `.sh`, `.py`, `.tf`, `.spl`.

## Script header

Every script starts with a short header, so readers know what it does before they run it:

```sql
-- =============================================================
-- Script   : tablespace_usage.sql
-- Purpose  : Show size, used and free space for each tablespace
-- Section  : General
-- Database : Oracle 12c, 19c, 21c
-- Run as   : A user with SELECT_CATALOG_ROLE
-- Changes  : None (read-only)
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
```

For shell, Python, Terraform and SPL, use the same fields with that language's comment character (`#` or `//`).
Always state whether the script is **read-only** or **makes changes**.

## Placeholders and secrets

- Replace values in angle brackets, such as `<SCHEMA_NAME>` or `<BACKUP_DIR>`, with your own.
- **Never** put passwords, keys or real host names in a script. Use OS authentication, a wallet, environment variables or a secrets manager.

## Disclaimer

These scripts are provided "as is", without warranty of any kind. You are responsible for testing them and for any changes they make to your systems. Product names are trademarks of their respective owners.

## Need help?

For Oracle DBA consulting, GoldenGate replication, performance tuning or migration to AWS, visit [bajwaconsulting.com](https://bajwaconsulting.com).

## License

Released under the MIT License. See [LICENSE](LICENSE).
