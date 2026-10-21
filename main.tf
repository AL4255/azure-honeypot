terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "hp" {
  name     = "rg-honeypot"
  location = var.location
  tags     = { purpose = "honeypot" }
}

# Its own network, not connected to anything else you run in Azure
resource "azurerm_virtual_network" "hp" {
  name                = "vnet-honeypot"
  address_space       = ["10.50.0.0/16"]
  location            = azurerm_resource_group.hp.location
  resource_group_name = azurerm_resource_group.hp.name
}

resource "azurerm_subnet" "hp" {
  name                 = "snet-honeypot"
  resource_group_name  = azurerm_resource_group.hp.name
  virtual_network_name = azurerm_virtual_network.hp.name
  address_prefixes     = ["10.50.1.0/24"]
}

# The firewall. Rules are checked lowest priority number first.
resource "azurerm_network_security_group" "hp" {
  name                = "nsg-honeypot"
  location            = azurerm_resource_group.hp.location
  resource_group_name = azurerm_resource_group.hp.name

  # --- Inbound ---
  security_rule {
    name                       = "admin-ssh-from-me"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22222"
    source_address_prefix      = var.admin_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "admin-ssh-block-everyone-else"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "22222"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Everything else is open on purpose: Cowrie answers on 22/23,
  # and every other port attempt is logged as a scan.
  security_rule {
    name                       = "bait-all-tcp"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # --- Outbound: only DNS and web (updates, Docker image pulls). ---
  # Nothing else leaves, so the box can't be used to attack anyone.
  security_rule {
    name                       = "out-dns"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "out-web"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "out-block-everything-else"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "hp" {
  subnet_id                 = azurerm_subnet.hp.id
  network_security_group_id = azurerm_network_security_group.hp.id
}

resource "azurerm_public_ip" "hp" {
  name                = "pip-honeypot"
  location            = azurerm_resource_group.hp.location
  resource_group_name = azurerm_resource_group.hp.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "hp" {
  name                = "nic-honeypot"
  location            = azurerm_resource_group.hp.location
  resource_group_name = azurerm_resource_group.hp.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.hp.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.hp.id
  }
}

resource "azurerm_linux_virtual_machine" "hp" {
  name                            = "vm-honeypot"
  location                        = azurerm_resource_group.hp.location
  resource_group_name             = azurerm_resource_group.hp.name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.hp.id]
  custom_data                     = base64encode(file("${path.module}/cloud-init.yaml"))

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.admin_ssh_key))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# Email when spending in this resource group passes 80% / 100% of the budget
resource "azurerm_consumption_budget_resource_group" "hp" {
  name              = "budget-honeypot"
  resource_group_id = azurerm_resource_group.hp.id
  amount            = var.monthly_budget
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
