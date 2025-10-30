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

variable "master_machine_type" {
  description = "Master 节点机器类型"
  type        = string
  default     = "n1-standard-2"
}

variable "worker_machine_type" {
  description = "Worker 节点机器类型"
  type        = string
  default     = "n1-standard-2"
}

variable "worker_count" {
  description = "Worker 节点数量"
  type        = number
  default     = 2
}

variable "local_ssh_public_key_path" {
  description = "本地 SSH 公钥路径（用于你登录集群）"
  type        = string
  default     = "~/.ssh/id_rsa.pub"  # 请替换为实际路径
}