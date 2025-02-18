provider "google" {
  project = "steady-adapter-451207-c1"
  region  = "europe-west1"
}

#  Création d'un Bucket pour Sauvegarde
resource "google_storage_bucket" "minecraft_backup" {
  name     = "minecraft-backups-steady-adapter"
  location = "EUROPE-WEST1"
  storage_class = "STANDARD"
}

# Création des Instances Minecraft
resource "google_compute_instance" "minecraft_server" {
  count        = 5
  name         = "minecraft-server-${count.index}"
  machine_type = "e2-medium"
  zone         = "europe-west1-b"

  boot_disk {
    initialize_params {
      image = "minecraft-image"  # Image Packer pré-configurée
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

    #  Téléchargement du Serveur Minecraft
    wget https://launcher.mojang.com/v1/objects/abc123/minecraft_server.1.20.1.jar -O server.jar
    echo "eula=true" > eula.txt

    #  Configuration du Serveur
    echo "difficulty=1" >> server.properties
    echo "max-players=4" >> server.properties
    echo "motd=Équipe ${count.index} - Serveur Minecraft FR !" >> server.properties
    echo "enable-command-block=true" >> server.properties
    echo "spawn-protection=0" >> server.properties
    echo "allow-flight=true" >> server.properties

    #  Lancer Minecraft en Arrière-Plan
    nohup java -Xmx2G -Xms1G -jar server.jar nogui &

    #  Configuration des Sauvegardes Automatiques
    cat <<EOF > /opt/minecraft/backup.sh
    #!/bin/bash
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
    BACKUP_FILE="/opt/minecraft/backup_\$TIMESTAMP.zip"

    zip -r \$BACKUP_FILE /opt/minecraft/world
    gsutil cp \$BACKUP_FILE gs://minecraft-backups-steady-adapter/
    ls -t /opt/minecraft/backup_*.zip | tail -n +11 | xargs rm -f
    EOF

    chmod +x /opt/minecraft/backup.sh

    #  Planification Cron (Sauvegarde toutes les 5 min)
    echo "*/5 * * * * /opt/minecraft/backup.sh" | crontab -
  EOT
}

# Création de l'Adresse IP Publique
resource "google_compute_global_address" "minecraft_ip" {
  name = "minecraft-ip"
}

#  Configuration du Load Balancer
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

#  Groupe de Serveurs
resource "google_compute_instance_group" "minecraft_group" {
  name     = "minecraft-group"
  zone     = "europe-west1-b"
  instances = google_compute_instance.minecraft_server[*].self_link
}

#  Ouverture du Port 25565 (Minecraft)
resource "google_compute_firewall" "allow_minecraft" {
  name    = "allow-minecraft"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }

  source_ranges = ["0.0.0.0/0"]
}
#  Supervision avec Google Cloud Monitoring
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
resource "null_resource" "ansible_provision" {
  depends_on = [google_compute_instance.minecraft_server]

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini install_minecraft.yml --user ubuntu --private-key ~/.ssh/id_rsa"
  }
}



