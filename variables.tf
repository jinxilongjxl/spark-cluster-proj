variable "project_id" {
  description = "GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "GCP 区域"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP 可用区"
  type        = string
  default     = "us-central1-a"
}

variable "worker_count" {
  description = "Worker 节点数量"
  type        = number
  default     = 2
}

variable "allowed_source_ips" {
  description = "允许访问 Web UI 的源 IP 段"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # 生产环境请限制为具体 IP
}

variable "local_ssh_public_key_path" {
  description = "本地 SSH 公钥路径（~/.ssh/id_rsa.pub）"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}