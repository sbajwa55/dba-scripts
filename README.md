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
| [Tuning](#tuning) | [`tuning/`](tuning) | Instance tuning (waits, memory, I/O, locks, AWR/ASH) and SQL tuning (plans, statistics, indexes) |
| [High Availability](#high-availability) | [`ha/`](ha) | Data Guard, GoldenGate and RAC checks, switchover and lag monitoring |
| [General](#general) | [`general/`](general) | Parameters, character set, users and profiles, sessions, alert log, invalid objects, privileges, scheduler jobs, space |
| [OS](#os) | [`os/`](os) | Linux/Unix checks: disk, memory, CPU, processes, alert-log and listener-log scanning |

### Languages used

`SQL` · `KSH / Bash` · `Python` · `Terraform` · `SPL (Splunk)`

---

## Backups

RMAN backup and recovery, Data Pump exports and restore verification.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`rman_backup_status.sql`](backups/rman_backup_status.sql) | SQL | RMAN jobs for the last N days and age of the last successful backup of each type | 19c, 21c |
| [`backup_coverage_fra.sql`](backups/backup_coverage_fra.sql) | SQL | Datafiles with no recent backup, Fast Recovery Area usage, non-default RMAN settings | 19c, 21c |
| [`rman_backup_progress.sql`](backups/rman_backup_progress.sql) | SQL | Running RMAN jobs: % done, time left, channel waits | 19c, 21c |
| [`backup_size_trend.sql`](backups/backup_size_trend.sql) | SQL | Daily backup volume, compression ratio and throughput by backup type | 19c, 21c |
| [`archivelog_generation.sql`](backups/archivelog_generation.sql) | SQL | Redo generated per day, log switches per hour, archive logs never backed up | 19c, 21c |
| [`block_corruption_check.sql`](backups/block_corruption_check.sql) | SQL | Corrupt blocks and their segments, corruption in backups, NOLOGGING changes since last backup | 19c, 21c |
| [`flashback_restore_points.sql`](backups/flashback_restore_points.sql) | SQL | Flashback Database window and space, restore points, old guaranteed restore points | 19c, 21c |
| [`datapump_jobs_status.sql`](backups/datapump_jobs_status.sql) | SQL | Data Pump jobs, progress, worker sessions, orphaned jobs | 19c, 21c |
| [`rman_backup.ksh`](backups/rman_backup.ksh) | KSH | **Makes changes.** RMAN level 0 / level 1 / archive log backup with logging, cleanup of obsolete backups and e-mail on failure | 19c, 21c |
| [`rman_restore_validate.ksh`](backups/rman_restore_validate.ksh) | KSH | Proves the backups can be restored (RESTORE … VALIDATE) without restoring anything | 19c, 21c |
| [`datapump_export.ksh`](backups/datapump_export.ksh) | KSH | **Makes changes.** Consistent schema or full Data Pump export with checksums and removal of old exports | 19c, 21c |
| [`pg_backup.sh`](backups/pg_backup.sh) | Bash | **Makes changes.** PostgreSQL pg_dump of one or all databases plus roles, with a readability check and cleanup | PostgreSQL 13–17, RDS |

## Tuning

Tuning is split in two: **instance tuning** (the whole database: waits, memory, I/O, locks, load) and **SQL tuning** (one statement or one schema: plans, statistics, indexes).

> Scripts marked **Diagnostics Pack** or **Tuning Pack** read ASH/AWR or run advisors. Those are separately licensed Oracle Enterprise Edition options; run them only if you are licensed.

### Instance tuning — [`tuning/instance/`](tuning/instance)

| Script | Language | Description | Versions |
|---|---|---|---|
| [`top_sql_and_active_sessions.sql`](tuning/instance/top_sql_and_active_sessions.sql) | SQL | Active sessions by wait event, blocking sessions, top SQL with Exadata offload % | 19c, 21c |
| [`wait_events_exadata_offload.sql`](tuning/instance/wait_events_exadata_offload.sql) | SQL | Time model, top wait events, Exadata Smart Scan and storage index efficiency | 19c, 21c |
| [`blocking_lock_tree.sql`](tuning/instance/blocking_lock_tree.sql) | SQL | Who blocks whom as a tree, locked objects, and the KILL command for the root blocker (printed, not run) | 19c, 21c |
| [`memory_advisors.sql`](tuning/instance/memory_advisors.sql) | SQL | SGA components, SGA and PGA target advice, PGA over-allocation, automatic resize operations | 19c, 21c |
| [`redo_and_io_latency.sql`](tuning/instance/redo_and_io_latency.sql) | SQL | Read/write ms per tablespace and datafile, commit latency, redo log size and switch rate | 19c, 21c |
| [`ash_top_activity.sql`](tuning/instance/ash_top_activity.sql) | SQL | Last N minutes from ASH by wait class, event, SQL_ID, module and session — **Diagnostics Pack** | 19c, 21c |
| [`awr_load_profile_trend.sql`](tuning/instance/awr_load_profile_trend.sql) | SQL | Per-snapshot load: active sessions, CPU, IOPS, redo, transactions, executions — **Diagnostics Pack** | 19c, 21c |

### SQL tuning — [`tuning/sql/`](tuning/sql)

| Script | Language | Description | Versions |
|---|---|---|---|
| [`sql_details.sql`](tuning/sql/sql_details.sql) | SQL | One SQL_ID: text, child cursors with per-execution figures, profile/baseline/patch, bind values, plan | 19c, 21c |
| [`sql_plan_history.sql`](tuning/sql/sql_plan_history.sql) | SQL | Plan changes for one SQL_ID over AWR history, best plan, how to fix it with SPM — **Diagnostics Pack** | 19c, 21c |
| [`stats_health.sql`](tuning/sql/stats_health.sql) | SQL | Stale, missing and locked optimizer statistics for a schema, rows changed, auto stats job | 19c, 21c |
| [`index_usage.sql`](tuning/sql/index_usage.sql) | SQL | Indexes with no recorded use, their size, and foreign keys without an index | 19c, 21c |
| [`sql_plan_management.sql`](tuning/sql/sql_plan_management.sql) | SQL | SQL plan baselines, SQL profiles and SQL patches in the database, and SPM settings | 19c, 21c |
| [`sql_tuning_advisor.sql`](tuning/sql/sql_tuning_advisor.sql) | SQL | **Makes changes** (creates an advisor task). Runs the SQL Tuning Advisor on a SQL_ID — **Tuning Pack** | 19c, 21c |

## High Availability

Data Guard, GoldenGate and RAC monitoring and operations.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`dataguard_status.sql`](ha/dataguard/dataguard_status.sql) | SQL | Data Guard role, lag, destinations, gaps and apply processes | 19c, 21c |
| [`dataguard_alerts.sql`](ha/dataguard/dataguard_alerts.sql) | SQL | Data Guard errors from V$DATAGUARD_STATUS and the alert log | 19c, 21c |
| [`dg_switchover_readiness.sql`](ha/dataguard/dg_switchover_readiness.sql) | SQL | PASS/WARN/FAIL checklist before a switchover: force logging, flashback, broker, standby redo logs, transport, gaps, parameters | 19c, 21c |
| [`standby_apply_progress.sql`](ha/dataguard/standby_apply_progress.sql) | SQL | On the standby: apply rate, lag and lag history, received vs applied sequence per thread, MRP/RFS processes | 19c, 21c |
| [`dg_redo_transport.sql`](ha/dataguard/dg_redo_transport.sql) | SQL | On the primary: SYNC/ASYNC settings per destination, errors, last shipped and applied log per thread, logs shipped per day | 19c, 21c |
| [`dg_broker_check.ksh`](ha/dataguard/dg_broker_check.ksh) | KSH | Broker configuration and member status, VALIDATE DATABASE for each standby, exit code for monitoring | 19c, 21c |
| [`gg_db_capture_apply_status.sql`](ha/goldengate/gg_db_capture_apply_status.sql) | SQL | GoldenGate prerequisites, integrated Extract and Replicat status | 19c, 21c |
| [`ggserr_log_scan.ksh`](ha/goldengate/ggserr_log_scan.ksh) | KSH | Scan ggserr.log for ERROR/WARNING lines, summarised by OGG code | 19c, 21c |
| [`gg_lag_check.ksh`](ha/goldengate/gg_lag_check.ksh) | KSH | Every Extract/Replicat with status, lag and checkpoint age against thresholds, exit code for monitoring (Classic or saved Admin Client output) | 19c, 21c |
| [`gg_supplemental_logging.sql`](ha/goldengate/gg_supplemental_logging.sql) | SQL | Is a schema ready to replicate: database/schema/table supplemental logging, tables without keys, unsupported tables | 19c, 21c |
| [`gg_integrated_health.sql`](ha/goldengate/gg_integrated_health.sql) | SQL | Streams pool size, oldest archive log each Extract still needs (and if it is on disk), Replicat error queue | 19c, 21c |
| [`rac_cluster_status.sql`](ha/rac/rac_cluster_status.sql) | SQL | RAC instances, services per node, interconnect, global cache waits | 19c, 21c |
| [`crs_asm_status.ksh`](ha/rac/crs_asm_status.ksh) | KSH | Clusterware resources, voting disks, ASM disk groups, CRS/ASM alert errors | 19c, 21c |
| [`rac_services_check.ksh`](ha/rac/rac_services_check.ksh) | KSH | Each service's preferred/available/running instances; flags DOWN, FAILED OVER and missing instances with the srvctl fix | 19c, 21c |
| [`rac_load_balance.sql`](ha/rac/rac_load_balance.sql) | SQL | Load per instance, sessions per service on each node, service goal/failover/TAC settings, services that are down | 19c, 21c |
| [`rac_gc_interconnect.sql`](ha/rac/rac_gc_interconnect.sql) | SQL | Global cache receive times, lost/corrupt blocks, GC traffic, top cluster waits, hottest segments across nodes | 19c, 21c |
| [`asm_diskgroup_health.sql`](ha/rac/asm_diskgroup_health.sql) | SQL | ASM disk groups: free and usable space after mirroring, offline disks, imbalance between disks, running rebalances | 19c, 21c |

## General

Everyday DBA checks and housekeeping.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`db_instance_overview.sql`](general/db_instance_overview.sql) | SQL | Database role and modes, RAC instances, PDBs, key settings, last patches | 19c, 21c |
| [`alert_log_errors.sql`](general/alert_log_errors.sql) | SQL | Alert log errors for the last N hours via SQL, with a count by ORA- code | 19c, 21c |
| [`tablespace_usage.sql`](general/tablespace_usage.sql) | SQL | Tablespace size, used and free space with autoextend limits (run in each PDB) | 12c, 19c, 21c |
| [`tablespace_usage_all_pdbs.sql`](general/tablespace_usage_all_pdbs.sql) | SQL | Tablespace usage for every container at once, run from CDB$ROOT | 12c, 19c, 21c |
| [`pdb_status.sql`](general/pdb_status.sql) | SQL | All PDBs with open mode, restricted flag, size and saved state | 12c, 19c, 21c |
| [`characterset_nls.sql`](general/characterset_nls.sql) | SQL | Database and national character set, NLS at database/instance/session level, time zone file, BYTE vs CHAR columns | 19c, 21c |
| [`key_parameters.sql`](general/key_parameters.sql) | SQL | Key init parameters, everything changed from default, hidden and deprecated ones, SPFILE vs memory, RAC differences, resource limits | 19c, 21c |
| [`users_by_profile.sql`](general/users_by_profile.sql) | SQL | Users per profile and account status, passwords about to expire, unused accounts, default passwords, old 10G hashes | 19c, 21c |
| [`profile_limits.sql`](general/profile_limits.sql) | SQL | Every profile's resource and password limits side by side (DEFAULT resolved), users per profile, users near SESSIONS_PER_USER | 19c, 21c |
| [`session_summary.sql`](general/session_summary.sql) | SQL | Sessions by container, user, machine and program; long-idle sessions; PROCESSES and SESSIONS usage | 19c, 21c |
| [`alert_log_events.sql`](general/alert_log_events.sql) | SQL | Alert log over N days: messages per day, startups/shutdowns, ORA-600/7445, ALTER SYSTEM/DATABASE, checkpoint problems, ADR incidents | 19c, 21c |
| [`invalid_objects.sql`](general/invalid_objects.sql) | SQL | Invalid objects, unusable indexes, disabled constraints and triggers, registry components not VALID | 19c, 21c |
| [`privileged_users.sql`](general/privileged_users.sql) | SQL | DBA and other powerful role grantees, SYSDBA etc. in the password file, ANY privileges, extra grants to PUBLIC | 19c, 21c |
| [`scheduler_jobs_status.sql`](general/scheduler_jobs_status.sql) | SQL | Failed scheduler job runs with errors, failures per job, running jobs, broken/disabled jobs, maintenance windows | 19c, 21c |

## OS

Operating-system checks that matter to a DBA.

| Script | Language | Description | Versions |
|---|---|---|---|
| [`db_host_check.ksh`](os/db_host_check.ksh) | KSH | Load, memory, HugePages, disk space, instances, listeners, Exadata image | 19c, 21c |
| [`alert_log_scan.ksh`](os/alert_log_scan.ksh) | KSH | Scan every database and ASM alert log on the server for recent errors | 19c, 21c |
| [`listener_log_scan.ksh`](os/listener_log_scan.ksh) | KSH | Every listener log on the server: connections and failures per day, TNS- errors by code, top hosts/services/programs, oversized logs | 19c, 21c |

---

## Folder layout

```
dba-scripts/
├── README.md
├── LICENSE
├── backups/
├── tuning/
│   ├── instance/
│   └── sql/
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
