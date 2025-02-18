terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = "steady-adapter-451207-c1"
  region  = "europe-west1"
}

# 🔹 Récupération de l’image Packer la plus récente
data "google_compute_image" "minecraft_packer_image" {
  name    = "minecraft-image"
  project = "steady-adapter-451207-c1"
}

# 🔹 Politique de suppression automatique après 2 heures d'inactivité
resource "google_compute_resource_policy" "minecraft_autodelete" {
  name   = "minecraft-autodelete-policy"
  region = "europe-west1"

  instance_schedule_policy {
    vm_stop_schedule {
      schedule = "every 2 hours"
    }
  }
}

# 🔹 Déploiement des Instances Minecraft avec l’Image Packer
resource "google_compute_instance" "minecraft_server" {
  count        = 5
  name         = "minecraft-server-${count.index}"
  machine_type = "e2-medium"
  zone         = "europe-west1-b"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.minecraft_packer_image.self_link
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    preemptible         = true  # Permet la suppression automatique après 2h
  }

  resource_policies = [google_compute_resource_policy.minecraft_autodelete.id]
}

# 🔹 Création du Bucket de Sauvegarde
resource "google_storage_bucket" "minecraft_backup" {
  name          = "minecraft-backups-steady-adapter"
  location      = "EUROPE-WEST1"
  storage_class = "STANDARD"
}

# 🔹 Création de l'Adresse IP Publique
resource "google_compute_global_address" "minecraft_ip" {
  name = "minecraft-ip"
}

# 🔹 Configuration du Load Balancer
resource "google_compute_target_tcp_proxy" "minecraft_proxy" {
  name            = "minecraft-tcp-proxy"
  backend_service = google_compute_backend_service.minecraft_backend.id
}

resource "google_compute_backend_service" "minecraft_backend" {
  name                  = "minecraft-backend"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "TCP"

  backend {
    group = google_compute_instance_group.minecraft_group.id
  }
}

resource "google_compute_global_forwarding_rule" "minecraft_lb" {
  name        = "minecraft-load-balancer"
  ip_address  = google_compute_global_address.minecraft_ip.address
  target      = google_compute_target_tcp_proxy.minecraft_proxy.self_link
  ip_protocol = "TCP"
  port_range  = "25565"
}

# 🔹 Groupe de Serveurs
resource "google_compute_instance_group" "minecraft_group" {
  name      = "minecraft-group"
  zone      = "europe-west1-b"
  instances = google_compute_instance.minecraft_server[*].self_link
}

# 🔹 Ouverture du Port 25565 (Minecraft)
resource "google_compute_firewall" "allow_minecraft" {
  name    = "allow-minecraft"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# 🔹 Supervision avec Google Cloud Monitoring
resource "google_monitoring_metric_descriptor" "minecraft_cpu" {
  type        = "custom.googleapis.com/minecraft/cpu_utilization"
  metric_kind = "GAUGE"
  value_type  = "DOUBLE"

  display_name = "Minecraft CPU Usage"
  description  = "Moniteur d'utilisation CPU des serveurs Minecraft"

  labels {
    key         = "instance_id"
    value_type  = "STRING"
    description = "Instance ID"
  }

  unit = "1"

  metadata {
    ingest_delay  = "0s"
    sample_period = "60s"
  }
}

# 🔹 Exécution Automatique d'Ansible après Déploiement
resource "null_resource" "ansible_provision" {
  depends_on = [google_compute_instance.minecraft_server]

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini install_minecraft.yml --user ubuntu --private-key ~/.ssh/id_rsa"
  }
}
