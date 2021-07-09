locals {
  intraday_schedule = {
    "development" = {
      "SUN-FRI" : "cron(0 10,11 ? * SUN-FRI *)",
      "SAT" : "cron(0 19,20 ? * SAT *)"
    },
    "qa" = {
      "SUN-FRI" : "cron(0 10,11? * SUN-FRI *)",
      "SAT" : "cron(0 19,20 ? * SAT *)"
    },
    "integration" = {
      "SUN-FRI" : "cron(0 10 ? * SUN-FRI *)",
      "SAT" : "cron(0 10 ? * SAT *)"
    },
    "preprod" = {
      "SUN-FRI" : "cron(0 10 ? * SUN-FRI *)",
      "SAT" : "cron(0 10 ? * SAT *)"
    },
    "production" = {
      "SUN-FRI" : "cron(0 10-14,19-22 ? * SUN-FRI *)",
      "SAT" : "cron(0 19-22 ? * SAT *)"
    },
  }
}

resource "aws_cloudwatch_event_rule" "hbase_incremental_rule" {
  for_each            = local.intraday_schedule[local.environment]
  name                = "intraday-refresh-${each.key}"
  description         = "scheduler for incremental refresh, days: ${each.key}"
  schedule_expression = each.value
  tags                = { Name = "intraday-refresh-${each.key}" }
}

resource "aws_cloudwatch_event_target" "hbase_incremental_refresh_target" {
  for_each  = local.intraday_schedule[local.environment]
  rule      = aws_cloudwatch_event_rule.hbase_incremental_rule[each.key].name
  target_id = "intraday-refresh-emr-launcher-${each.key}"
  arn       = aws_lambda_function.hbase_incremental_refresh_lambda.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "files/lambda"
  output_path = "lambda.zip"
}

resource "aws_lambda_function" "hbase_incremental_refresh_lambda" {
  filename         = "lambda.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "hbase_incremental_refresh"
  role             = aws_iam_role.hbase_incremental_refresh_lambda_role.arn
  description      = "Lambda function for incremental refresh"
  handler          = "index.handler"
  runtime          = "python3.8"
  timeout          = 900
  environment {
    variables = {
      job_status_table_name = aws_dynamodb_table.job_status.name
      emr_config_bucket     = data.terraform_remote_state.common.outputs.config_bucket["id"]
      emr_config_folder     = local.replica_emr_configuration_files_s3_prefix
      sns_topic_arn         = aws_sns_topic.hbase_incremental_refresh_sns.arn
      collections_secret_name   = local.collections_secret_name
    }
  }
  tags = { Name = "hbase_incremental_refresh" }
}

resource "aws_iam_role" "hbase_incremental_refresh_lambda_role" {
  name = "hbase_incremental_refresh_lambda_role"
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

  tags = { Name = "hbase_incremental_refresh_lambda_role" }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hbase_incremental_refresh_lambda.function_name
  principal     = "events.amazonaws.com"
}

data "aws_secretsmanager_secret" "intraday_collections_secret" {
  name = local.collections_secret_name
}

resource "aws_iam_policy" "hbase_incremental_refresh_lambda_policy" {
  name        = "hbase_incremental_refresh_lambda"
  path        = "/"
  description = "hbase_incremental_refresh_lambda"
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
          aws_dynamodb_table.job_status.arn,
          "${aws_dynamodb_table.job_status.arn}/index/*"
        ]
      },
      {
        Sid = "AllowLambdaToGetSecretManagerSecretCollections"
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

  tags = { Name = "hbase_incremental_refresh_lambda" }
}

resource "aws_iam_policy_attachment" "hbase_incremental_refresh_lambda_attach" {
  name       = "Use Any Identifier/Name You Want Here For IAM Policy Logs"
  policy_arn = aws_iam_policy.hbase_incremental_refresh_lambda_policy.arn
  roles      = [aws_iam_role.hbase_incremental_refresh_lambda_role.name]
}
