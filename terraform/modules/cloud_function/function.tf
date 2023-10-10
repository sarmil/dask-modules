data "archive_file" "this" {
  type        = "zip"
  output_path = "${path.module}/lambda-files.zip"
  source_dir  = var.function_folder_location
  excludes    = var.excludes
}

resource "google_storage_bucket_object" "this" {
  name   = "${var.name}.${data.archive_file.this.output_sha}.zip"
  bucket = var.bucket_id
  source = data.archive_file.this.output_path
}

resource "google_cloudfunctions2_function" "this" {
  name        = var.name
  location    = var.location
  description = var.description
  project     = var.project
  labels      = var.labels

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = var.bucket_id
        object = google_storage_bucket_object.this.name
      }
    }
  }

  service_config {
    available_memory               = "1024M"
    min_instance_count             = var.min_instance_count
    max_instance_count             = var.max_instance_count
    timeout_seconds                = var.timeout_seconds
    environment_variables          = var.environment_variables
    ingress_settings               = var.ingress_settings
    all_traffic_on_latest_revision = var.all_traffic_on_latest_revision
    service_account_email          = var.service_account_email
  }
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project
  location       = var.location
  cloud_function = google_cloudfunctions2_function.this.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${var.service_account_email}"
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  project  = google_cloudfunctions2_function.this.project
  location = google_cloudfunctions2_function.this.location
  service  = google_cloudfunctions2_function.this.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.service_account_email}"
}

resource "google_project_iam_member" "token_creator" {
  project = var.project
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${var.service_account_email}"
}

resource "google_cloud_scheduler_job" "invoke_cloud_function" {
  name             = "invoke-${var.name}"
  description      = "Schedule the HTTPS trigger for cloud function"
  schedule         = var.schedule # every day at midnight
  time_zone        = "Europe/Oslo"
  project          = google_cloudfunctions2_function.this.project
  region           = google_cloudfunctions2_function.this.location
  attempt_deadline = "${var.timeout_seconds}s"

  http_target {
    uri         = google_cloudfunctions2_function.this.service_config[0].uri
    http_method = "POST"
    oidc_token {
      service_account_email = var.service_account_email
    }
  }
}