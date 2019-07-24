#
# Vault Training VM
#

variable "resource_group" {
  default     = "vault-cpu"
  description = "Name of the Azure Resource group"
}

variable "vault-token" {
}


variable "environment_tag" {
  default     = "Vault Training"
  description = "Name of Environment"
}

variable "private_key_filename" {
  default     = "private_key-pem"
  description = "Name of the SSH private key"
}

resource "tls_private_key" "main" {
  algorithm = "RSA"
}


variable "vault_download_url" {
    default = "https://releases.hashicorp.com/vault/1.1.2/vault_1.1.2_linux_amd64.zip"
}

resource "null_resource" "main" {
  provisioner "local-exec" {
    command = "echo \"${tls_private_key.main.private_key_pem}\" > ${var.private_key_filename}"
  }

  provisioner "local-exec" {
    command = "chmod 600 ${var.private_key_filename}"
  }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = "${var.resource_group}"
  }

  byte_length = 8
}

# Create virtual network
resource "azurerm_virtual_network" "vault-training-network" {
  name                = "vaultTrainingVnet-${random_id.randomId.hex}"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus"
  resource_group_name = "${var.resource_group}"

  tags {
    environment = "${var.environment_tag}"
  }
}

# Create subnet
resource "azurerm_subnet" "vault-training-subnet" {
  name                 = "vaultTrainingSubnet-${random_id.randomId.hex}"
  resource_group_name  = "${var.resource_group}"
  virtual_network_name = "${azurerm_virtual_network.vault-training-network.name}"
  address_prefix       = "10.0.1.0/24"
}

# Create public IPs
resource "azurerm_public_ip" "vault-training-publicip" {
  name                = "vaultTrainingPublicIP-${random_id.randomId.hex}"
  location            = "eastus"
  resource_group_name = "${var.resource_group}"
  allocation_method   = "Dynamic"
  domain_name_label   = "swissrevault"

  tags {
    environment = "${var.environment_tag}"
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "vault-training-nsg" {
  name                = "vaultTrainingNSG-${random_id.randomId.hex}"
  location            = "eastus"
  resource_group_name = "${var.resource_group}"

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Vault"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8200"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags {
    environment = "${var.environment_tag}"
  }
}

# Create network interface
resource "azurerm_network_interface" "vault-training-nic" {
  name                      = "vaultTrainingNIC-${random_id.randomId.hex}"
  location                  = "eastus"
  resource_group_name       = "${var.resource_group}"
  network_security_group_id = "${azurerm_network_security_group.vault-training-nsg.id}"

  ip_configuration {
    name                          = "vaultTrainingNicConfiguration-${random_id.randomId.hex}"
    subnet_id                     = "${azurerm_subnet.vault-training-subnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.vault-training-publicip.id}"
  }

  tags {
    environment = "${var.environment_tag}"
  }
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "vault-training-storeageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = "${var.resource_group}"
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags {
    environment = "${var.environment_tag}"
  }
}

data "template_file" "setup" {
  template = <<EOF
#!/bin/bash

# Install required module
sudo apt-get install -y unzip jq

# Install Vault
sudo curl $${vault_download_url} -o /tmp/vault.zip
sudo unzip -o /tmp/vault.zip -d /usr/bin/
sudo curl https://raw.githubusercontent.com/cpu601/training-vault/master/vault_agent.hcl > /home/azureuser/vault_agent.hcl
EOF

  vars = {
    vault_download_url = "${var.vault_download_url}"
  }
}

# Create virtual machine
resource "azurerm_virtual_machine" "vault-training-vm" {
  name                          = "vaultTrainingVM-${random_id.randomId.hex}"
  location                      = "eastus"
  resource_group_name           = "${var.resource_group}"
  network_interface_ids         = ["${azurerm_network_interface.vault-training-nic.id}"]
  vm_size                       = "Standard_A0"
  delete_os_disk_on_termination = true

  identity {
    type = "SystemAssigned"
  }

  storage_os_disk {
    name              = "vaultTrainingOsDisk-${random_id.randomId.hex}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04.0-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "vaultTrainingVM-${random_id.randomId.hex}"
    admin_username = "azureuser"
    custom_data    = "${data.template_file.setup.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/azureuser/.ssh/authorized_keys"
      key_data = "${tls_private_key.main.public_key_openssh}"
    }
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${azurerm_storage_account.vault-training-storeageaccount.primary_blob_endpoint}"
  }

  tags {
    environment = "${var.environment_tag}"
  }
}

# Outputs

output "ssh_connection_strings" {
  value = "${format("ssh -i %s azureuser@%s", var.private_key_filename, azurerm_public_ip.vault-training-publicip.ip_address)}"
}
