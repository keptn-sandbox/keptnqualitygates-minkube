/*
   GKE CLUSTERS/BASTION HOST generation
*/
terraform {
  required_version = ">= 0.12.0"
}

# Configure the Google Cloud provider
provider "google" {
  # see here how to get this file
  # https://console.cloud.google.com/apis/credentials/serviceaccountkey
  version = ">= 2.11.0"
  credentials = file(var.gcloud_cred_file)
  project = var.gcloud_project
  region  = join("-", slice(split("-", var.gcloud_zone), 0, 2))
}

resource "google_compute_disk" "vagrantdisk" {
  name  = "vagrant"
  type  = "pd-ssd"
  zone  = "${var.gcloud_zone}"
  image = "${var.os}"

  timeouts {
  create = "60m"
  }
}

resource "google_compute_image" "vagrantimg" {
  name = "vagrantimg"
  source_disk = "${google_compute_disk.vagrantdisk.self_link}"
  licenses = [
    "https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx",
  ]
  timeouts {
  create = "60m"
  }
}

# Terraform plugin for creating random ids
resource "random_id" "instance_id" {
  byte_length = 8
}

resource "google_compute_address" "static" {
  name = "ipv4-address-${random_id.instance_id.hex}"
}

resource "google_compute_firewall" "allow_https" {
  name    = "acl-https-${random_id.instance_id.hex}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [ "443" ]
  }

  target_tags = [ "acl-${random_id.instance_id.hex}" ]
}

# A single Google Cloud Engine instance
resource "google_compute_instance" "bastion" {
  name         = "${var.lab_prefix}-${random_id.instance_id.hex}"
  machine_type = var.instance_size
  zone         = var.gcloud_zone
  min_cpu_platform = "Intel Haswell"

  boot_disk {
    initialize_params {
      image = "${google_compute_image.vagrantimg.self_link}"
      type  = "pd-ssd"
      size  = "${var.disk-size}"
    }
  }

  network_interface {
    network = "default"

    access_config {
      # Include this section to give the VM an external ip address
      nat_ip = google_compute_address.static.address
    }
  }

  metadata = {
    sshKeys = "${var.username}:${file(var.ssh_pub_key)}"
  }

  tags = [ "acl-${random_id.instance_id.hex}" ]

  connection {
    host        = self.network_interface.0.access_config.0.nat_ip
    type        = "ssh"
    user        = "${var.username}"
    private_key = file(var.ssh_priv_key)
  }

 
  provisioner "remote-exec" {
    inline = [ "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" ]
  }

  provisioner "file" {
    destination = "~/configure_vm.sh"
    content     = templatefile(
      "${path.module}/templates/configure_vm.sh.tmpl",
      {
        keptn_release     = var.keptn_release,
        minikube_release  = var.minikube_release
        username          = var.username
      }
    )
  }

  provisioner "file" {
    source      = "${path.module}/templates/keptncreds.json"
    destination = "~/creds.json"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod a+x ~/configure_vm.sh",
      "sudo ~/configure_vm.sh"
    ]
  }

}
  
output "bastion-ip" {
  value = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

