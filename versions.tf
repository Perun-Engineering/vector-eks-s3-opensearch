terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    utils = {
      source  = "cloudposse/utils"
      version = "~> 2.5"
    }
  }
}
