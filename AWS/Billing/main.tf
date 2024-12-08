provider "aws" {
  region  = "us-east-1" # Billing metrics are only available in us-east-1
  profile = "terraform"
}

# Warning SNS Topic (>$5)
resource "aws_sns_topic" "billing_warning" {
  name = "billing-warning-topic"
}

# Critical SNS Topic (>$10)
resource "aws_sns_topic" "billing_critical" {
  name = "billing-critical-topic"
}

# Warning Alarm (>$5)
resource "aws_cloudwatch_metric_alarm" "billing_warning" {
  alarm_name          = "billing-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400" # 7 days
  statistic           = "Maximum"
  threshold           = 5
  alarm_description   = "Billing warning when charges exceed $5 USD"
  alarm_actions       = [aws_sns_topic.billing_warning.arn]

  dimensions = {
    Currency = "USD"
  }
}

# Critical Alarm (>$10)
resource "aws_cloudwatch_metric_alarm" "billing_critical" {
  alarm_name          = "billing-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400" # 7 days
  statistic           = "Maximum"
  threshold           = 10
  alarm_description   = "Billing CRITICAL when charges exceed $10 USD"
  alarm_actions       = [aws_sns_topic.billing_critical.arn]

  dimensions = {
    Currency = "USD"
  }
}

# Lambda Function
resource "aws_lambda_function" "notification_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "billing-notification-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.9"
  timeout          = 10
  layers           = [aws_lambda_layer_version.dependencies.arn]

  environment {
    variables = {
      SECRETS_ARN = aws_secretsmanager_secret.billing_alert_secrets.arn
    }
  }
}

# Create a null resource to install dependencies
resource "null_resource" "lambda_dependencies" {
  triggers = {
    requirements = filemd5("${path.module}/requirements.txt")
    source_code  = filemd5("${path.module}/index.py")
  }

  provisioner "local-exec" {
    command = <<EOF
      rm -rf ${path.module}/lambda_package
      mkdir -p ${path.module}/lambda_package
      pip install --target ${path.module}/lambda_package -r ${path.module}/requirements.txt
      cp ${path.module}/index.py ${path.module}/lambda_package/
    EOF
  }
}

# Create zip file from lambda_package directory
data "archive_file" "lambda_zip" {
  depends_on  = [null_resource.lambda_dependencies]
  type        = "zip"
  source_dir  = "${path.module}/lambda_package"
  output_path = "${path.module}/lambda_function.zip"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "billing_alert_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SNS Topic Subscriptions
resource "aws_sns_topic_subscription" "warning_lambda" {
  topic_arn = aws_sns_topic.billing_warning.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notification_handler.arn
}

resource "aws_sns_topic_subscription" "critical_lambda" {
  topic_arn = aws_sns_topic.billing_critical.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notification_handler.arn
}

# Lambda permissions to allow SNS to invoke it
resource "aws_lambda_permission" "warning_sns" {
  statement_id  = "AllowExecutionFromSNSWarning"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.billing_warning.arn
}

resource "aws_lambda_permission" "critical_sns" {
  statement_id  = "AllowExecutionFromSNSCritical"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.billing_critical.arn
}

# Create Lambda Layer for dependencies
resource "aws_lambda_layer_version" "dependencies" {
  filename            = data.archive_file.layer_zip.output_path
  layer_name          = "billing-alert-dependencies"
  compatible_runtimes = ["python3.9"]

  depends_on = [null_resource.layer_dependencies]
}

# Create layer dependencies
resource "null_resource" "layer_dependencies" {
  triggers = {
    requirements = filemd5("${path.module}/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<EOF
      rm -rf ${path.module}/layer
      mkdir -p ${path.module}/layer/python
      pip install --target ${path.module}/layer/python -r ${path.module}/requirements.txt
    EOF
  }
}

# Create layer zip
data "archive_file" "layer_zip" {
  depends_on  = [null_resource.layer_dependencies]
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/layer.zip"
}

# Add Secrets Manager access to Lambda IAM role
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "lambda_secrets_access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.billing_alert_secrets.arn
        ]
      }
    ]
  })
}
  