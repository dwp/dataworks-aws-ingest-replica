resource "aws_s3_bucket_object" "adg_incremental_spark_step" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_step_scripts_s3_prefix}/spark_job.py"
  content = templatefile("files/emr/spark_job.py",
  {
    dks_decrypt_endpoint = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]
    log_path = "/var/log/adg_incremental_step.log"
    # todo - temporary output location
    incremental_output_bucket = data.terraform_remote_state.ingest.outputs.s3_buckets["input_bucket"]
    incremental_output_prefix = "business-data/intra-day/"
  })

  tags = merge(
  local.common_tags,
  {
    Name = "adg-incremental-spark-step"
  },
  )
}