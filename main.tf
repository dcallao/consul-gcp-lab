data "google_compute_image" "consul_image" {
  family = "ubuntu-1604-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_network" "default" {
  name = "default"
}

locals {
  network = var.network == "" ? google_compute_network.default.name : var.network
}

resource "random_id" "environment_name" {
  byte_length = 32
}

resource "google_compute_firewall" "allow_consul" {
  name    = "allow-consul"
  network = local.network
  project = var.project_name

  allow {
    protocol = "tcp"
    ports    = ["8500", "8300", "8301", "8302", "8600"]
  }
  allow {
    protocol = "udp"
    ports    = ["8301", "8302", "8600"]
  }
  source_ranges = var.allowed_inbound_cidrs
}

resource "google_compute_firewall" "allow_consul_health_checks" {
  name    = "allow-vault-consul-health-check"
  network = local.network
  project = var.project_name

  allow {
    protocol = "tcp"
    ports    = ["8500"]
  }
  source_ranges = var.gcp_health_check_cidr
}

data "template_file" "install_consul" {
  template = file("${path.module}/templates/consul-server.sh.tpl")

  vars = {
    project                = var.project_name
    image                  = data.google_compute_image.consul_image.self_link
    environment_name       = random_id.environment_name.hex
    datacenter             = var.datacenter
    bootstrap_expect       = var.consul_nodes
    consul_cluster_version = var.consul_cluster_version
    redundancy_zones       = var.redundancy_zones
    bootstrap              = var.bootstrap
  }
}

resource "google_compute_instance" "consul" {
  name         = "consul-test${count.index}"
  machine_type = var.machine_type
  zone         = var.zone
  count        = var.consul_nodes

  tags = ["consul-server"]

  lifecycle {
        ignore_changes = [metadata_startup_script]
    }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.consul_image.self_link
      size  = 10
      type  = "pd-ssd"
    }
  }

  network_interface {
    #network       = google_compute_network.default.name
    network       = local.network
    access_config {}
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }

  allow_stopping_for_update = true

  metadata_startup_script = data.template_file.install_consul.rendered
}