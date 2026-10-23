locals {
  tags = {
    created_by = var.owner
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  # Fixed date (contract): timestamp() would produce a perpetual diff.
  # Must be the first day of a month; update manually if the budget
  # is reused long afterward.
  budget_start = "2026-10-01T00:00:00Z"

  repository = "php-flaws-demo"
}
