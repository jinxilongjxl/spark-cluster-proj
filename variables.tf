variable "project_id" {
  description = "GCP项目ID（必填）"
  type        = string
}

variable "region" {
  description = "GCP区域"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP可用区"
  type        = string
  default     = "us-central1-a"
}

variable "master_machine_type" {
  description = "Master节点机器类型"
  type        = string
  default     = "n1-standard-2"
}

variable "worker_machine_type" {
  description = "Worker节点机器类型"
  type        = string
  default     = "n1-standard-2"
}

variable "worker_count" {
  description = "Worker节点数量"
  type        = number
  default     = 2
}

# 核心优化：允许用户手动输入公钥内容（避免文件路径问题）
variable "ssh_public_key_content" {
  description = "SSH公钥内容（替代文件路径，可通过`cat ~/.ssh/id_rsa.pub`获取）"
  type        = string
  default     = ""  # 留空则自动读取本地文件
}

variable "local_ssh_public_key_path" {
  description = "本地SSH公钥路径（当ssh_public_key_content为空时使用）"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}