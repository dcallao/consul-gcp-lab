data "google_compute_image" "consul_image" {
  family = "ubuntu-1604-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_network" "default" {
  name = var.network == "" ? "default" : var.network
}

resource "random_id" "environment_name" {
  byte_length = 32
}

resource "google_compute_firewall" "allow_consul" {
  name    = "allow-consul"
  network = google_compute_network.default.name
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
  network = google_compute_network.default.name
  project = var.project_name

  allow {
    protocol = "tcp"
    ports    = ["8500"]
  }
  source_ranges = var.gcp_health_check_cidr
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.default.name
  project = var.project_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = var.allowed_inbound_cidrs
}

data "template_file" "install_consul" {
  template = file("${path.module}/templates/consul-server.sh.tpl")

  vars = {
    project                = var.project_name
    image                  = data.google_compute_image.consul_image.self_link
    environment_name       = random_id.environment_name.hex
    datacenter             = var.datacenter
    bootstrap_expect       = var.consul_nodes
    bootstrap_docker       = var.bootstrap_docker_consul_container
    bootstrap_consul       = var.ootstrap_consul_vm
  }
}

resource "google_compute_instance" "consul" {
  name         = "demo-consul-server${count.index}"
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
    network       = google_compute_network.default.name
    access_config {}
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }

  allow_stopping_for_update = true

  metadata_startup_script = data.template_file.install_consul.rendered
}