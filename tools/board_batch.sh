#!/usr/bin/env bash
# Holds the shared board's lease across several build.ps1 jobs, one per
# line of the jobs file (each line: the build.ps1 arguments, -Port included).
set -u
jobs="$1"; port="${2:-COM7}"
dir=/c/PMFBuild/board-leases; lease="$dir/$port.lease"
mkdir -p "$dir"
while ! (set -o noclobber; echo "8080-core $(date -Iseconds) batch" > "$lease") 2>/dev/null; do
  if [ -f "$lease" ] && [ $(( $(date +%s) - $(stat -c %Y "$lease") )) -gt 1800 ]; then
    echo "Lease on $port is over 30 minutes old ($(cat "$lease")); removing it as abandoned."
    rm -f "$lease"
  else
    echo "Board $port is leased by: $(cat "$lease" 2>/dev/null) - retrying in 30 s"; sleep 30
  fi
done
trap 'rm -f "$lease"' EXIT
here="$(cd "$(dirname "$0")" && pwd -W)"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  echo "=== JOB $line"
  eval "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$here/build.ps1\" -NoLease $line"
done < "$jobs"
