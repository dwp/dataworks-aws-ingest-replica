locals {
  pyspark_log_path = "/var/log/adg_incremental_step.log"
}

resource "aws_s3_object" "configurations_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_configuration_files_s3_prefix}/configurations.yaml"
  content = templatefile("files/emr-config/configurations.yaml.tpl",
    {
      //    hbase-site
      hbase_rootdir                   = local.hbase_full_dir
      core_instance_count             = var.hbase_core_instance_count[local.environment]
      hbase_client_scanner_timeout_ms = var.hbase_client_scanner_timeout_ms[local.environment]
      hbase_assignment_usezk          = var.hbase_assignment_usezk[local.environment]

      //    hbase
      hbase_emr_storage_mode = var.hbase_emr_storage_mode[local.environment]

      //    emrfs-site
      hbase_fs_multipart_th_fraction_parts_completed = var.hbase_fs_multipart_th_fraction_parts_completed[local.environment]
      hbase_s3_maxconnections                        = var.hbase_s3_maxconnections[local.environment]
      hbase_s3_max_retry_count                       = var.hbase_s3_max_retry_count[local.environment]
      hive_metastore_username                        = data.terraform_remote_state.internal_compute.outputs.metadata_store_users["hbase_read_replica_writer"]["username"]
      hive_metastore_pwd                             = data.terraform_remote_state.internal_compute.outputs.metadata_store_users["hbase_read_replica_writer"]["secret_name"]
      hive_metastore_endpoint                        = data.terraform_remote_state.internal_compute.outputs.hive_metastore_v2["endpoint"]
      hive_metastore_database_name                   = data.terraform_remote_state.internal_compute.outputs.hive_metastore_v2["database_name"]
      s3_published_bucket                            = data.terraform_remote_state.common.outputs.published_bucket["id"]
  })

  tags = { Name = "configurations.yaml" }
}

resource "aws_s3_object" "cluster_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_configuration_files_s3_prefix}/cluster.yaml"
  content = templatefile("files/emr-config/cluster.yaml.tpl",
    {
      ami_id                 = var.emr_al2_ami_id
      emr_release            = var.emr_release[local.environment]
      s3_log_bucket          = data.terraform_remote_state.security-tools.outputs.logstore_bucket["id"]
      s3_log_prefix          = aws_s3_object.intraday_emr_logs_folder.id
      emr_cluster_name       = local.emr_cluster_name
      security_configuration = aws_emr_security_configuration.intraday_emr.id

      scale_down_behaviour = "TERMINATE_AT_TASK_COMPLETION"
      service_role         = aws_iam_role.emr_service.arn
      instance_profile     = aws_iam_instance_profile.intraday_emr.id
      spark_applications   = local.emr_applications[local.environment]
  })

  tags = { Name = "cluster.yaml" }
}

resource "aws_s3_object" "instances_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_configuration_files_s3_prefix}/instances.yaml"
  content = templatefile("files/emr-config/instances.yaml.tpl",
    {
      keep_cluster_alive = local.keep_cluster_alive[local.environment]

      add_master_sg_id         = aws_security_group.intraday_emr_common.id
      add_slave_sg_id          = aws_security_group.intraday_emr_common.id
      ec2_subnet_id            = data.terraform_remote_state.internal_compute.outputs.hbase_emr_subnet["id"][0]
      emr_managed_master_sg_id = aws_security_group.intraday_emr_master.id
      emr_managed_slave_sg_id  = aws_security_group.intraday-emr-slave.id
      service_access_sg_id     = aws_security_group.intraday_emr_service.id

      master_instance_count        = var.hbase_master_instance_count[local.environment]
      master_instance_type         = var.hbase_master_instance_type[local.environment]
      master_instance_ebs_vol_gb   = var.hbase_master_ebs_size[local.environment]
      master_instance_ebs_vol_type = var.hbase_master_ebs_type[local.environment]

      core_instance_count        = var.hbase_core_instance_count[local.environment]
      core_instance_type         = var.hbase_core_instance_type_one[local.environment]
      core_instance_ebs_vol_gb   = var.hbase_core_ebs_size[local.environment]
      core_instance_ebs_vol_type = var.hbase_core_ebs_type[local.environment]
  })

  tags = { Name = "instances.yaml" }
}

resource "aws_s3_object" "steps_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_configuration_files_s3_prefix}/steps.yaml"
  content = templatefile("files/emr-config/steps.yaml.tpl",
    {
      s3_config_bucket        = data.terraform_remote_state.common.outputs.config_bucket["id"]
      download_scripts_sh_key = aws_s3_object.download_scripts.key

      pyspark_action_on_failure = "TERMINATE_CLUSTER"
  })

  tags = { Name = "steps.yaml" }

}

resource "aws_s3_object" "generate_dataset_from_hbase" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_step_scripts_s3_prefix}/generate_dataset_from_hbase.py"
  content = templatefile("files/steps/generate_dataset_from_hbase.py",
    {
      dks_decrypt_endpoint      = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]
      log_path                  = local.pyspark_log_path
      incremental_output_bucket = data.terraform_remote_state.common.outputs.published_bucket["id"]
      incremental_output_prefix = "intraday/"
      collections_secret_name   = local.collections_secret_name
      job_status_table_name     = aws_dynamodb_table.intraday_job_status.name
  })

  tags = { Name = "emr-step-generate-dataset-from-hbase" }
}

resource "aws_s3_object" "generate_dataset_from_adg" {
  bucket  = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key     = "${local.ingest_emr_step_scripts_s3_prefix}/generate_dataset_from_adg.py"
  content = file("files/steps/generate_dataset_from_adg.py")

  tags = { Name = "emr-step-generate-dataset-from-adg" }
}


resource "aws_s3_object" "download_scripts" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/download_scripts.sh"
  content = templatefile("files/bootstrap/download_scripts.sh",
    {
      EMR_LOG_LEVEL              = local.emr_log_level[local.environment]
      ENVIRONMENT_NAME           = local.environment
      S3_COMMON_LOGGING_SHELL    = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket["id"], data.terraform_remote_state.common.outputs.application_logging_common_file["s3_id"])
      S3_LOGGING_SHELL           = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket["id"], aws_s3_object.logging_sh.key)
      bootstrap_scripts_location = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket["id"], local.ingest_emr_bootstrap_scripts_s3_prefix)
      step_scripts_location      = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket["id"], local.ingest_emr_step_scripts_s3_prefix)
  })

  tags = { Name = "download_scripts" }
}

resource "aws_s3_object" "logging_sh" {
  bucket  = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key     = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/logging.sh"
  content = file("files/bootstrap/logging.sh")

  tags = { Name = "logging" }
}

resource "aws_s3_object" "cloudwatch_sh" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/cloudwatch.sh"
  content = templatefile("files/bootstrap/cloudwatch.sh",
    {
      cwa_metrics_collection_interval = local.cw_agent_collection_interval
      cwa_namespace                   = local.cw_agent_namespace
      cwa_log_group_name              = local.cw_agent_lg_name
      cwa_bootstrap_loggrp_name       = local.cw_agent_bootstrap_lg_name
      cwa_steps_loggrp_name           = local.cw_agent_steps_lg_name
      cwa_yarnspark_loggrp_name       = local.cw_agent_yarnspark_lg_name
      cwa_tests_loggrp_name           = local.cw_agent_tests_lg_name
      emr_release                     = var.emr_release[local.environment]
      aws_default_region              = var.region
      step_log_path                   = local.pyspark_log_path
  })

  tags = { Name = "cloudwatch" }
}
