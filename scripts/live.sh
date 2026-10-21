#!/usr/bin/env bash
# Live feed of attacks. Ctrl+c to stop.
#   scripts/live.sh         fake SSH/Telnet logins and commands
#   scripts/live.sh scans   port scans on every other port
set -e
cd "$(dirname "$0")/.."
IP=$(terraform output -raw public_ip)
SSH=(ssh -i ~/.ssh/honeypot_ed25519 -p 22222 -o StrictHostKeyChecking=accept-new azureuser@"$IP")

if [[ "$1" == "scans" ]]; then
  "${SSH[@]}" "sudo journalctl -kf --no-pager -o cat | grep --line-buffered SCAN: | sed -u -E 's/.*SRC=([0-9.]+).*DPT=([0-9]+).*/\1 -> port \2/'"
else
  "${SSH[@]}" 'bash -s' <<'REMOTE'
DIR=$(sudo docker volume inspect cowrie-var -f '{{.Mountpoint}}')/log/cowrie
sudo tail -n 20 -F "$DIR/cowrie.json" | jq -r --unbuffered '
  select(.eventid | test("connect|login|command.input|file_download")) |
  "\(.timestamp[11:19])  \(.src_ip)  " + (
    if .eventid == "cowrie.session.connect" then "connected to port \(.dst_port)"
    elif .eventid == "cowrie.login.failed" then "login FAILED   \(.username) / \(.password)"
    elif .eventid == "cowrie.login.success" then "login OK       \(.username) / \(.password)"
    elif .eventid == "cowrie.command.input" then "typed: \(.input)"
    else "download: \(.url)" end)'
REMOTE
fi
