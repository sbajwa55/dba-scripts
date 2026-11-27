#!/usr/bin/env python3
"""
Build scripts.json for the bajwaconsulting.com scripts library from this repo.

Reads every script's header block (Where, Changes) and its one-line description
from the README tables, and writes the JSON the website's scripts-library.js loads.

Usage (from the repo root):
    python3 tools/build_scripts_json.py                 # writes ./scripts.json
    python3 tools/build_scripts_json.py /path/scripts.json

Author: Sandeep S. Bajwa · bajwaconsulting.com
"""
import json, os, re, sys

REPO = "https://github.com/sbajwa55/dba-scripts"
BRANCH = "main"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Folder -> filter label, in the order the chips appear on the page
SECTIONS = [
    ("backups", "Backups"),
    ("tuning/instance", "Instance tuning"),
    ("tuning/sql", "SQL tuning"),
    ("ha/dataguard", "Data Guard"),
    ("ha/goldengate", "GoldenGate"),
    ("ha/rac", "RAC"),
    ("general", "General"),
    ("os", "OS"),
]
LANG = {".sql": "SQL", ".ksh": "KSH", ".sh": "Bash", ".py": "Python", ".tf": "Terraform", ".spl": "SPL"}

# Short "Run in" text for each card. A script missing here falls back to its header "Where" line.
WHERE = {
    "archivelog_generation.sql": "CDB$ROOT or non-CDB",
    "backup_coverage_fra.sql": "CDB$ROOT or non-CDB",
    "backup_size_trend.sql": "CDB$ROOT or non-CDB",
    "block_corruption_check.sql": "CDB$ROOT or non-CDB",
    "datapump_export.ksh": "Database server or client host",
    "datapump_jobs_status.sql": "The PDB where the jobs run",
    "flashback_restore_points.sql": "CDB$ROOT or non-CDB",
    "pg_backup.sh": "PostgreSQL server or client host",
    "rman_backup.ksh": "Database server",
    "rman_backup_progress.sql": "CDB$ROOT or non-CDB",
    "rman_backup_status.sql": "CDB$ROOT or non-CDB",
    "rman_restore_validate.ksh": "Database server (open or mounted)",
    "ash_top_activity.sql": "CDB$ROOT or non-CDB",
    "awr_load_profile_trend.sql": "CDB$ROOT or non-CDB",
    "blocking_lock_tree.sql": "CDB$ROOT or non-CDB",
    "memory_advisors.sql": "Each instance, CDB$ROOT or non-CDB",
    "redo_and_io_latency.sql": "Each instance, CDB$ROOT or non-CDB",
    "top_sql_and_active_sessions.sql": "CDB$ROOT or non-CDB",
    "wait_events_exadata_offload.sql": "CDB$ROOT or non-CDB",
    "index_usage.sql": "The PDB that holds the schema",
    "sql_details.sql": "The PDB where the SQL runs",
    "sql_plan_history.sql": "CDB$ROOT or non-CDB",
    "sql_plan_management.sql": "The PDB where the SQL runs",
    "sql_tuning_advisor.sql": "The PDB where the SQL runs",
    "stats_health.sql": "The PDB that holds the schema",
    "dataguard_alerts.sql": "Primary and standby, CDB$ROOT",
    "dataguard_status.sql": "Primary and standby, CDB$ROOT",
    "dg_broker_check.ksh": "Any server in the Data Guard configuration",
    "dg_redo_transport.sql": "Primary, CDB$ROOT",
    "dg_switchover_readiness.sql": "Primary, then standby, CDB$ROOT",
    "standby_apply_progress.sql": "Standby, CDB$ROOT",
    "gg_db_capture_apply_status.sql": "Source: CDB$ROOT. Target: the PDB",
    "gg_integrated_health.sql": "Source: CDB$ROOT. Target: the PDB",
    "gg_lag_check.ksh": "GoldenGate server",
    "gg_supplemental_logging.sql": "Source PDB",
    "ggserr_log_scan.ksh": "GoldenGate server",
    "asm_diskgroup_health.sql": "Any database instance or +ASM",
    "crs_asm_status.ksh": "Any cluster node (grid user)",
    "rac_cluster_status.sql": "Any RAC instance",
    "rac_gc_interconnect.sql": "Any RAC instance",
    "rac_load_balance.sql": "Any RAC instance, CDB$ROOT",
    "rac_services_check.ksh": "Any cluster node (oracle user)",
    "alert_log_errors.sql": "CDB$ROOT or non-CDB",
    "alert_log_events.sql": "Each instance, CDB$ROOT or non-CDB",
    "characterset_nls.sql": "Each PDB, or non-CDB",
    "db_instance_overview.sql": "CDB$ROOT or non-CDB",
    "invalid_objects.sql": "Each PDB, or non-CDB",
    "key_parameters.sql": "CDB$ROOT or non-CDB",
    "pdb_status.sql": "CDB$ROOT",
    "privileged_users.sql": "Each PDB, or non-CDB",
    "profile_limits.sql": "Each PDB, or non-CDB",
    "scheduler_jobs_status.sql": "Each PDB, or non-CDB",
    "session_summary.sql": "CDB$ROOT or a PDB",
    "tablespace_usage.sql": "Each PDB, or non-CDB",
    "tablespace_usage_all_pdbs.sql": "CDB$ROOT",
    "users_by_profile.sql": "Each PDB, or non-CDB",
    "oswatcher_check.ksh": "Each database server (and Exadata cells)",
    "hugepages_calculator.ksh": "Each database server, all instances started",
    "io_stats_snapshot.ksh": "Each database server, during the problem",
    "cert_expiry_check.ksh": "Each database or GoldenGate server",
    "db_host_check.ksh": "Each database server",
}
STOP = {"and", "the", "of", "a", "to", "for", "sql", "ksh", "status", "check", "report"}


