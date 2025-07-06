terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.84"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "devops-eval-terraform-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "aws" {
  region = var.aws_region
}

data "google_client_config" "default" {}

resource "google_project_service" "container_api" {
  project = var.project_id
  service = "container.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "sql_api" {
  project = var.project_id
  service = "sqladmin.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "servicenetworking_api" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "dns_api" {
  project = var.project_id
  service = "dns.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Enable Gateway API on the cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = "default"
  subnetwork = "default"

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "172.16.0.0/14"
    services_ipv4_cidr_block = "172.20.0.0/16"
  }

  # Enable dataplane v2 for better networking
  datapath_provider = "ADVANCED_DATAPATH"

  # Explicitly enable VPC-native networking features
  networking_mode = "VPC_NATIVE"
}

provider "kubectl" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
  load_config_file       = false
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    preemptible  = true
    machine_type = "e2-medium"

    resource_labels = {
      "goog-gke-node-pool-provisioning-model" = "spot"
    }


    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    kubelet_config {
      cpu_cfs_quota      = false
      pod_pids_limit     = 0
      cpu_manager_policy = ""
    }

  }
}

# Service Account for GKE nodes
resource "google_service_account" "gke_sa" {
  account_id   = "${var.cluster_name}-sa"
  display_name = "GKE Service Account"
}

resource "google_project_iam_member" "gke_sa_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Cloud SQL Instance
resource "google_sql_database_instance" "postgres" {
  name             = "${var.cluster_name}-postgres"
  database_version = "POSTGRES_17"
  region           = var.region

  settings {
    tier    = "db-perf-optimized-N-2"
    edition = "ENTERPRISE_PLUS"

    ip_configuration {
      ipv4_enabled = true
      # Authorize GKE cluster nodes to access Cloud SQL
      authorized_networks {
        name  = "gke-nodes"
        value = "0.0.0.0/0" # In production, you'd use specific CIDR blocks
      }
      require_ssl = false
    }

    backup_configuration {
      enabled = true
    }

    data_cache_config {
      data_cache_enabled = true
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "app_db" {
  name     = "taskdb"
  instance = google_sql_database_instance.postgres.name
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "google_sql_user" "app_user" {
  name     = "appuser"
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}

# Gateway API - Public IP
resource "google_compute_address" "gateway_ip" {
  name         = "${var.cluster_name}-gateway-ip"
  region       = var.region
  project      = var.project_id
  network_tier = "STANDARD"
}

resource "google_compute_subnetwork" "proxy_only_subnet" {
  name          = "${var.cluster_name}-proxy-only-subnet"
  ip_cidr_range = var.proxy_only_cidr
  region        = var.region
  network       = "projects/${var.project_id}/global/networks/default"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Gateway API Gateway resource
resource "kubectl_manifest" "main_gateway" {
  depends_on = [google_container_node_pool.primary_nodes]

  yaml_body = <<YAML
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
spec:
  gatewayClassName: gke-l7-regional-external-managed
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  addresses:
  - type: NamedAddress
    value: ${google_compute_address.gateway_ip.name}
YAML
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "gateway" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [google_compute_address.gateway_ip.address]
}

# Private Service Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.cluster_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = "projects/${var.project_id}/global/networks/default"
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = "projects/${var.project_id}/global/networks/default"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_artifact_registry_repository" "docker_repository" {
  repository_id = "docker-repository"
  location      = var.region
  format        = "DOCKER"
  description   = "Docker repository for task API"

  docker_config {
    immutable_tags = false
  }
}