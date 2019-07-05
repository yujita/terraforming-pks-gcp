resource "google_compute_image" "ops-manager-image" {
  name = "${var.env_prefix}-opsman-pcf-gcp" # name is required
  timeouts {
    create = "20m"
  }
  raw_disk {
    source = "${var.opsman_image_url}"
  }
}

// generate public ip address for ops-manager
resource "google_compute_address" "ops-manager-public-ip" {
  name = "${var.env_prefix}-om-public-ip" # a public ip will be generated and can be used as google_compute_address.ops-manager-public-ip.address
}

resource "google_compute_instance" "ops-manager" {
  name = "${var.env_prefix}-ops-manager"
  machine_type = "${var.opsman_machine_type}"
  zone = "${element(var.zones, 0)}" # var.zones is a list type objest. the first element in the var.zones chosen here.
  tags = ["${var.env_prefix}-opsman", "allow-https", "allow-ssh"] # tags - (Optional) A mapping of tags to assign to the resource. (seen from gcp console.)
  timeouts {
    create = "10m"
  }
  boot_disk {
    initialize_params {
      image = "${google_compute_image.ops-manager-image.self_link}" # self_link: the ops-manager-image resource itself, not its name or others.
      type = "pd-ssd"
      size = 150
    }
  }
  network_interface {
    subnetwork = "${google_compute_subnetwork.infrastructure-subnet.name}"
    network_ip = "${cidrhost(var.infrastructure_cidr, 5)}"
    access_config {
      nat_ip = "${google_compute_address.ops-manager-public-ip.address}"
    }
  }
}
