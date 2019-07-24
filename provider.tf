# Configure the HashiCorp Vault Provider
provider "vault" {
  # It is strongly recommended to configure this provider through the 
  # environment variables

  address = "http://3163bcea.ngrok.io"
  token = "${var.vault-token}"
}

# Pull static secrets out of Vault for Microsoft Azure Provider
data "vault_generic_secret" "azure-static" {
  path = "secret/azure"
}

# Pull dynamic secrets out of Vault for Microsoft Azure Provider
data "vault_generic_secret" "azure" {
  path = "azure/creds/user"
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  tenant_id       = "${data.vault_generic_secret.azure-static.data["tenant_id"]}"
  subscription_id = "${data.vault_generic_secret.azure-static.data["subscription_id"]}"
  client_id       = "${data.vault_generic_secret.azure.data["client_id"]}"
  client_secret   = "${data.vault_generic_secret.azure.data["client_secret"]}"
}