def readme_descriptions():
    """`file.sql` -> description text from the README tables (markdown removed)."""
    out = {}
    for line in open(os.path.join(ROOT, "README.md"), encoding="utf-8"):
        m = re.match(r"\|\s*\[`([^`]+)`\]\(([^)]+)\)\s*\|\s*[^|]+\|\s*(.+?)\s*\|\s*[^|]+\|\s*$", line)
        if m:
            text = re.sub(r"\*\*([^*]+)\*\*", r"\1", m.group(3))
            text = re.sub(r"^Makes changes( with -delete)?\.\s*|^Makes changes\s*\([^)]*\)\.\s*", "", text)
            out[m.group(2)] = text.strip().rstrip(".") + "."
    return out


def header_field(lines, name):
    """Return a header field (e.g. Where) joined over its continuation lines."""
    vals, on = [], False
    for l in lines:
        body = re.sub(r"^\s*(--|#)\s?", "", l)
        m = re.match(r"([A-Z][a-z]+)\s*:\s*(.*)$", body)
        if m and len(m.group(1)) <= 9:
            if on:
                break
            if m.group(1) == name:
                on = True
                vals.append(m.group(2).strip())
            continue
        if on:
            if body.startswith("====") or not body.strip():
                break
            vals.append(body.strip())
    return " ".join(v for v in vals if v)


def short_where(text):
    text = re.split(r"(?<=[a-z\)])\.\s|;\s", text + " ")[0].strip().rstrip(".")
    return text if len(text) <= 70 else text[:67].rsplit(" ", 1)[0] + "…"


def changes_label(text):
    t = text.lower()
    if t.startswith("none"):
        return "read-only"
    if "-delete" in t or "report only by default" in t:
        return "read-only unless run with -delete"
    if t.startswith("writes a copy"):
        return "saves a copy of the crontab"
    if "advisor task" in t:
        return "creates an advisor task"
    return "makes changes"


def tags_for(path, desc, section):
    words = re.split(r"[_./]", os.path.splitext(os.path.basename(path))[0])
    tags = [section.lower()] + [w for w in words if w and w not in STOP]
    for k in ("rman", "data pump", "exadata", "asm", "awr", "ash", "pdb", "rac", "goldengate",
              "standby", "hugepages", "wallet", "certificate", "cron", "listener", "alert log"):
        if k in desc.lower() and k not in tags:
            tags.append(k)
    return tags[:8]


def main():
    out_file = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "scripts.json")
    desc = readme_descriptions()
    scripts, missing = [], []
    for folder, label in SECTIONS:
        d = os.path.join(ROOT, folder)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            ext = os.path.splitext(name)[1]
            if ext not in LANG:
                continue
            path = f"{folder}/{name}"
            head = open(os.path.join(d, name), encoding="utf-8").read().splitlines()[:40]
            text = desc.get(path)
            if not text:
                missing.append(path)
                text = header_field(head, "Purpose")
            changes = header_field(head, "Changes")
            scripts.append({
                "name": name,
                "path": path,
                "section": label,
                "language": LANG[ext],
                "description": text,
                "where": WHERE.get(name) or short_where(header_field(head, "Where") or "See the script header"),
                "changes": changes_label(changes),
                "tags": tags_for(path, text, label),
            })
    data = {"repo": REPO, "branch": BRANCH, "count": len(scripts), "scripts": scripts}
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {out_file}: {len(scripts)} scripts")
    for p in missing:
        print(f"  note: {p} has no README row; used its header Purpose instead")


if __name__ == "__main__":
    main()
