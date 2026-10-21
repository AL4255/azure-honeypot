variable "subscription_id" {
  description = "Azure subscription to deploy into (set via TF_VAR_subscription_id)"
  type        = string
}

variable "location" {
  description = "Azure region. centralus has the cheap B-series sizes open for this subscription."
  type        = string
  default     = "centralus"
}

variable "vm_size" {
  description = "1 vCPU / 1 GiB is enough for Cowrie in Docker"
  type        = string
  default     = "Standard_B1s"
}

variable "admin_ip" {
  description = "Your public IP. Only this address can reach the real SSH port (22222)."
  type        = string
}

variable "admin_ssh_key" {
  description = "Public key for the admin account"
  type        = string
  default     = "~/.ssh/honeypot_ed25519.pub"
}

variable "alert_email" {
  description = "Where the budget alert is sent"
  type        = string
}

variable "monthly_budget" {
  description = "USD. You get an email at 80% and 100%."
  type        = number
  default     = 15
}
