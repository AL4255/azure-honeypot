# Azure SSH Honeypot

A small, locked-down Azure VM that sits on the open internet and records who attacks it:
brute-force logins, the commands attackers run, the malware they try to download, and port
scans on every other port. Built with Terraform.

## How it works

```
 Internet ──► Azure firewall (NSG) ──► vm-honeypot (Ubuntu 24.04, Standard_B1s)
               │                          ├─ port 22 / 23  → Cowrie (fake SSH/Telnet in Docker)
               │                          ├─ other ports   → logged as scans (iptables LOG)
               │                          └─ port 22222    → real SSH, admin IP only
               └─ outbound: DNS + web only; everything else blocked
```

- **Cowrie** pretends to be a Linux server. Attackers "log in" to an emulated shell, so
  nothing they type runs on the real system. It records every username, password and command.
- **Real SSH** is moved to port 22222, and the firewall only lets one IP (yours) reach it.
- **Outbound traffic is restricted** to DNS and web, so a compromised box can't be used to
  attack other systems.
- **Own resource group and network**, not connected to anything else.
- **Budget alert** emails at 80% and 100% of the monthly budget.

## Deploy

```bash
export TF_VAR_subscription_id=$(az account show --query id -o tsv)
export TF_VAR_admin_ip=$(curl -s ifconfig.me)
export TF_VAR_alert_email="you@example.com"
terraform init
terraform plan -out tf.plan
terraform apply tf.plan
```

Cloud-init takes a few minutes after `apply` to install Docker and start Cowrie.

## Watch

```bash
scripts/attacks.sh        # summary: top IPs, passwords, commands, downloads, scanned ports
scripts/live.sh           # live feed of logins and commands
scripts/live.sh scans     # live feed of port scans
```

If your IP changes (new network, VPN), re-run `terraform apply` with the new `TF_VAR_admin_ip`.

## Tear down

```bash
terraform destroy
```

## Safety notes

- Downloaded malware stays on the VM in the Cowrie volume. Don't copy it to a personal machine;
  look up the SHA-256 on VirusTotal instead.
- The admin key (`~/.ssh/honeypot_ed25519`) is only for this VM.
- Keep the VM free of credentials: no managed identity, no secrets, no other Azure access.
