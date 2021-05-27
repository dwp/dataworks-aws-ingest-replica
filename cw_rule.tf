resource "aws_cloudwatch_event_rule" "hbase_incremental_rule" {
  name                = "hbase_incremental_refresh"
  description         = "scheduler for incremental refresh"
  schedule_expression = "cron(0, 8-18, ?, *, MON-FRI, *)"
  tags                = { Name = "hbase_incremental_refresh" }
}

resource "aws_cloudwatch_event_target" "hbase_incremental_refresh_target" {
  rule      = aws_cloudwatch_event_rule.hbase_incremental_rule.name
  target_id = "hbase_incremental_refresh_target"
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
      table_name   = aws_dynamodb_table.hbase_incremental_refresh_dynamodb.name
      bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
      folder = local.replica_emr_configuration_files_s3_prefix
      topic = aws_sns_topic.hbase_incremental_refresh_sns.arn
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
        Resource : aws_dynamodb_table.hbase_incremental_refresh_dynamodb.arn
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
