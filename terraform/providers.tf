terraform {
  required_version = ">= 1.14.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.2.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.1.0"
    }

    helm = {
      source = "hashicorp/helm"
      # version = "~> 2.9.0"
      version = ">= 2.9.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.1"
    }

    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 8.8.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.3"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.1"
    }

    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}

# Default provider — used by root-module data sources and resources
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Aliased provider — passed explicitly to the OKE module (oci.home)
provider "oci" {
  alias            = "home"
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
