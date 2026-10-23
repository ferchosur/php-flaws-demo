locals {
  tags = {
    created_by = var.owner
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  # Fecha fija (contrato): timestamp() produciría un diff perpetuo.
  # Debe ser el primer día de un mes; actualizar manualmente si el presupuesto
  # se reutiliza mucho tiempo después.
  budget_start = "2026-10-01T00:00:00Z"

  repository = "php-flaws-demo"
}
