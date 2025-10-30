output "spark_master_external_ip" {
  description = "Spark Master 节点的外部 IP 地址"
  value       = google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip
}

output "ssh_spark_master_command" {
  description = "使用 spark 用户免密登录 Master 节点的 SSH 命令"
  value       = "ssh spark@${google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip}"
}

output "ssh_spark_worker_commands" {
  description = "使用 spark 用户免密登录各 Worker 节点的 SSH 命令"
  value = [
    for idx, worker in google_compute_instance.spark_worker :
    "ssh spark@${worker.network_interface[0].access_config[0].nat_ip}  # Worker ${idx + 1}"
  ]
}

output "spark_web_ui" {
  description = "Spark Master Web UI 地址"
  value       = "http://${google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip}:8080"
}