# ---------------------------------------------------------------------
# Variables for Cloud-Based Bus Pass System
# ---------------------------------------------------------------------

variable "stripe_secret_key" {
  description = "Stripe Secret Key (starts with sk_test_)"
  type        = string
  sensitive   = true
}

variable "stripe_webhook_secret" {
  description = "Stripe Webhook Secret (starts with whsec_)"
  type        = string
  sensitive   = true
}
