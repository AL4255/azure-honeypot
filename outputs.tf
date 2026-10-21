output "public_ip" {
  value = azurerm_public_ip.hp.ip_address
}

output "admin_ssh" {
  description = "Real SSH (only works from admin_ip). Port 22 is the honeypot."
  value       = "ssh -i ~/.ssh/honeypot_ed25519 -p 22222 azureuser@${azurerm_public_ip.hp.ip_address}"
}
