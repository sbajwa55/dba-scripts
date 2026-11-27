#!/bin/ksh
# =============================================================
# Script   : io_stats_snapshot.ksh
# Purpose  : Disk I/O health for a few minutes: per device reads and
#            writes per second, MB/s, average wait (ms) and % busy from
#            iostat, flagging slow or saturated devices, with the ASM
#            disk name next to each device when it can be found
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); needs sysstat (iostat)
# Run as   : oracle or grid (any user can run iostat)
# Where    : Each database server, while the problem is happening
# Changes  : None (read-only)
# Usage    : ./io_stats_snapshot.ksh [interval_s] [samples]   default 10 6
# Settings : AWAIT_WARN (default 20 ms), UTIL_WARN (default 80 %)
# Notes    : The first iostat sample is the average since boot, so it
#            is skipped. Exadata cell disks are on the storage cells:
#            use cellcli there; this script shows the database node.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

INT=${1:-10}
CNT=${2:-6}
AWAIT_WARN=${AWAIT_WARN:-20}
UTIL_WARN=${UTIL_WARN:-80}

command -v iostat >/dev/null 2>&1 || { echo "iostat not found: install the sysstat package."; exit 1; }

# Map kernel device -> ASM disk label (ASMLib, AFD or udev names like /dev/oracleasm/*, /dev/asm*)
MAP=/tmp/iomap.$$; trap 'rm -f $MAP' EXIT
for L in /dev/oracleasm/disks/* /dev/oracleafd/disks/* /dev/asm* /dev/mapper/asm*; do
  [ -e "$L" ] || continue
  D=$(readlink -f "$L")
  [ -b "$D" ] && echo "$(basename "$D") $(basename "$L")"
done > $MAP 2>/dev/null

echo "=============================================================="
echo "I/O snapshot on $(hostname): $CNT samples x ${INT}s   $(date '+%d-%b-%Y %H:%M')"
echo "Flags: await > ${AWAIT_WARN} ms, %util > ${UTIL_WARN}"
echo "=============================================================="

iostat -dxk $INT $((CNT + 1)) | awk -v aw=$AWAIT_WARN -v uw=$UTIL_WARN -v mapf=$MAP '
  BEGIN { while ((getline l < mapf) > 0) { split(l, a, " "); asm[a[1]] = a[2] } }
  /^Device/ {
    hdr++
    for (i = 1; i <= NF; i++) col[$i] = i
    next
  }
  hdr >= 2 && NF > 5 && $1 !~ /^(loop|ram|sr)/ {
    d = $1; n[d]++
    r  = $col["r/s"]; w = $col["w/s"]
    rk = ("rkB/s" in col) ? $col["rkB/s"] : 0; wk = ("wkB/s" in col) ? $col["wkB/s"] : 0
    ra = ("r_await" in col) ? $col["r_await"] : $col["await"]
    wa = ("w_await" in col) ? $col["w_await"] : $col["await"]
    u  = $col["%util"]
    R[d] += r; W[d] += w; MB[d] += (rk + wk) / 1024; RA[d] += ra; WA[d] += wa; U[d] += u
    if (u > UMAX[d]) UMAX[d] = u
  }
  END {
    printf "%-14s %-18s %9s %9s %8s %9s %9s %7s %7s  %s\n", "Device", "ASM disk", "Reads/s", "Writes/s", "MB/s", "Read ms", "Write ms", "Util%", "Max%", "Flag"
    for (d in n) {
      k = n[d]; f = ""
      if (RA[d]/k > aw || WA[d]/k > aw) f = "SLOW"
      if (U[d]/k > uw) f = f (f ? "," : "") "BUSY"
      if (R[d] + W[d] == 0) continue
      printf "%-14s %-18s %9.1f %9.1f %8.1f %9.2f %9.2f %7.1f %7.1f  %s\n", d, (d in asm ? asm[d] : "-"),
             R[d]/k, W[d]/k, MB[d]/k, RA[d]/k, WA[d]/k, U[d]/k, UMAX[d], f
    }
  }' | (read H; echo "$H"; sort -k5 -nr)

echo
echo "Devices with no I/O are not listed. Averages are over the samples after the first."
echo "SLOW with low Util% = the storage or SAN is slow; BUSY = the device is saturated (spread the I/O)."
echo "Compare with what the database sees: tuning/instance/redo_and_io_latency.sql"
