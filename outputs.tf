output "spark_master_external_ip" {
  description = "Spark Master 节点的外部 IP 地址"
  value       = google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip
}

output "spark_worker_ips" {
  description = "所有 Worker 节点的内部 IP 地址"
  value       = [for worker in google_compute_instance.spark_worker : worker.network_interface[0].network_ip]
}