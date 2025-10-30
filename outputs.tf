output "spark_master_external_ip" {
  description = "Spark Master 节点的外部 IP 地址"
  value       = google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip
}

output "ssh_master_command" {
  description = "登录 Master 节点的 SSH 命令（默认用户为 debian）"
  value       = "ssh debian@${google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip}"
}

output "spark_worker_external_ips" {
  description = "所有 Worker 节点的外部 IP 地址"
  value       = [for worker in google_compute_instance.spark_worker : worker.network_interface[0].access_config[0].nat_ip]
}

output "ssh_worker_commands" {
  description = "登录各 Worker 节点的 SSH 命令（默认用户为 debian）"
  value = [
    for idx, worker in google_compute_instance.spark_worker :
    "ssh debian@${worker.network_interface[0].access_config[0].nat_ip}  # Worker ${idx}"
  ]
}

output "spark_web_ui" {
  description = "Spark Master Web UI 地址"
  value       = "http://${google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip}:8080"
}