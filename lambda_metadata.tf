locals {
  enable_metadata_purge_lambda = {
    development = true
    qa          = false
    integration = false
    preprod     = false
    production  = false
  }
}


resource "aws_iam_role" "metadata_removal_lambda" {
  count = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  name  = "metadata-removal-lambda-role"
  path  = "/"
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

  tags = { Name = "metadata-removal-lambda-role" }
}


resource "aws_iam_policy_attachment" "metadata_removal_lambda" {
  count      = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  name       = "metadata-removal-lambda"
  policy_arn = aws_iam_policy.metadata_removal_lambda[count.index].arn
  roles      = [aws_iam_role.metadata_removal_lambda[count.index].name]
}

data "aws_iam_policy_document" "metadata_removal_lambda" {
  count = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  statement {
    sid = "LogGroup"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    sid = "EMRDescribeClusters"
    actions = [
      "elasticmapreduce:DescribeCluster"
    ]
    resources = ["*"]
  }

  statement {
    sid = "HBaseRootDirOperations"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${local.hbase_root_bucket}/${local.hbase_meta_prefix}*",
    ]
  }

  statement {
    sid = "HBaseBucketOperations"
    actions = [
      "s3:ListBucket*",
    ]
    resources = [
      "arn:aws:s3:::${local.hbase_root_bucket}",
    ]
  }

}

resource "aws_iam_policy" "metadata_removal_lambda" {
  count       = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  name        = "metadata-removal-lambda"
  description = "policy for lambda function that deletes replica metadata from hbase dir"
  policy      = data.aws_iam_policy_document.metadata_removal_lambda[count.index].json

  tags = { Name = "metadata-removal-lambda-policy" }
}

data "archive_file" "metadata_removal_lambda" {
  count                   = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  type                    = "zip"
  source_content          = file("files/metadata_removal_lambda/index.py")
  source_content_filename = "index.py"
  output_path             = "files/metadata_removal_lambda.zip"
}

resource "aws_lambda_function" "metadata_removal" {
  count            = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  filename         = data.archive_file.metadata_removal_lambda[count.index].output_path
  source_code_hash = data.archive_file.metadata_removal_lambda[count.index].output_base64sha256
  function_name    = "metadata_removal_lambda"
  role             = aws_iam_role.metadata_removal_lambda[count.index].arn
  description      = "Lambda function to remove replica metadata from hbase directory"
  handler          = "index.handler"
  runtime          = "python3.8"
  timeout          = 900

  environment {
    variables = {
      hbase_prefix = local.hbase_meta_prefix
      hbase_bucket = local.hbase_root_bucket
    }
  }

  tags = { Name = "metadata-removal-lambda" }
}

resource "aws_cloudwatch_event_rule" "emr_state_change" {
  count       = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  name        = "intraday-emr-terminated"
  description = "captures termination events for intraday emr clusters: TERMINATED|TERMINATED_WITH_ERRORS"

  event_pattern = jsonencode(
    {
      "source" : [
        "aws.emr"
      ],
      "detail-type" : [
        "EMR Cluster State Change"
      ],

      "detail" : {
        "state" : [
          "TERMINATED",
          "TERMINATED_WITH_ERRORS",
        ],
        "name" : [
          "intraday-incremental",
          "intraday-incremental-e2e",
        ],
      }
    }
  )
}

resource "aws_sns_topic" "emr_state_change" {
  count = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  name  = "intraday-emr-terminated"
}

resource "aws_cloudwatch_event_target" "emr_state_change_lambda" {
  count = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  rule  = aws_cloudwatch_event_rule.emr_state_change[count.index].name
  arn   = aws_sns_topic.emr_state_change[count.index].arn
}


resource "aws_sns_topic_subscription" "metadata_lambda_trigger" {
  count     = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  topic_arn = aws_sns_topic.emr_state_change[count.index].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.metadata_removal[count.index].arn
}

resource "aws_lambda_permission" "metadata_lambda_trigger" {
  count         = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  statement_id  = "LaunchMetadataRemoval"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metadata_removal[count.index].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.emr_state_change[count.index].arn
}

resource "aws_sns_topic_policy" "emr_state_change" {
  count  = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  arn    = aws_sns_topic.emr_state_change[count.index].arn
  policy = data.aws_iam_policy_document.sns_topic_policy[count.index].json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  count = local.enable_metadata_purge_lambda[local.environment] ? 1 : 0
  statement {
    sid       = "Allow CloudwatchEvents"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.emr_state_change[count.index].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}
