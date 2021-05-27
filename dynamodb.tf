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
  
  tags = { Name = "hbase_incremental_refresh" }
}