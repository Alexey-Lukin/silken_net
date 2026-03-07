variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for compute instances"
  type        = string
  default     = "europe-west1-b"
}

variable "db_password" {
  description = "Cloud SQL database password"
  type        = string
  sensitive   = true
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-7680"
}

variable "redis_memory_size_gb" {
  description = "Memorystore Redis memory size in GB"
  type        = number
  default     = 1
}

variable "web_machine_type" {
  description = "Machine type for web nodes"
  type        = string
  default     = "n2-standard-2"
}

variable "web_node_count" {
  description = "Number of web server instances"
  type        = number
  default     = 1
}

variable "ssh_public_key" {
  description = "SSH public key for accessing compute instances"
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "SSH username for compute instances"
  type        = string
  default     = "deploy"
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH into web nodes (restrict in production)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
