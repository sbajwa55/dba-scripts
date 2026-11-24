# dba-scripts
DBA helpful scripts
DBA Scripts
Practical scripts for Oracle and multi-platform database administrators: SQL, KSH/Bash, Python, Terraform and Splunk SPL, collected from years of production database work.
Maintained by Sandeep S. Bajwa, Senior Oracle Database Engineer and author of AWS for Database Administrators: From On-Premises to Cloud.
Website: bajwaconsulting.com · Tutorials: bajwaconsulting.com/tutorials
> ⚠️ **Read before you run.** These scripts are provided as examples. Test them in a non-production environment first, review every command, and check that they suit your database version and your organization's change process. Some scripts change or remove data; they are clearly marked.
---
Contents
Section	Folder	What you'll find
Backups	`backups/`	RMAN, Data Pump and logical backups; restore tests; backup reporting
Tuning	`tuning/`	Top SQL, waits, AWR/ASH queries, execution plans, statistics
High Availability	`ha/`	Data Guard, GoldenGate and RAC checks, switchover and lag monitoring
General	`general/`	Space, users, sessions, locks, invalid objects, health checks
OS	`os/`	Linux/Unix checks: disk, memory, CPU, processes, alert-log scanning
Languages used
`SQL` · `KSH / Bash` · `Python` · `Terraform` · `SPL (Splunk)`
---
Backups
RMAN backup and recovery, Data Pump exports and restore verification.
Script	Language	Description	Tested on
`rman_backup_status.sql`	SQL	Status, size and duration of recent RMAN backups	19c
add your script here			
Tuning
Finding and fixing slow SQL and database bottlenecks.
Script	Language	Description	Tested on
`top_sql_by_elapsed.sql`	SQL	Top SQL statements by elapsed time from AWR	19c
add your script here			
High Availability
Data Guard, GoldenGate and RAC monitoring and operations.
Script	Language	Description	Tested on
`dg_lag_check.sql`	SQL	Data Guard transport and apply lag on the standby	19c
add your script here			
General
Everyday DBA checks and housekeeping.
Script	Language	Description	Tested on
`tablespace_usage.sql`	SQL	Tablespace size, used and free space, with autoextend	19c
add your script here			
OS
Operating-system checks that matter to a DBA.
Script	Language	Description	Tested on
`check_db_host.ksh`	KSH	Disk, memory, CPU load and Oracle processes in one report	Oracle Linux 8
add your script here			
---
Folder layout
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
Script header
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
Always state whether the script is read-only or makes changes.
Placeholders and secrets
Replace values in angle brackets, such as `<SCHEMA_NAME>` or `<BACKUP_DIR>`, with your own.
Never put passwords, keys or real host names in a script. Use OS authentication, a wallet, environment variables or a secrets manager.
Disclaimer
These scripts are provided "as is", without warranty of any kind. You are responsible for testing them and for any changes they make to your systems. Product names are trademarks of their respective owners.
Need help?
For Oracle DBA consulting, GoldenGate replication, performance tuning or migration to AWS, visit bajwaconsulting.com.
License
Released under the MIT License. See LICENSE.
