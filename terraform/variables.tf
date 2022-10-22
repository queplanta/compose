
variable "cluster_version" {
  default = "1.23"
}

variable "worker_count" {
  default = 1
}

variable "worker_size" {
  default = "s-1vcpu-1gb"
}

variable "write_kubeconfig" {
  type        = bool
  default     = false
}
