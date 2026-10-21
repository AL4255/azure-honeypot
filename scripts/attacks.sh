#!/usr/bin/env bash
# Summary of everything that has hit the honeypot so far.
set -e
cd "$(dirname "$0")/.."
IP=$(terraform output -raw public_ip)
ssh -i ~/.ssh/honeypot_ed25519 -p 22222 -o StrictHostKeyChecking=accept-new azureuser@"$IP" 'bash -s' <<'REMOTE'
DIR=$(sudo docker volume inspect cowrie-var -f '{{.Mountpoint}}')/log/cowrie
J() { sudo sh -c "cat $DIR/cowrie.json*" 2>/dev/null; }
conns() { J | jq -r 'select(.eventid=="cowrie.session.connect") | .src_ip'; }

echo "== Fake SSH/Telnet: $(conns | wc -l) connections from $(conns | sort -u | wc -l) different IPs"
echo; echo "== Top 10 attacking IPs"
conns | sort | uniq -c | sort -rn | head
echo; echo "== Top 15 username / password guesses"
J | jq -r 'select(.eventid | startswith("cowrie.login")) | "\(.username) / \(.password)"' | sort | uniq -c | sort -rn | head -15
echo; echo "== Commands typed after 'logging in'"
J | jq -r 'select(.eventid=="cowrie.command.input") | .input' | sort | uniq -c | sort -rn | head -15
echo; echo "== Malware they tried to download"
J | jq -r 'select(.eventid=="cowrie.session.file_download") | "\(.url)  sha256:\(.shasum)"' | sort -u | head
echo; echo "== Port scans on every other port (top 15)"
sudo journalctl -k --no-pager | grep -o 'DPT=[0-9]*' | cut -d= -f2 | sort | uniq -c | sort -rn | head -15 |
  awk 'BEGIN{n[80]="HTTP";n[443]="HTTPS";n[8080]="HTTP-alt";n[3389]="RDP (Windows remote desktop)";n[445]="SMB (Windows shares)";n[5900]="VNC";n[3306]="MySQL";n[1433]="MS SQL";n[6379]="Redis";n[5432]="Postgres";n[25]="SMTP";n[21]="FTP";n[8443]="HTTPS-alt";n[2375]="Docker API";n[9200]="Elasticsearch"}
       {printf "%7s  port %-6s %s\n", $1, $2, n[$2]}'
REMOTE
