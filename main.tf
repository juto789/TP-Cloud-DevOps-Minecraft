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

# 🔹 Création d'un Bucket pour les Sauvegardes Minecraft
resource "google_storage_bucket" "minecraft_backup" {
  name          = "minecraft-backups-steady-adapter"
  location      = "EUROPE-WEST1"
  storage_class = "STANDARD"
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

# 🔹 Création des Instances Minecraft
resource "google_compute_instance" "minecraft_server" {
  count        = 5
  name         = "minecraft-server-${count.index}"
  machine_type = "e2-medium"
  zone         = "europe-west1-b"

  boot_disk {
    initialize_params {
      image = "minecraft-image"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt update && apt install -y openjdk-17-jre-headless wget unzip cron

    # Création du dossier de stockage
    mkdir -p /opt/minecraft && cd /opt/minecraft

    # Téléchargement du Serveur Minecraft
    wget https://launcher.mojang.com/v1/objects/abc123/minecraft_server.1.20.1.jar -O server.jar
    echo "eula=true" > eula.txt

    # Configuration du Serveur
    echo "difficulty=1" >> server.properties
    echo "max-players=4" >> server.properties
    echo "motd=Équipe ${count.index} - Serveur Minecraft FR !" >> server.properties
    echo "enable-command-block=true" >> server.properties
    echo "spawn-protection=0" >> server.properties
    echo "allow-flight=true" >> server.properties

    # Lancer Minecraft en Arrière-Plan
    nohup java -Xmx2G -Xms1G -jar server.jar nogui &

    # Configuration des Sauvegardes Automatiques
    cat <<EOF > /opt/minecraft/backup.sh
    #!/bin/bash
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
    BACKUP_FILE="/opt/minecraft/backup_\$TIMESTAMP.zip"

    zip -r \$BACKUP_FILE /opt/minecraft/world
    gsutil cp \$BACKUP_FILE gs://minecraft-backups-steady-adapter/
    ls -t /opt/minecraft/backup_*.zip | tail -n +11 | xargs rm -f
    EOF

    chmod +x /opt/minecraft/backup.sh

    # Planification Cron (Sauvegarde toutes les 5 min)
    echo "*/5 * * * * /opt/minecraft/backup.sh" | crontab -
  EOT

  scheduling {
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    preemptible         = true  # Permet la suppression automatique par GCP
  }

  resource_policies = [google_compute_resource_policy.minecraft_autodelete.id]
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
  ip_protocol =
