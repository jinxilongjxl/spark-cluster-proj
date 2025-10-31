# 优先使用用户输入的公钥内容，否则读取本地文件
locals {
  ssh_public_key = var.ssh_public_key_content != "" ? var.ssh_public_key_content : file(var.local_ssh_public_key_path)
}

# VPC网络
resource "google_compute_network" "spark_vpc" {
  name                    = "spark-vpc"
  auto_create_subnetworks = false
}

# 子网
resource "google_compute_subnetwork" "spark_subnet" {
  name          = "spark-subnet"
  region        = var.region
  network       = google_compute_network.spark_vpc.id
  ip_cidr_range = "10.0.2.0/24"
}

# Spark Master节点
resource "google_compute_instance" "spark_master" {
  name         = "spark-master"
  machine_type = var.master_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"  # 改用Ubuntu（兼容性更好）
      size  = 50
    }
  }

  network_interface {
    network    = google_compute_network.spark_vpc.id
    subnetwork = google_compute_subnetwork.spark_subnet.id
    access_config {}  # 分配公网IP
  }

  # 注入用户SSH公钥（用于登录spark用户）
  metadata = {
    ssh-keys = "spark:${local.ssh_public_key}"
    
  }

  metadata_startup_script = file("${path.module}/startup/install-spark-master.sh")

  tags = ["spark-cluster"]
}

# Spark Worker节点
resource "google_compute_instance" "spark_worker" {
  count        = var.worker_count
  name         = "spark-worker-${count.index + 1}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
    }
  }

  network_interface {
    network    = google_compute_network.spark_vpc.id
    subnetwork = google_compute_subnetwork.spark_subnet.id
    access_config {}
  }

  # 关键：通过 metadata 传递 Master 节点的内网 IP（推荐）或公网 IP
  metadata = {
    master_ip = google_compute_instance.spark_master.network_interface.0.network_ip  # 内网 IP（集群内通信更稳定）
    # 若内网不通，可替换为：google_compute_instance.spark_master.network_interface.0.access_config.0.nat_ip
  }    
  metadata_startup_script = file("${path.module}/startup/install-spark-worker.sh")

  tags = ["spark-cluster"]
}

# 防火墙规则（开放必要端口）
resource "google_compute_firewall" "spark_firewall" {
  name    = "spark-all-ports"
  network = google_compute_network.spark_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22", "7077", "8080", "8081", "4040"]  # 包含SSH和Spark端口
  }

  allow {
    protocol = "icmp"  # 允许ping（调试用）
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["spark-cluster"]
}

resource "google_compute_firewall" "spark_firewall_allow_worker_rpc" {
  name       = "spark-all-tcp-udp-internal"  # 规则名称，可自定义
  network    = google_compute_network.spark_vpc.id  # 替换为你的VPC网络资源ID
  priority   = 65534  # 最低优先级（Terraform中priority值越大，优先级越低）

  # 开放所有TCP端口（0-65535）
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  # 开放所有UDP端口（0-65535）
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  # 保留ICMP（如ping调试）
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.2.0/24"]  # 仅允许10.0.2.0/24网段访问
  target_tags   = ["spark-cluster"]  # 替换为你的虚拟机网络标签
}

# 自动分发Master的SSH公钥到Worker（实现免密）
resource "null_resource" "distribute_ssh_key" {
  depends_on = [
    google_compute_instance.spark_master,
    google_compute_instance.spark_worker,
    google_compute_firewall.spark_firewall
  ]

  provisioner "local-exec" {
    command = <<EOT
      # 等待Master就绪
      MASTER_NAME="${google_compute_instance.spark_master.name}"
      MASTER_ZONE="${google_compute_instance.spark_master.zone}"
      MAX_RETRIES=60
      RETRY_DELAY=5

      echo "等待Master节点SSH就绪..."
      retry=0
      while ! gcloud compute ssh spark@$MASTER_NAME --zone=$MASTER_ZONE --command "exit 0" >/dev/null 2>&1; do
        if [ $retry -ge $MAX_RETRIES ]; then
          echo "错误：Master节点SSH未就绪"
          exit 1
        fi
        retry=$((retry+1))
        sleep $RETRY_DELAY
      done

      # 从Master获取spark用户的公钥
      echo "获取Master的SSH公钥..."
      gcloud compute scp spark@$MASTER_NAME:~/.ssh/id_rsa.pub ./master_ssh.pub --zone=$MASTER_ZONE

      # 分发公钥到所有Worker
      %{ for i in range(var.worker_count) ~}
        WORKER_NAME="${google_compute_instance.spark_worker[i].name}"
        WORKER_ZONE="${google_compute_instance.spark_worker[i].zone}"
        echo "分发公钥到Worker $WORKER_NAME..."
        
        # 等待Worker就绪
        retry=0
        while ! gcloud compute ssh spark@$WORKER_NAME --zone=$WORKER_ZONE --command "exit 0" >/dev/null 2>&1; do
          if [ $retry -ge $MAX_RETRIES ]; then
            echo "错误：Worker节点$WORKER_NAME SSH未就绪"
            exit 1
          fi
          retry=$((retry+1))
          sleep $RETRY_DELAY
        done
        
        # 写入公钥
        gcloud compute ssh spark@$WORKER_NAME --zone=$WORKER_ZONE --command "cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys" < ./master_ssh.pub
      %{ endfor ~}

      # 清理临时文件
      rm ./master_ssh.pub
      echo "SSH免密配置完成"
    EOT
  }
}