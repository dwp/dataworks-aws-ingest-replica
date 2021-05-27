data "local_file" "start_ssm_script" {
  filename = "files/bootstrap/start_ssm.sh"
}

data "local_file" "amazon_root_ca_1" {
  filename = "files/bootstrap/AmazonRootCA1.pem"
}

resource "aws_s3_bucket_object" "installer" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/installer.sh"
  content = templatefile("files/bootstrap/installer.sh",
    {
      full_proxy    = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy = join(",", data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["no_proxy_list"])
    }
  )

  tags = {
    Name = "hbase-replica-installer"
  }
}

resource "aws_s3_bucket_object" "certificate_setup" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/certificate_setup.sh"
  content = templatefile("files/bootstrap/certificate_setup.sh",
    {
      aws_default_region            = "eu-west-2"
      acm_cert_arn                  = aws_acm_certificate.emr_replica_hbase.arn
      private_key_alias             = "private_key"
      truststore_aliases            = join(",", local.ingest_hbase_truststore_aliases[local.environment])
      truststore_certs              = local.ingest_hbase_truststore_certs[local.environment]
      dks_endpoint                  = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]
      s3_script_amazon_root_ca1_pem = aws_s3_bucket_object.amazon_root_ca1_pem.id
      s3_scripts_bucket             = data.terraform_remote_state.common.outputs.config_bucket["id"]
      full_proxy                    = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy                 = join(",", data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["no_proxy_list"])
  })

  tags = { Name = "hbase-replica-certificate-setup" }
}

resource "aws_s3_bucket_object" "unique_hostname" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.replica_emr_bootstrap_scripts_s3_prefix}/set_unique_hostname.sh"
  content = templatefile("files/bootstrap/set_unique_hostname.sh",
    {
      aws_default_region = "eu-west-2"
      full_proxy         = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy      = join(",", data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["no_proxy_list"])
      name               = "hbase-replica"
  })

  tags = { Name = "hbase-replica-set-unique-hostname" }
}

resource "aws_s3_bucket_object" "start_ssm_script" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key        = "${local.replica_emr_bootstrap_scripts_s3_prefix}/start_ssm.sh"
  content    = data.local_file.start_ssm_script.content
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]

  tags = { Name = "hbase-replica-start-ssm-script" }
}

resource "aws_s3_bucket_object" "amazon_root_ca1_pem" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key        = "${local.replica_emr_bootstrap_scripts_s3_prefix}/AmazonRootCA1.pem"
  content    = data.local_file.amazon_root_ca_1.content
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]

  tags = { Name = "amazon-root-ca1-pem" }
}

