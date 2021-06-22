resource "aws_sns_topic" "hbase_incremental_refresh_sns" {
  name = "hbase_incremental_refresh"

  tags = { Name = "hbase_incremental_refresh" }
}

resource "aws_sns_topic_policy" "ingest_replica_trigger" {
  arn    = aws_sns_topic.hbase_incremental_refresh_sns.arn
  policy = data.aws_iam_policy_document.ingest_replica_refresh.json
}

data "aws_iam_policy_document" "ingest_replica_refresh" {
  policy_id = "__default_policy_ID"

  statement {
    sid = "__default_statement_ID"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:Receive",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        local.account[local.environment],
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.hbase_incremental_refresh_sns.arn,
    ]
  }
}
