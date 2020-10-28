provider "google" {
  #credentials = file("service-account-key.json")
  version     = "~>3.44.0"
  region      = "us-east1"
  project     = var.project_name
}