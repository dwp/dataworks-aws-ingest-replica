locals {

  input_bucket_business_data_root = "business-data"
  hbase_rootdir_prefix            = "${local.input_bucket_business_data_root}/${var.hbase_rootdir[local.environment]}"
  hbase_rootdir                   = "${data.terraform_remote_state.ingest.outputs.s3_buckets.input_bucket}/${local.hbase_rootdir_prefix}"

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

  emr_applications = {
    development = ["Spark", "Hive", "HBase", "Ganglia"]
  }

  ingest_emr_bootstrap_scripts_s3_prefix = "component/hbase_read_replica/bootstrap_scripts"

  ingest_hbase_truststore_certs = {
    development = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem"
    qa          = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem"
    integration = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem"
    preprod     = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem"
    production  = "s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/ucfs/root_ca.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/ucfs/root_ca_old.pem,s3://${data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem,s3://${data.terraform_remote_state.mgmt_ca.outputs.public_cert_bucket.id}/ca_certificates/dataworks/dataworks_root_ca.pem"
  }

  ingest_hbase_truststore_aliases = {
    development = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    qa          = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    integration = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    preprod     = ["ucfs_ca", "dataworks_root_ca", "dataworks_mgt_root_ca"]
    production  = ["ucfs_ca", "ucfs_ca_old", "dataworks_root_ca", "dataworks_mgt_root_ca"]
  }

  s3_manifest_prefix = {
    development = "business-data/manifest"
    qa          = "business-data/manifest"
    integration = "business-data/manifest"
    preprod     = "business-data/manifest"
    production  = "business-data/manifest"
  }
}