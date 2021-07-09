resource "aws_dynamodb_table" "job_status" {
  name         = "intra-day"
  hash_key     = "CorrelationId"
  range_key    = "Collection"
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
    name = "Collection"
    type = "S"
  }

  global_secondary_index {
    hash_key           = "Collection"
    range_key          = "TriggeredTime"
    name               = "byCollection"
    projection_type    = "INCLUDE"
    non_key_attributes = ["JobStatus", "ProcessedDataStart", "ProcessedDataEnd"]
  }

  tags = { Name = "hbase_incremental_refresh" }
}