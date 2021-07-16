locals {
  collections_secret_name = "/ingest-replica/collections"

  persistence_tag_value = {
    development = "mon-fri,08:00-18:00"
    qa          = "Ignore"
    integration = "mon-fri,08:00-18:00"
    preprod     = "Ignore"
    production  = "Ignore"
  }

  auto_shutdown_tag_value = {
    development = "True"
    qa          = "False"
    integration = "True"
    preprod     = "False"
    production  = "False"
  }

  overridden_tags = {
    Role         = "intraday"
    Owner        = "dataworks-aws-ingest-replica"
    Persistence  = local.persistence_tag_value[local.environment]
    AutoShutdown = local.auto_shutdown_tag_value[local.environment]
  }

  common_repo_tags = merge(module.dataworks_common.common_tags, local.overridden_tags)

  management_account = {
    development = "management-dev"
    qa          = "management-dev"
    integration = "management-dev"
    preprod     = "management"
    production  = "management"
  }

  crypto_workspace = {
    management-dev = "management-dev"
    management     = "management"
  }

  emr_cluster_name = "intraday-incremental"

  emr_log_level = {
    development = "DEBUG"
    qa          = "DEBUG"
    integration = "DEBUG"
    preprod     = "INFO"
    production  = "INFO"
  }

  input_bucket_business_data_root = "business-data"
  hbase_rootdir_prefix            = "${local.input_bucket_business_data_root}/${var.hbase_rootdir[local.environment]}"
  hbase_rootdir                   = "${data.terraform_remote_state.ingest.outputs.s3_buckets["input_bucket"]}/${local.hbase_rootdir_prefix}"

  emr_applications = {
    development = ["HBase", "Hive", "Spark"]
    qa          = ["HBase", "Hive", "Spark"]
    integration = ["HBase", "Hive", "Spark"]
    preprod     = ["HBase", "Hive", "Spark"]
    production  = ["HBase", "Hive", "Spark"]
  }

  ingest_emr_bootstrap_scripts_s3_prefix   = "component/ingest_replica/bootstrap_scripts"
  ingest_emr_step_scripts_s3_prefix        = "component/ingest_replica/step_scripts"
  ingest_emr_configuration_files_s3_prefix = "emr/ingest_replica"


  intraday_truststore_certs = {
    development = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem"
    qa          = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem"
    integration = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem"
    preprod     = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem"
    production  = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/ucfs/root_ca_old.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket["id"]}/ca_certificates/dataworks/dataworks_root_ca.pem"
  }

  intraday_truststore_aliases = {
    development = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    qa          = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    integration = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    preprod     = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    production  = ["ucfs_ca", "ucfs_ca_old", "dataworks_root_ca", "dataworks_mgt_root_ca"]
  }

  dns_subdomain = {
    development = ".dev"
    qa          = ".qa"
    integration = ".int"
    preprod     = ".pre"
    production  = ""
  }

  keep_cluster_alive = {
    development = false
    qa          = false
    integration = false
    preprod     = false
    production  = false
  }
}
