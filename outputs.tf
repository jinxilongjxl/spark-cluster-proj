output "spark_master_public_ip" {
  description = "Master节点公网IP"
  value       = google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip
}

output "ssh_master_command" {
  description = "登录Master节点（spark用户）"
  value       = "ssh spark@${google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip}"
}

output "worker_ips" {
  description = "Worker节点公网IP列表"
  value       = [for worker in google_compute_instance.spark_worker : worker.network_interface[0].access_config[0].nat_ip]
}

output "ssh_worker_commands" {
  description = "登录Worker节点（spark用户）"
  value = [for idx, worker in google_compute_instance.spark_worker : 
    "ssh spark@${worker.network_interface[0].access_config[0].nat_ip}  # Worker ${idx+1}"]
}

output "spark_web_ui" {
  description = "Spark Master Web界面"
  value       = "http://${google_compute_instance.spark_master.network_interface[0].access_config[0].nat_ip}:8080"
}