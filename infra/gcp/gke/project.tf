resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = var.project_id != ""
      error_message = "project_id is required on GCP."
    }
  }
}

resource "google_project_service" "api" {
  for_each = toset(concat(local.apis, var.billing_account_id != "" ? ["billingbudgets.googleapis.com"] : []))

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false

  depends_on = [terraform_data.guard]
}

data "google_project" "current" {
  project_id = var.project_id

  depends_on = [terraform_data.guard]
}

# Presupuesto filtrado por proyecto y etiqueta created_by.
# Las notificaciones por correo no se soportan directamente (requieren canal de
# Cloud Monitoring or Pub/Sub); alert_email is ignored here.
resource "google_billing_budget" "budget" {
  count = var.billing_account_id != "" ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "${var.name_prefix}-budget (created_by: ${var.owner})"

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
    labels   = { created_by = lower(var.owner) }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  depends_on = [google_project_service.api]
}
