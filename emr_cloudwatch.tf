locals {
  cw_agent_collection_interval = 30
  cw_agent_namespace           = "/app/ingest-replica-incremental"
  cw_agent_lg_name             = "/app/ingest-replica-incremental"
  cw_agent_bootstrap_lg_name   = "/app/ingest-replica-incremental/bootstrap_actions"
  cw_agent_steps_lg_name       = "/app/ingest-replica-incremental/step_logs"
  cw_agent_yarnspark_lg_name   = "/app/ingest-replica-incremental/yarn-spark_logs"
  cw_agent_tests_lg_name       = "/app/ingest-replica-incremental/tests_logs"
}


resource "aws_cloudwatch_log_group" "ingest_replica_incremental" {
  name              = local.cw_agent_lg_name
  retention_in_days = 180
  tags              = { Name = "ingest-replica-incremental" }
}

resource "aws_cloudwatch_log_group" "bootstrap_actions" {
  name              = local.cw_agent_bootstrap_lg_name
  retention_in_days = 180
  tags              = { Name = "ingest-replica-incremental-bootstrap-actions" }
}

resource "aws_cloudwatch_log_group" "steps" {
  name              = local.cw_agent_steps_lg_name
  retention_in_days = 180
  tags              = { Name = "ingest-replica-incremental-steps" }
}

resource "aws_cloudwatch_log_group" "yarn_spark" {
  name              = local.cw_agent_yarnspark_lg_name
  retention_in_days = 180
  tags              = { Name = "ingest-replica-incremental-yarn-spark" }
}

resource "aws_cloudwatch_log_group" "tests" {
  name              = local.cw_agent_tests_lg_name
  retention_in_days = 180
  tags              = { Name = "ingest-replica-incremental-tests" }
}
