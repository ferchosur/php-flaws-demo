variable "name_prefix" {
  description = "Prefijo de nombres de recursos (minúsculas, números y guiones)."
  type        = string
  default     = "php-flaws-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix: 3-21 caracteres, minúsculas, números y guiones."
  }
}

variable "region" {
  description = "Región donde se despliegan los recursos."
  type        = string
}

variable "owner" {
  description = "Valor de la etiqueta created_by."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", var.owner))
    error_message = "owner: alfanumérico, guiones, guiones bajos o puntos; máximo 63 caracteres."
  }
}

variable "expires_at" {
  description = "Fecha (YYYY-MM-DD) hasta la que el entorno debe existir."
  type        = string
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.expires_at))
    error_message = "expires_at debe tener formato YYYY-MM-DD."
  }
}

variable "image" {
  description = "Imagen del contenedor con tag inmutable, por ejemplo <registro>/php-flaws-demo:20261023120000. Vacío durante el bootstrap del registro."
  type        = string
  default     = ""
}

variable "size" {
  description = "Tamaño de la carga: small o medium."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium"], var.size)
    error_message = "size debe ser small o medium."
  }
}

variable "replicas" {
  description = "Réplicas deseadas (ECS, Kubernetes) o máximo de instancias (Cloud Run, Container Apps). Las VM crean una sola instancia."
  type        = number
  default     = 2
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 5
    error_message = "replicas debe estar entre 1 y 5."
  }
}

variable "budget_usd" {
  description = "Presupuesto mensual en USD para la alerta de costo."
  type        = number
  default     = 25
}

variable "alert_email" {
  description = "Correo para alertas de presupuesto. Vacío desactiva las notificaciones."
  type        = string
  default     = ""
}

variable "billing_account_id" {
  description = "Solo GCP: ID de la cuenta de facturación para el presupuesto. Vacío lo omite."
  type        = string
  default     = ""
}

variable "project_id" {
  description = "Solo GCP: ID del proyecto. Vacío en otras nubes."
  type        = string
  default     = ""
}

variable "admin_cidrs" {
  description = "CIDR con acceso al endpoint público de Kubernetes (IP del operador, formato x.x.x.x/32). Obligatorio en GKE."
  type        = list(string)
  default     = []
}
