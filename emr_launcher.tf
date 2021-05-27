variable "emr_launcher_zip" {
  type = map(string)

  default = {
    base_path = ""
    version   = ""
  }
}

resource "aws_lambda_function" "incremental_ingest_replica_emr_launcher" {
  filename      = "${var.emr_launcher_zip["base_path"]}/emr-launcher-${var.emr_launcher_zip["version"]}.zip"
  description   = "Launches hbase-replica for incremental dataset generation"
  function_name = "incremental_ingest_replica_emr_launcher"
  role          = aws_iam_role.incremental_ingest_replica_emr_launcher_lambda.arn
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
      EMR_LAUNCHER_CONFIG_S3_FOLDER = local.replica_emr_configuration_files_s3_prefix
      EMR_LAUNCHER_LOG_LEVEL        = "debug"
    }
  }

  tags = { Name = "incremental_ingest_replica_emr_launcher" }
}

resource "aws_iam_role" "incremental_ingest_replica_emr_launcher_lambda" {
  name               = "incremental-ingest-replica-emr-launcher-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.incremental_ingest_replica_emr_launcher_assume_policy.json

  tags = { Name = "incremental-ingest-replica-emr-launcher-lambda" }
}

data "aws_iam_policy_document" "incremental_ingest_replica_emr_launcher_assume_policy" {
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

data "aws_iam_policy_document" "incremental_ingest_replica_emr_launcher_read_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.common.outputs.config_bucket["id"]}/${local.replica_emr_configuration_files_s3_prefix}/*"
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

data "aws_iam_policy_document" "incremental_ingest_replica_emr_launcher_runjobflow" {
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

data "aws_iam_policy_document" "incremental_ingest_replica_emr_launcher_pass_role" {
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

data "aws_iam_policy_document" "incremental_ingest_replica_emr_launcher_getsecrets" {
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

resource "aws_iam_policy" "incremental_ingest_replica_repository_emr_launcher_read_s3" {
  name        = "incremental-ingest-replica-ReadS3"
  description = "Allow incremental-ingest-replica emr-launcher to read from S3 bucket"
  policy      = data.aws_iam_policy_document.incremental_ingest_replica_emr_launcher_read_s3.json

  tags = { Name = "incremental-ingest-replica-ReadS3" }
}

resource "aws_iam_policy" "incremental_ingest_replica_emr_launcher_runjobflow" {
  name        = "incremental-ingest-replica-RunJobFlow"
  description = "allow incremental-ingest-replica emr-launcher to run job flow"
  policy      = data.aws_iam_policy_document.incremental_ingest_replica_emr_launcher_runjobflow.json

  tags = { Name = "incremental-ingest-replica-RunJobFlow" }
}

resource "aws_iam_policy" "incremental_ingest_replica_emr_launcher_pass_role" {
  name        = "incremental-ingest-replica-PassRole"
  description = "Allow incremental-ingest-replica emr-launcher to pass role"
  policy      = data.aws_iam_policy_document.incremental_ingest_replica_emr_launcher_pass_role.json

  tags = { Name = "incremental-ingest-replica-PassRole" }
}

resource "aws_iam_policy" "incremental_ingest_replica_emr_launcher_getsecrets" {
  name        = "incremental-ingest-replica-getsecrets"
  description = "Allow incremental-ingest-replica emr-launcher to get metastore secret"
  policy      = data.aws_iam_policy_document.incremental_ingest_replica_emr_launcher_getsecrets.json

  tags = { Name = "incremental-ingest-replica-getsecrets" }
}

resource "aws_iam_role_policy_attachment" "incremental_ingest_replica_emr_launcher_read_s3" {
  role       = aws_iam_role.incremental_ingest_replica_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.incremental_ingest_replica_repository_emr_launcher_read_s3.arn
}

resource "aws_iam_role_policy_attachment" "incremental_ingest_replica_emr_launcher_runjobflow" {
  role       = aws_iam_role.incremental_ingest_replica_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.incremental_ingest_replica_emr_launcher_runjobflow.arn
}

resource "aws_iam_role_policy_attachment" "incremental_ingest_replica_emr_launcher_pass_role" {
  role       = aws_iam_role.incremental_ingest_replica_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.incremental_ingest_replica_emr_launcher_pass_role.arn
}


resource "aws_iam_role_policy_attachment" "incremental_ingest_replica_emr_launcher_policy_execution" {
  role       = aws_iam_role.incremental_ingest_replica_emr_launcher_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "incremental_ingest_replica_emr_launcher_getsecrets" {
  role       = aws_iam_role.incremental_ingest_replica_emr_launcher_lambda.name
  policy_arn = aws_iam_policy.incremental_ingest_replica_emr_launcher_getsecrets.arn
}


resource "aws_sns_topic_subscription" "incremental_trigger_subscription" {
  topic_arn = aws_sns_topic.hbase_incremental_refresh_sns.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.hbase_incremental_refresh_lambda.arn
}

resource "aws_lambda_permission" "adg_emr_launcher_incrementals_subscription_eccs" {
  statement_id  = "LaunchIncrementalEMRLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incremental_ingest_replica_emr_launcher.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.hbase_incremental_refresh_sns.arn
}
