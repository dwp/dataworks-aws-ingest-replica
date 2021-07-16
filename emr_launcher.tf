variable "emr_launcher_zip" {
  type = map(string)

  default = {
    base_path = ""
    version   = ""
  }
}

resource "aws_lambda_function" "intraday_emr_launcher" {
  filename      = "${var.emr_launcher_zip["base_path"]}/emr-launcher-${var.emr_launcher_zip["version"]}.zip"
  description   = "Launches intraday cluster for incremental dataset generation"
  function_name = "intraday-emr-launcher"
  role          = aws_iam_role.intraday_emr_launcher_lambda.arn
  handler       = "emr_launcher.handler.handler"
  runtime       = "python3.7"
  source_code_hash = filebase64sha256(
    format(
      "%s/emr-launcher-%s.zip",
      var.emr_launcher_zip["base_path"],
      var.emr_launcher_zip["version"]
    )
  )
  publish = false
  timeout = 60

  environment {
    variables = {
      EMR_LAUNCHER_CONFIG_S3_BUCKET = data.terraform_remote_state.common.outputs.config_bucket["id"]
      EMR_LAUNCHER_CONFIG_S3_FOLDER = local.ingest_emr_configuration_files_s3_prefix
      EMR_LAUNCHER_LOG_LEVEL        = "debug"
    }
  }

  tags = {
    Name        = "intraday-emr-launcher",
    Persistence = "Ignore"
  }
}

resource "aws_iam_role" "intraday_emr_launcher_lambda" {
  name               = "intraday-emr-launcher-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.intraday_emr_launcher_assume_role.json

  tags = {
    Name        = "intraday-emr-launcher-lambda",
    Persistence = "Ignore"
  }
}

data "aws_iam_policy_document" "intraday_emr_launcher_assume_role" {
  statement {
    sid     = "EMRLauncherLambdaAssumeRolePolicy"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "intraday_emr_launcher_read_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.common.outputs.config_bucket["id"]}/${local.ingest_emr_configuration_files_s3_prefix}/*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = [
      data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]
    ]
  }
}

data "aws_iam_policy_document" "intraday_emr_launcher_runjobflow" {
  statement {
    effect = "Allow"
    actions = [
      "elasticmapreduce:RunJobFlow",
      "elasticmapreduce:AddTags",
    ]
    resources = [
      "*"
    ]
  }
}

data "aws_iam_policy_document" "intraday_emr_launcher_pass_role" {
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::*:role/*"
    ]
  }
}

data "aws_iam_policy_document" "intraday_emr_launcher_getsecrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      data.terraform_remote_state.internal_compute.outputs.metadata_store_users["hbase_read_replica_writer"]["secret_arn"],
    ]
  }
}

resource "aws_iam_policy" "intraday_emr_launcher_read_s3" {
  name        = "intraday-emr-launcher-ReadS3"
  description = "Allow intraday emr-launcher to read from S3 bucket"
  policy      = data.aws_iam_policy_document.intraday_emr_launcher_read_s3.json

  tags = {
    Name        = "intraday-emr-launcher-ReadS3",
    Persistence = "Ignore"
  }
}

resource "aws_iam_policy" "intraday_emr_launcher_runjobflow" {
  name        = "intraday-emr-launcher-RunJobFlow"
  description = "Allow intraday emr-launcher to run job flow"
  policy      = data.aws_iam_policy_document.intraday_emr_launcher_runjobflow.json

  tags = {
    Name        = "intraday-emr-launcher-RunJobFlow",
    Persistence = "Ignore"
  }
}

resource "aws_iam_policy" "intraday_emr_launcher_passrole" {
  name        = "intraday-emr-launcher-PassRole"
  description = "Allow intraday emr-launcher to pass role"
  policy      = data.aws_iam_policy_document.intraday_emr_launcher_pass_role.json

  tags = {
    Name        = "intraday-emr-launcher-PassRole",
    Persistence = "Ignore"
  }
}

resource "aws_iam_policy" "intraday_emr_launcher_getsecrets" {
  name        = "intraday-emr-launcher-getsecrets"
  description = "Allow intraday emr-launcher emr-launcher to get metastore secret"
  policy      = data.aws_iam_policy_document.intraday_emr_launcher_getsecrets.json

  tags = {
    Name        = "intraday-emr-launcher-getsecrets",
    Persistence = "Ignore"
  }
}

resource "aws_iam_role_policy_attachment" "intraday_emr_launcher_readS3" {
  role       = aws_iam_role.intraday_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.intraday_emr_launcher_read_s3.arn
}

resource "aws_iam_role_policy_attachment" "intraday_emr_launcher_runjobflow" {
  role       = aws_iam_role.intraday_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.intraday_emr_launcher_runjobflow.arn
}

resource "aws_iam_role_policy_attachment" "intraday_emr_launcher_passrole" {
  role       = aws_iam_role.intraday_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.intraday_emr_launcher_passrole.arn
}


resource "aws_iam_role_policy_attachment" "intraday_emr_launcher_policy_execution" {
  role       = aws_iam_role.intraday_emr_launcher_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "intraday_emr_launcher_getsecrets" {
  role       = aws_iam_role.intraday_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.intraday_emr_launcher_getsecrets.arn
}


resource "aws_sns_topic_subscription" "intraday_trigger" {
  topic_arn = aws_sns_topic.hbase_incremental_refresh_sns.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.intraday_emr_launcher.arn
}

resource "aws_lambda_permission" "intraday_emr_launcher" {
  statement_id  = "LaunchIncrementalEMRLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.intraday_emr_launcher.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.hbase_incremental_refresh_sns.arn
}
