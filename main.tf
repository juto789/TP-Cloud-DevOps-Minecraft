provider "google" {
  project = "cloud-447110"
  region  = "europe-west9"
}

# VPC Network
resource "google_compute_network" "app_network" {
  name                    = "app-network"
  auto_create_subnetworks = false
}

# Subnetwork
resource "google_compute_subnetwork" "app_subnetwork" {
  name          = "app-subnetwork"
  ip_cidr_range = "10.0.0.0/16"
  network       = google_compute_network.app_network.self_link
  region        = "europe-west9"
}

# Firewall Rule
resource "google_compute_firewall" "app_firewall" {
  name    = "app-firewall-rule"
  network = google_compute_network.app_network.self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Instance Template
resource "google_compute_instance_template" "app_template" {
  name           = "app-instance-template"
  machine_type   = "e2-medium"
  region         = "europe-west9"

  disk {
    boot       = true
    source_image = "projects/cloud-447110/global/images/app-image-1736504202"
    auto_delete = true
  }

  network_interface {
    network    = google_compute_network.app_network.self_link
    subnetwork = google_compute_subnetwork.app_subnetwork.self_link
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo systemctl start app
  EOT
}

# Managed Instance Group
resource "google_compute_region_instance_group_manager" "app_mig" {
  name               = "app-mig"
  base_instance_name = "app-instance"
  region             = "europe-west9"
  target_size        = 3

  version {
    instance_template = google_compute_instance_template.app_template.self_link
  }
}

# Health Check
resource "google_compute_health_check" "app_health_check" {
  name                = "app-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# Backend Service
resource "google_compute_backend_service" "app_backend" {
  name                  = "app-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10

  backend {
    group = google_compute_region_instance_group_manager.app_mig.instance_group
  }

  health_checks = [
    google_compute_health_check.app_health_check.self_link
  ]
}

# URL Map
resource "google_compute_url_map" "app_url_map" {
  name            = "app-url-map"
  default_service = google_compute_backend_service.app_backend.self_link
}

# Target HTTP Proxy
resource "google_compute_target_http_proxy" "app_http_proxy" {
  name    = "app-http-proxy"
  url_map = google_compute_url_map.app_url_map.self_link
}

# IP Address
resource "google_compute_global_address" "app_ip" {
  name = "app-ip"
}

# Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "app_forwarding_rule" {
  name                  = "app-forwarding-rule"
  target                = google_compute_target_http_proxy.app_http_proxy.self_link
  port_range            = "80"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.app_ip.address
}

# Alert Policy
resource "google_monitoring_alert_policy" "app_alert_policy" {
  display_name = "App Instance Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "CPU Utilization"

    condition_threshold {
      comparison      = "COMPARISON_GT"
      duration        = "60s"
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\""
      threshold_value = 0.8
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_channel.name]
}

# Notification Channel
resource "google_monitoring_notification_channel" "email_channel" {
  display_name = "Admin Email"
  type         = "email"

  labels = {
    email_address = "rikoudo76@gmail.com"
  }
}

