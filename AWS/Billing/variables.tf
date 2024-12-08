variable "billing_threshold" {
  description = "The billing amount in USD that will trigger the alarm"
  type        = number
  default     = 100
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "twilio_account_sid" {
  description = "Twilio Account SID"
  type        = string
  sensitive   = true
}

variable "twilio_auth_token" {
  description = "Twilio Auth Token"
  type        = string
  sensitive   = true
}

variable "twilio_from_number" {
  description = "Twilio Phone Number to call from"
  type        = string
}

variable "twilio_to_number" {
  description = "Phone Number to call when billing exceeds threshold"
  type        = string
} 