terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }
    utils = {
      source  = "cloudposse/utils"
      version = ">= 1.31.0"
    }
  }
}
