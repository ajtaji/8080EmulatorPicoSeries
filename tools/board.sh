#!/usr/bin/env bash
# Takes the shared board's lease, runs tools/build.ps1 with the same
# arguments (which must include -Port), and releases the lease at once.
# The lease is an exclusively created file; a lease over 30 minutes old is
# treated as abandoned and removed, and that is reported.
set -u
port=COM7
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "-Port" ] && port="${args[$((i + 1))]}"
done
dir=/c/PMFBuild/board-leases
lease="$dir/$port.lease"
mkdir -p "$dir"
while ! (set -o noclobber; echo "8080-core $(date -Iseconds)" > "$lease") 2>/dev/null; do
  if [ -f "$lease" ] && [ $(( $(date +%s) - $(stat -c %Y "$lease") )) -gt 1800 ]; then
    echo "Lease on $port is over 30 minutes old ($(cat "$lease")); removing it as abandoned."
    rm -f "$lease"
  else
    echo "Board $port is leased by: $(cat "$lease" 2>/dev/null) - retrying in 30 s"
    sleep 30
  fi
done
trap 'rm -f "$lease"' EXIT
here="$(cd "$(dirname "$0")" && pwd -W)"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here/build.ps1" -NoLease "$@"
