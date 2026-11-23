terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Credenciales: usa tu perfil de AWS (por ejemplo, export AWS_PROFILE=mi-perfil).
# La Local Zone de Bogotá se administra desde su región padre, us-east-1.
provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}
