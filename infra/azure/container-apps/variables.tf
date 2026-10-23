variable "name_prefix" {
  description = "Resource name prefix (lowercase, digits and hyphens)."
  type        = string
  default     = "php-flaws-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix: 3-21 characters, lowercase, digits and hyphens."
  }
}

variable "region" {
  description = "Region where the resources are deployed."
  type        = string
}

variable "owner" {
  description = "Value of the created_by tag."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", var.owner))
    error_message = "owner: alphanumeric, hyphens, underscores or dots; max 63 characters."
  }
}

variable "expires_at" {
  description = "Date (YYYY-MM-DD) until which the environment should exist."
  type        = string
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.expires_at))
    error_message = "expires_at must be in YYYY-MM-DD format."
  }
}

variable "image" {
  description = "Container image with an immutable tag, e.g. <registry>/php-flaws-demo:20261023120000. Empty during registry bootstrap."
  type        = string
  default     = ""
}

variable "size" {
  description = "Workload size: small or medium."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium"], var.size)
    error_message = "size must be small or medium."
  }
}

variable "replicas" {
  description = "Desired replicas (ECS, Kubernetes) or max instances (Cloud Run, Container Apps). VMs create a single instance."
  type        = number
  default     = 2
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 5
    error_message = "replicas must be between 1 and 5."
  }
}

variable "budget_usd" {
  description = "Monthly budget in USD for the cost alert."
  type        = number
  default     = 25
}

variable "alert_email" {
  description = "Email for budget alerts. Empty disables notifications."
  type        = string
  default     = ""
}

variable "billing_account_id" {
  description = "GCP only: billing account ID for the budget. Empty skips it."
  type        = string
  default     = ""
}

variable "project_id" {
  description = "GCP only: project ID. Empty on other clouds."
  type        = string
  default     = ""
}

variable "admin_cidrs" {
  description = "CIDRs with access to the public Kubernetes endpoint (operator IP, x.x.x.x/32 format). Required on AKS."
  type        = list(string)
  default     = []
}
