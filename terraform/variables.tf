
variable "cluster_version" {
  default = "1.23"
}

variable "worker_count" {
  default = 2
}

variable "worker_size" {
  default = "s-2vcpu-2gb"
}

variable "write_kubeconfig" {
  type        = bool
  default     = false
}
