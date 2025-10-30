# ========== 读取本地 SSH 公钥（用于你登录 Master）==========
data "local_file" "local_ssh_public_key" {
  filename = var.local_ssh_public_key_path
}

# ========== 自定义 VPC ==========
resource "google_compute_network" "spark_vpc" {
  name                    = "spark-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "spark_subnet" {
  name          = "spark-subnet"
  region        = var.region
  network       = google_compute_network.spark_vpc.id
  ip_cidr_range = "10.0.2.0/24"
}

# ========== 主节点（Spark Master）==========
resource "google_compute_instance" "master" {
  name         = "spark-master"
  machine_type = "n1-standard-2"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 50
    }
  }

  network_interface {
    network    = google_compute_network.spark_vpc.id
    subnetwork = google_compute_subnetwork.spark_subnet.id
    access_config {}
  }

  # 注入你本地的公钥（用于你登录 Master）
  metadata = {
    ssh-keys = "spark:${data.local_file.local_ssh_public_key.content}"
  }

  metadata_startup_script = file("${path.module}/startup/install-spark-master.sh")

  tags = ["spark-cluster"]
}

# ========== 工作节点（Spark Worker）==========
resource "google_compute_instance" "worker" {
  count        = var.worker_count
  name         = "spark-worker-${count.index + 1}"
  machine_type = "n1-standard-2"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 100
    }
  }

  network_interface {
    network    = google_compute_network.spark_vpc.id
    subnetwork = google_compute_subnetwork.spark_subnet.id
    access_config {}
  }

  metadata_startup_script = file("${path.module}/startup/install-spark-worker.sh")

  tags = ["spark-cluster"]
}

# ========== 防火墙规则 ==========
resource "google_compute_firewall" "allow_internal" {
  name    = "spark-allow-internal"
  network = google_compute_network.spark_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_tags = ["spark-cluster"]
  target_tags = ["spark-cluster"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "spark-allow-ssh"
  network = google_compute_network.spark_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["spark-cluster"]
}

resource "google_compute_firewall" "allow_web_ui" {
  name    = "spark-allow-web-ui"
  network = google_compute_network.spark_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["8080", "8081"]
  }

  source_ranges = var.allowed_source_ips
  target_tags   = ["spark-cluster"]
}

# ========== 自动化分发 SSH 公钥到所有 Worker ==========
resource "null_resource" "distribute_ssh_key" {
  depends_on = [
    google_compute_instance.master,
    google_compute_instance.worker
  ]

  provisioner "local-exec" {
    command = <<EOT
      # 1. 等待 Master 节点 SSH 服务就绪
      MASTER_NAME="${google_compute_instance.master.name}"
      MASTER_ZONE="${google_compute_instance.master.zone}"
      MAX_RETRIES=60
      RETRY_DELAY=5

      echo "1. Waiting for $MASTER_NAME SSH to be ready..."
      retry_count=0
      while ! gcloud compute ssh $MASTER_NAME --zone=$MASTER_ZONE --command "exit 0" >/dev/null 2>&1; do
        if [ $retry_count -ge $MAX_RETRIES ]; then
          echo "Error: $MASTER_NAME SSH not ready (timeout)"
          exit 1
        fi
        retry_count=$((retry_count+1))
        sleep $RETRY_DELAY
      done
      echo "$MASTER_NAME SSH is ready"

      # 2. 等待 Master 的 spark 用户生成 id_rsa.pub（关键：确保密钥存在）
      echo "2. Waiting for $MASTER_NAME SSH key to be generated..."
      retry_count=0
      while ! gcloud compute ssh spark@$MASTER_NAME --zone=$MASTER_ZONE --command "test -f ~/.ssh/id_rsa.pub" >/dev/null 2>&1; do
        if [ $retry_count -ge $MAX_RETRIES ]; then
          echo "Error: $MASTER_NAME ~/.ssh/id_rsa.pub not found (timeout)"
          exit 1
        fi
        retry_count=$((retry_count+1))
        sleep $RETRY_DELAY
      done
      echo "$MASTER_NAME SSH key is generated"

      # 3. 从 Master 拉取公钥（此时文件已存在）
      echo "3. Pulling SSH public key from $MASTER_NAME..."
      gcloud compute scp spark@$MASTER_NAME:~/.ssh/id_rsa.pub ./master_rsa.pub --zone=$MASTER_ZONE

      # 4. 分发公钥到所有 Worker（先等 Worker SSH 就绪）
      %{ for i in range(var.worker_count) ~}
        WORKER_NAME="${google_compute_instance.worker[i].name}"
        WORKER_ZONE="${google_compute_instance.worker[i].zone}"
        echo "4. Waiting for $WORKER_NAME SSH to be ready..."
        retry_count=0
        while ! gcloud compute ssh $WORKER_NAME --zone=$WORKER_ZONE --command "exit 0" >/dev/null 2>&1; do
          if [ $retry_count -ge $MAX_RETRIES ]; then
            echo "Error: $WORKER_NAME SSH not ready (timeout)"
            exit 1
          fi
          retry_count=$((retry_count+1))
          sleep $RETRY_DELAY
        done
        echo "$WORKER_NAME SSH is ready, distributing key..."
        # 分发公钥
        gcloud compute ssh spark@$WORKER_NAME --zone=$WORKER_ZONE --command "cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys" < ./master_rsa.pub
      %{ endfor ~}

      # 5. 清理临时文件
      rm ./master_rsa.pub
      echo "✅ SSH key distribution completed"
    EOT
  }
}