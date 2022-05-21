terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.52.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "3.52.0"
    }
  }

  required_version = "~> 0.14"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
