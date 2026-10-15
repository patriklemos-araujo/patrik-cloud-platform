terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.8.0"
}

provider "aws" {
  region = "us-east-1"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name = "patrik-cloudwatch-lab-lambda-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/patrik-cloudwatch-observability"
  retention_in_days = 7

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lambda_function" "app" {
  function_name = "patrik-cloudwatch-observability"

  role    = aws_iam_role.lambda.arn
  handler = "lambda_function.lambda_handler"
  runtime = "python3.13"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 5
  memory_size = 128

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda
  ]

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_metric_filter" "warning" {
  name           = "patrik-application-warning-filter"
  log_group_name = aws_cloudwatch_log_group.lambda.name

  pattern = "\"Simulated warning event\""

  metric_transformation {
    name      = "ApplicationWarnings"
    namespace = "PatrikCloudPlatform"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_warning" {
  alarm_name          = "patrik-application-warning-alarm"
  alarm_description   = "Triggers when at least one application warning is detected"

  namespace           = "PatrikCloudPlatform"
  metric_name         = "ApplicationWarnings"
  statistic           = "Sum"

  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data  = "notBreaching"

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_dashboard" "observability" {
  dashboard_name = "patrik-cloudwatch-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width  = 12
        height = 6

        properties = {
          title  = "Lambda Invocations"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 60

          metrics = [
            [
              "AWS/Lambda",
              "Invocations",
              "FunctionName",
              "patrik-cloudwatch-observability"
            ]
          ]
        }
      },

      {
        type = "metric"
        x    = 12
        y    = 0
        width  = 12
        height = 6

        properties = {
          title  = "Lambda Errors"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 60

          metrics = [
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              "patrik-cloudwatch-observability"
            ]
          ]
        }
      },

      {
        type = "metric"
        x    = 0
        y    = 6
        width  = 12
        height = 6

        properties = {
          title  = "Lambda Duration"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 60

          metrics = [
            [
              "AWS/Lambda",
              "Duration",
              "FunctionName",
              "patrik-cloudwatch-observability"
            ]
          ]
        }
      },

      {
        type = "metric"
        x    = 12
        y    = 6
        width  = 12
        height = 6

        properties = {
          title  = "Application Warnings"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 60

          metrics = [
            [
              "PatrikCloudPlatform",
              "ApplicationWarnings"
            ]
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name        = "patrik-lambda-error-alarm"
  alarm_description = "Triggers when the Lambda function reports at least one error"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"

  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    FunctionName = aws_lambda_function.app.function_name
  }

  treat_missing_data = "notBreaching"

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}