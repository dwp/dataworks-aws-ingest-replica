resource "aws_cloudwatch_event_rule" "intraday_terminated_with_errors" {
  name          = "intraday_terminated_with_errors"
  description   = "Sends failed message to slack when intraday cluster terminates with errors"
  event_pattern = <<EOF
{
  "source": [
    "aws.emr"
  ],
  "detail-type": [
    "EMR Cluster State Change"
  ],
  "detail": {
    "state": [
      "TERMINATED_WITH_ERRORS"
    ],
    "name": [
      "intraday-incremental"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_metric_alarm" "intraday_failed_with_errors" {
  alarm_name                = "intraday_failed_with_errors"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  metric_name               = "TriggeredRules"
  namespace                 = "AWS/Events"
  period                    = "60"
  statistic                 = "Sum"
  threshold                 = "1"
  alarm_description         = "This metric monitors cluster termination with errors"
  insufficient_data_actions = []
  alarm_actions             = [data.terraform_remote_state.security-tools.outputs.sns_topic_london_monitoring.arn]
  dimensions = {
    RuleName = aws_cloudwatch_event_rule.intraday_terminated_with_errors.name
  }
  tags = merge(
  local.common_tags,
  {
    Name              = "intraday_failed_with_errors",
    notification_type = "Error"
    severity          = "Critical"
  },
  )
}
