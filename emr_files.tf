resource "aws_s3_bucket_object" "configurations_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_configuration_files_s3_prefix}/configurations.yaml"
  content = templatefile("files/emr-config/configurations.yaml.tpl",
    {
      //    hbase-site
      hbase_rootdir                   = local.hbase_rootdir
      core_instance_count             = var.hbase_core_instance_count[local.environment]
      hbase_client_scanner_timeout_ms = var.hbase_client_scanner_timeout_ms[local.environment]
      hbase_assignment_usezk          = var.hbase_assignment_usezk[local.environment]

      //    hbase
      hbase_emr_storage_mode = var.hbase_emr_storage_mode[local.environment]

      //    emrfs-site
      hbase_fs_multipart_th_fraction_parts_completed = var.hbase_fs_multipart_th_fraction_parts_completed[local.environment]
      hbase_s3_maxconnections                        = var.hbase_s3_maxconnections[local.environment]
      hbase_s3_max_retry_count                       = var.hbase_s3_max_retry_count[local.environment]
  })

  tags = merge(
    local.common_tags,
    { Name = "configurations.yaml" }
  )
}

resource "aws_s3_bucket_object" "cluster_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_configuration_files_s3_prefix}/cluster.yaml"
  content = templatefile("files/emr-config/cluster.yaml.tpl",
    {
      ami_id                 = var.emr_al2_ami_id
      s3_log_bucket          = data.terraform_remote_state.security-tools.outputs.logstore_bucket["id"]
      s3_log_prefix          = aws_s3_bucket_object.emr_logs_folder.id
      emr_cluster_name       = local.emr_cluster_name
      security_configuration = aws_emr_security_configuration.ingest_read_replica.id

      scale_down_behaviour = "TERMINATE_AT_TASK_COMPLETION"
      service_role         = aws_iam_role.emr_service.arn
      instance_profile     = aws_iam_instance_profile.emr_hbase_replica.id
  })

  tags = merge(
    local.common_tags,
    { Name = "cluster.yaml" }
  )
}

resource "aws_s3_bucket_object" "instances_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_configuration_files_s3_prefix}/instances.yaml"
  content = templatefile("files/emr-config/instances.yaml.tpl",
    {
      keep_cluster_alive = local.keep_cluster_alive[local.environment]

      add_master_sg_id         = aws_security_group.replica_emr_hbase_common.id
      add_slave_sg_id          = aws_security_group.replica_emr_hbase_common.id
      ec2_subnet_id            = data.terraform_remote_state.internal_compute.outputs.hbase_emr_subnet["id"][0]
      emr_managed_master_sg_id = aws_security_group.emr_hbase_master.id
      emr_managed_slave_sg_id  = aws_security_group.replica_emr_hbase_slave.id
      service_access_sg_id     = aws_security_group.emr_hbase_service.id

      master_instance_count        = var.hbase_master_instance_count[local.environment]
      master_instance_type         = var.hbase_master_instance_type[local.environment]
      master_instance_ebs_vol_gb   = var.hbase_master_ebs_size[local.environment]
      master_instance_ebs_vol_type = var.hbase_master_ebs_type[local.environment]

      core_instance_count        = var.hbase_core_instance_count[local.environment]
      core_instance_type         = var.hbase_core_instance_type_one[local.environment]
      core_instance_ebs_vol_gb   = var.hbase_core_ebs_size[local.environment]
      core_instance_ebs_vol_type = var.hbase_core_ebs_type[local.environment]
  })

  tags = merge(
    local.common_tags,
  { name = "instances.yaml" })
}

resource "aws_s3_bucket_object" "steps_yaml" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_configuration_files_s3_prefix}/steps.yaml"
  content = templatefile("files/emr-config/steps.yaml.tpl",
    {
      s3_config_bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]

      certificate_setup_sh_key = aws_s3_bucket_object.certificate_setup.key
      unique_hostname_sh_key   = aws_s3_bucket_object.unique_hostname.key
      start_ssm_sh_key         = aws_s3_bucket_object.start_ssm_script.key
      installer_sh_key         = aws_s3_bucket_object.installer.key

      pyspark_action_on_failure = "TERMINATE_CLUSTER"
  })

  tags = merge(
    local.common_tags,
    { name = "steps.yaml" }
  )

}

resource "aws_s3_bucket_object" "generate_dataset_from_hbase" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_step_scripts_s3_prefix}/generate_dataset_from_hbase.py"
  content = templatefile("files/steps/generate_dataset_from_hbase.py",
    {
      dks_decrypt_endpoint = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]
      log_path             = "/var/log/adg_incremental_step.log"
      # todo - temporary output location
      incremental_output_bucket = data.terraform_remote_state.ingest.outputs.s3_buckets["input_bucket"]
      incremental_output_prefix = "business-data/intra-day/"
  })

  tags = merge(
    local.common_tags,
  { Name = "emr-step-generate-dataset-from-hbase" })
}