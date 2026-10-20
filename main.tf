terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Backend values are supplied at init time by the workflow
  # (-backend-config), so nothing environment-specific is committed.
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

# ---------------------------------------------------------------------------
# Deliberately small. Enough surface to prove the pipeline works and to show
# plan output that isn't trivial, without running up a bill.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.project}-${var.environment}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 1)]
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app-${var.environment}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags

  # Default deny is implicit. This is here to make the plan output
  # show a rule change when you edit it, which is useful for testing
  # that the PR comment is doing its job.
  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_storage_account" "lab" {
  #checkov:skip=CKV_AZURE_206:Lab only; LRS acceptable for disposable data
  #checkov:skip=CKV2_AZURE_33:Lab only; no private networking in scope
  #checkov:skip=CKV_AZURE_59:Lab only; hosted runner uses public endpoint
  #checkov:skip=CKV2_AZURE_40:Phase 2; move to Azure AD-only data access

  name                            = "st${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "01.00:00:00"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    owner       = var.owner
  }
}
