#!/bin/ksh
# =============================================================
# Script   : cert_expiry_check.ksh
# Purpose  : Find the TLS/SSL certificates used by Oracle on this
#            server (database and listener wallets, GoldenGate
#            deployments, PEM files) and show when each one expires,
#            so a TLS connection does not suddenly stop working
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash, GNU date); Oracle 19c,
#            21c; GoldenGate Microservices
# Run as   : oracle (the wallet owner)
# Where    : Each database / GoldenGate server
# Changes  : None (read-only)
# Usage    : ./cert_expiry_check.ksh [warn_days]          default 30
#            WALLET_DIRS="/u01/app/oracle/wallet" ./cert_expiry_check.ksh
# Exit     : 0 = nothing expires within warn_days, 1 = expiring, 2 = expired
# Notes    : Auto-login wallets (cwallet.sso) are read with orapki and no
#            password. Password-only wallets (ewallet.p12 without
#            cwallet.sso) are listed but cannot be read without a password.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

WARN_DAYS=${1:-30}
NOW=$(date +%s)
RC=0
ORAPKI=$(command -v orapki 2>/dev/null); [ -z "$ORAPKI" ] && [ -x "$ORACLE_HOME/bin/orapki" ] && ORAPKI=$ORACLE_HOME/bin/orapki

# Print one certificate line and raise the exit code (called in the main shell, not a subshell)
show() {   # $1 = label  $2 = expiry as epoch seconds
  D=$(( ($2 - NOW) / 86400 ))
  if   [ $D -lt 0 ];          then V="EXPIRED $((-D)) days ago"; RC=2
  elif [ $D -le $WARN_DAYS ]; then V="expires in $D days"; [ $RC -lt 1 ] && RC=1
  else V="OK ($D days)"; fi
  printf "   %-60s %-12s %s\n" "$(echo "$1" | cut -c1-60)" "$(date -d @$2 +%d-%b-%Y)" "$V"
}

echo "=============================================================="
echo "Certificate expiry on $(hostname), warn within $WARN_DAYS days   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

SEARCH="$WALLET_DIRS ${ORACLE_BASE:-/u01/app/oracle} /u01/app/grid /etc/oracle /u01/ogg /u02/ogg $OGG_HOME $OGG_ETC_HOME"
WALLETS=$(find $SEARCH -xdev \( -name cwallet.sso -o -name ewallet.p12 \) 2>/dev/null | xargs -r -n1 dirname | sort -u)
TMP=/tmp/certchk.$$; trap 'rm -f $TMP $TMP.l' EXIT

for W in $WALLETS; do
  echo
  echo ">> Wallet $W"
  if [ ! -f "$W/cwallet.sso" ]; then echo "   password-protected only: check with  orapki wallet display -wallet $W -complete"; continue; fi
  if [ -z "$ORAPKI" ]; then echo "   orapki not found: set ORACLE_HOME"; continue; fi
  "$ORAPKI" wallet display -wallet "$W" -complete 2>/dev/null > $TMP
  # orapki prints "Subject: ..." and "Valid Until: Sat Mar 13 11:00:00 EST 2027" for each certificate
  awk '/^Subject:/ {s = substr($0, 10)} /Valid Until:/ {sub(/.*Valid Until: */, ""); print s "|" $0}' $TMP > $TMP.l
  while IFS='|' read SUBJ UNTIL; do
    E=$(date -d "$(echo "$UNTIL" | awk '{print $2, $3, $4, $6}')" +%s 2>/dev/null)
    if [ -n "$E" ]; then show "$SUBJ" $E; else printf "   %-60s %s\n" "$SUBJ" "date not read: $UNTIL"; fi
  done < $TMP.l
  [ -s $TMP ] || echo "   could not read the wallet as $(id -un)"
done

# PEM certificates (GoldenGate Microservices, listeners using PEM, custom TLS)
PEMS=$(find $SEARCH -xdev -type f \( -name '*.pem' -o -name '*.crt' -o -name '*.cer' \) 2>/dev/null | head -100)
if [ -n "$PEMS" ] && command -v openssl >/dev/null 2>&1; then
  echo
  echo ">> PEM certificate files"
  for P in $PEMS; do
    END=$(openssl x509 -in "$P" -noout -enddate 2>/dev/null | cut -d= -f2)
    [ -z "$END" ] && continue
    E=$(date -d "$END" +%s 2>/dev/null) && show "$P" $E
  done
fi

[ -z "$WALLETS$PEMS" ] && echo "No wallets or certificate files found. Pass the folders in WALLET_DIRS."

echo
echo "Renew before expiry: create a new certificate request (orapki wallet add -dn ... -keysize 2048),"
echo "have it signed, import it, then restart the listener / reconnect clients during a quiet period."
exit $RC
