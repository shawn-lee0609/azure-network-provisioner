# When terraform init runs, the following code gets executed, downloading
# the following providers and setting it up.

terraform {
  required_version = ">= 1.5" # The follwoing can only run under Terraform 1.5 or above.
  required_providers {
    # To communicate with Azure, require azurerm provider
    azurerm = {
      source  = "hashicorp/azurerm" # Where to get it
      version = "4.42.0"          
    }
  }
}

# How to operate the above installed provider
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id # The actual id comes from .tfvars
}