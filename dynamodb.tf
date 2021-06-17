resource "aws_dynamodb_table" "job_status" {
  name         = "intra-day"
  hash_key     = "CorrelationId"
  range_key    = "TriggeredTime"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "CorrelationId"
    type = "S"
  }

  attribute {
    name = "TriggeredTime"
    type = "N"
  }

  attribute {
    name = "JobStatus"
    type = "S"
  }

  global_secondary_index {
    hash_key           = "JobStatus"
    range_key          = "TriggeredTime"
    name               = "StatusIndex"
    projection_type    = "INCLUDE"
    non_key_attributes = ["ProcessedDataStart", "ProcessedDataEnd"]
  }

  tags = { Name = "hbase_incremental_refresh" }
}