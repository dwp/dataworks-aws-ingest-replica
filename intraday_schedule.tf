locals {
  intraday_schedule_enabled = {
    "development" = false,
    "qa"          = false,
    "integration" = false,
    "preprod"     = false,
    "production"  = false,

  }

  intraday_schedule = {
    "development" = {
      "SUN-FRI" : "cron(30 10,11 ? * SUN-FRI *)",
      "SAT" : "cron(0 19,20 ? * SAT *)"
    },
    "qa" = {
      "SUN-FRI" : "cron(30 10,11 ? * SUN-FRI *)",
      "SAT" : "cron(0 19,20 ? * SAT *)"
    },
    "integration" = {
      "SUN-FRI" : "cron(30 10-14 ? * SUN-FRI *)",
      "SAT" : "cron(0 19-22 ? * SAT *)"
    },
    "preprod" = {
      "SUN-FRI" : "cron(30 10-14,19-22 ? * SUN-FRI *)",
      "SAT" : "cron(0 19-22 ? * SAT *)"
    },
    "production" = {
      "SUN-FRI" : "cron(30 10-14,19-22 ? * SUN-FRI *)",
      "SAT" : "cron(0 19-22 ? * SAT *)"
    },
  }
}

resource "aws_cloudwatch_event_rule" "intraday_schedule" {
  for_each            = { for k, v in local.intraday_schedule[local.environment] : k => v if local.intraday_schedule_enabled[local.environment] }
  name                = "intraday-refresh-${each.key}"
  description         = "scheduler for incremental refresh, days: ${each.key}"
  schedule_expression = each.value
  tags                = { Name = "intraday-refresh-${each.key}" }
}

resource "aws_cloudwatch_event_target" "intraday_cron_lambda" {
  for_each  = { for k, v in local.intraday_schedule[local.environment] : k => v if local.intraday_schedule_enabled[local.environment] }
  rule      = aws_cloudwatch_event_rule.intraday_schedule[each.key].name
  target_id = "intraday-refresh-emr-launcher-${each.key}"
  arn       = aws_lambda_function.intraday_cron_launcher.arn
}

data "archive_file" "intraday_cron_lambda" {
  type        = "zip"
  source_dir  = "files/intraday_cron_lambda"
  output_path = "files/intraday_cron_lambda.zip"
}

resource "aws_lambda_function" "intraday_cron_launcher" {
  filename         = data.archive_file.intraday_cron_lambda.output_path
  source_code_hash = data.archive_file.intraday_cron_lambda.output_base64sha256
  function_name    = "intraday_cron_launcher"
  role             = aws_iam_role.intraday_cron_lambda_role.arn
  description      = "Lambda function for incremental refresh"
  handler          = "index.handler"
  runtime          = "python3.8"
  timeout          = 900
  environment {
    variables = {
      job_status_table_name   = aws_dynamodb_table.intraday_job_status.name
      emr_config_bucket       = data.terraform_remote_state.common.outputs.config_bucket["id"]
      emr_config_folder       = local.ingest_emr_configuration_files_s3_prefix
      launch_topic_arn        = aws_sns_topic.hbase_incremental_refresh_sns.arn
      alert_topic_arn         = data.terraform_remote_state.security-tools.outputs.sns_topic_london_monitoring["arn"]
      collections_secret_name = local.collections_secret_name
    }
  }
  tags = { Name = "intraday-cron-launcher" }
}

resource "aws_iam_role" "intraday_cron_lambda_role" {
  name = "intraday-cron-lambda-role"
  path = "/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = { Name = "intraday-cron-lambda-role" }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.intraday_cron_launcher.function_name
  principal     = "events.amazonaws.com"
}

data "aws_secretsmanager_secret" "intraday_collections_secret" {
  name = local.collections_secret_name
}

resource "aws_iam_policy" "intraday_cron_lambda_policy" {
  name        = "intraday-cron-lambda"
  path        = "/"
  description = "policy for cron-triggered lambda function which launches intraday emr cluster"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        Sid : "LogGroup"
        Effect : "Allow",
        Action : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource : "*"
      },
      {
        Sid : "SNSTopic"
        Effect : "Allow",
        Action : [
          "SNS:Receive",
          "SNS:Publish"
        ]
        Resource : aws_sns_topic.hbase_incremental_refresh_sns.arn
      },
      {
        Sid : "DynamoDBTableAccess",
        Effect : "Allow",
        Action : [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem",
          "dynamodb:PutItem",
          "dynamodb:DescribeTable",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:PartiQLInsert",
          "dynamodb:PartiQLUpdate",
          "dynamodb:PartiQLDelete",
          "dynamodb:PartiQLSelect"
        ],
        Resource : [
          aws_dynamodb_table.intraday_job_status.arn,
          "${aws_dynamodb_table.intraday_job_status.arn}/index/*"
        ]
      },
      {
        Sid    = "AllowLambdaToGetSecretManagerSecretCollections"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue",
        ]

        Resource = [
          data.aws_secretsmanager_secret.intraday_collections_secret.arn
        ]
      }
    ]
  })

  tags = { Name = "intraday-cron-lambda-policy" }
}

resource "aws_iam_policy_attachment" "intraday_cron_lambda" {
  name       = "intraday-cron-lambda"
  policy_arn = aws_iam_policy.intraday_cron_lambda_policy.arn
  roles      = [aws_iam_role.intraday_cron_lambda_role.name]
}
