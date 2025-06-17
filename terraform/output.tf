output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_location" {
  value = google_container_cluster.primary.location
}

output "database_connection_name" {
  value = google_sql_database_instance.postgres.connection_name
}

output "database_private_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "database_password" {
  value       = random_password.db_password.result
  sensitive   = true
  description = "Database password for appuser"
}

output "database_url" {
  value       = "postgresql://appuser:${random_password.db_password.result}@${google_sql_database_instance.postgres.ip_address.0.ip_address}:5432/taskdb"
  sensitive   = true
  description = "Complete database URL for application"
}

output "gateway_ip" {
  value = google_compute_address.gateway_ip.address
}

output "dns_name" {
  value = "${var.subdomain}.${var.domain_name}"
}

output "artifact_registry_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repository.repository_id}"
  description = "Artifact Registry URL for Docker images"
}
