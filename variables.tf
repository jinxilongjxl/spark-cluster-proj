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

variable "network_name" {
  description = "VPC 网络名称"
  type        = string
  default     = "spark-network"
}

variable "subnet_name" {
  description = "子网名称"
  type        = string
  default     = "spark-subnet"
}