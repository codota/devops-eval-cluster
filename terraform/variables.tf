variable "project_id" {
  description = "GCP Project ID"
  default     = "devops-eval-463110"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE Cluster Name"
  type        = string
  default     = "devops-eval-cluster"
}

variable "proxy_only_cidr" {
  description = "The CIDR for the proxy only subnet"
  type        = string
  default     = "192.168.100.0/23"
}

variable "domain_name" {
  description = "Base domain name (e.g., example.com)"
  type        = string
  default     = "tabnine.com"
}

variable "subdomain" {
  description = "Subdomain for the gateway (e.g., gateway)"
  type        = string
  default     = "devops-eval"
}

variable "aws_region" {
  description = "AWS Region for Route53"
  type        = string
  default     = "us-east-1"
}