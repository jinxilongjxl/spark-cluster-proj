# 1. 新建 VPC 网络
resource "google_compute_network" "spark_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

# 2. 新建子网
resource "google_compute_subnetwork" "spark_subnet" {
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.spark_network.self_link
  ip_cidr_range = "10.0.0.0/24"
}

# 3. 防火墙规则（允许 SSH、Spark 端口通信）
resource "google_compute_firewall" "spark_firewall" {
  name    = "spark-firewall"
  network = google_compute_network.spark_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "7077", "8080", "8081", "4040"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# 4. Spark Master 实例
resource "google_compute_instance" "spark_master" {
  name         = "spark-master"
  machine_type = var.master_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.spark_subnet.self_link
    access_config {} # 分配外部 IP
  }

  metadata_startup_script = file("${path.module}/startup/install-spark-master.sh")

  depends_on = [google_compute_firewall.spark_firewall]
}

# 5. Spark Worker 实例（数量由 worker_count 控制）
resource "google_compute_instance" "spark_worker" {
  count        = var.worker_count
  name         = "spark-worker-${count.index}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.spark_subnet.self_link
    access_config {} # 分配外部 IP
  }

  metadata_startup_script = file("${path.module}/startup/install-spark-worker.sh")

  depends_on = [
    google_compute_firewall.spark_firewall,
    google_compute_instance.spark_master
  ]
}