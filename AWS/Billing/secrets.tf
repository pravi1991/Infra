# Create AWS Secrets Manager secret
resource "aws_secretsmanager_secret" "billing_alert_secrets" {
  name = "billing-alert-secrets"
}

# Store the secret values
resource "aws_secretsmanager_secret_version" "billing_alert_values" {
  secret_id = aws_secretsmanager_secret.billing_alert_secrets.id
  secret_string = jsonencode({
    slack_webhook_url  = var.slack_webhook_url
    twilio_account_sid = var.twilio_account_sid
    twilio_auth_token  = var.twilio_auth_token
    twilio_from_number = var.twilio_from_number
    twilio_to_number   = var.twilio_to_number
  })
}

# Data source to read the secret
data "aws_secretsmanager_secret_version" "current" {
  secret_id = aws_secretsmanager_secret.billing_alert_secrets.id
  depends_on = [aws_secretsmanager_secret_version.billing_alert_values]
} 