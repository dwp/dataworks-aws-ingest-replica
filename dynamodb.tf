resource "aws_dynamodb_table" "hbase_incremental_refresh_dynamodb" {
  name           = "hbase_incremental_refresh"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "JOB_STATUS"
  range_key      = "JOB_START_TIME"

  attribute {
    name = "JOB_STATUS"
    type = "S"
  }

  attribute {
    name = "JOB_START_TIME"
    type = "S"
  }

  attribute {
    name = "JOB_END_TIME"
    type = "S"
  }

  local_secondary_index {
    name            = "JOB_STATUS-JOB_FINISH_TIME-idx"
    range_key       = "JOB_END_TIME"
    projection_type = "ALL"
  }

  tags = { Name = "hbase_incremental_refresh" }
}