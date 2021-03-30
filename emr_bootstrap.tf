data "local_file" "start_ssm_script" {
  filename = "files/emr/start_ssm.sh"
}

data "local_file" "cloud_watch" {
  filename = "files/emr/start_ssm.sh"
}

data "local_file" "amazon_root_ca_1" {
  filename = "files/emr/AmazonRootCA1.pem"
}

resource "aws_s3_bucket_object" "installer" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/installer.sh"
  content = templatefile("files/emr/installer.sh",
    {
      full_proxy    = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy = join(",", data.terraform_remote_state.internal_compute.outputs.vpc.vpc.no_proxy_list)
    }
  )

  tags = merge(
    local.common_tags,
    {
      Name = "hbase-replica-installer"
    }
  )
}

resource "aws_s3_bucket_object" "certificate_setup" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket.id
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/certificate_setup.sh"
  content = templatefile("files/emr/certificate_setup.sh",
    {
      aws_default_region            = "eu-west-2"
      acm_cert_arn                  = aws_acm_certificate.emr_replica_hbase.arn
      private_key_alias             = "private_key"
      truststore_aliases            = join(",", local.ingest_hbase_truststore_aliases[local.environment])
      truststore_certs              = local.ingest_hbase_truststore_certs[local.environment]
      dks_endpoint                  = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]
      s3_script_amazon_root_ca1_pem = aws_s3_bucket_object.amazon_root_ca1_pem.id
      s3_scripts_bucket             = data.terraform_remote_state.common.outputs.config_bucket.id
      full_proxy                    = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy                 = join(",", data.terraform_remote_state.internal_compute.outputs.vpc.vpc.no_proxy_list)
  })
  tags = merge(
    local.common_tags,
    {
      Name = "hbase-replica-certificate-setup"
    },
  )
}

resource "aws_s3_bucket_object" "unique_hostname" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/set_unique_hostname.sh"
  content = templatefile("files/emr/set_unique_hostname.sh",
    {
      aws_default_region = "eu-west-2"
      full_proxy         = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy      = join(",", data.terraform_remote_state.internal_compute.outputs.vpc.vpc.no_proxy_list)
      name               = "hbase-replica"
  })

  tags = merge(
    local.common_tags,
    {
      Name = "hbase-replica-set-unique-hostname"
    },
  )
}

resource "aws_s3_bucket_object" "start_ssm_script" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key        = "${local.replica_emr_bootstrap_scripts_s3_prefix}/start_ssm.sh"
  content    = data.local_file.start_ssm_script.content
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]

  tags = merge(
    local.common_tags,
    {
      Name = "hbase-replica-start-ssm-script"
    },
  )
}

resource "aws_s3_bucket_object" "generate_download_scripts_script" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/generate_download_scripts_script.sh"
  content = templatefile("files/emr/generate_download_scripts_script.tpl",
    {
      ingest_emr_scripts_location = "s3://${data.terraform_remote_state.common.outputs.config_bucket["id"]}/${local.replica_emr_step_scripts_s3_prefix}"
  })

  tags = merge(
    local.common_tags,
    {
      Name = "generate-download-scripts-script"
    },
  )
}

resource "aws_s3_bucket_object" "amazon_root_ca1_pem" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  key        = "${local.replica_emr_bootstrap_scripts_s3_prefix}/AmazonRootCA1.pem"
  content    = data.local_file.amazon_root_ca_1.content
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn

  tags = merge(
    local.common_tags,
    {
      Name = "amazon-root-ca1-pem"
    },
  )
}

//resource "aws_s3_bucket_object" "cloudwatch_sh" {
//  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
//  key        = "${local.replica_emr_bootstrap_scripts_s3_prefix}/cloudwatch.sh"
//  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
//  content = templatefile("files/ingest_emr/cloudwatch.sh.tpl",
//    {
//      cwa_metrics_collection_interval     = local.cw_agent_metrics_collection_interval
//      cwa_namespace                       = local.cw_agent_namespace_ingest
//      cwa_log_group_name                  = aws_cloudwatch_log_group.ingest_hbase.name
//      cwa_hbase_loggrp_name               = aws_cloudwatch_log_group.ingest_cw_hbase_loggroup.name
//      cwa_hbase_hbck_loggrp_name          = aws_cloudwatch_log_group.ingest_cw_hbase_hbck_loggroup.name
//      cwa_cdl_loggrp_name                 = data.terraform_remote_state.ingest.outputs.corporate_data_loader.log_group_name
//      cwa_hdl_loggrp_name                 = data.terraform_remote_state.ingest.outputs.historic_data_loader.log_group_name
//      cwa_hbase_loggrp_steps_name         = aws_cloudwatch_log_group.ingest_hbase_steps.name
//      cwa_hbase_loggrp_bootstrapping_name = aws_cloudwatch_log_group.ingest_hbase_bootstrapping.name
//      cwa_hbase_loggrp_yarn_name          = aws_cloudwatch_log_group.ingest_hbase_yarn.name
//  })
//
//  tags = merge(
//    local.common_tags,
//    {
//      Name = "cloudwatch-sh"
//    },
//  )
//}