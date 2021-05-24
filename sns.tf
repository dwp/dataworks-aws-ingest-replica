resource "aws_sns_topic" "hbase_incremental_refresh_sns" {
  name = "hbase_incremental_refresh"
}

resource "aws_sns_topic_policy" "hbase_incremental_refresh_topic_policy" {
  arn = aws_sns_topic.hbase_incremental_refresh_sns.arn

//  policy = data.aws_iam_policy_document.hbase_incremental_refresh_topic_policy.json
  policy = jsonencode({
    "Version": "2012-10-17",
    "Id": "hbase_incremental_refresh_ID",
    "Statement": [
      {
        "Sid": "statement_ID",
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
          "SNS:Receive"
        ],
        "Resource": "${aws_sns_topic.hbase_incremental_refresh_sns.arn}",
        "Condition": {
          "StringEquals": {
            "AWS:SourceOwner": "${local.account[local.environment]}"
          }
        }
      }
    ]
  })
}

