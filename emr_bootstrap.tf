data "local_file" "start_ssm_script" {
  filename = "files/bootstrap/start_ssm.sh"
}

data "local_file" "amazon_root_ca_1" {
  filename = "files/bootstrap/AmazonRootCA1.pem"
}

resource "aws_s3_object" "installer" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/installer.sh"
  content = templatefile("files/bootstrap/installer.sh",
    {
      full_proxy    = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy = join(",", data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["no_proxy_list"])
    }
  )

  tags = {
    Name = "intraday-emr-installer"
  }
}

resource "aws_s3_object" "certificate_setup" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/certificate_setup.sh"
  content = templatefile("files/bootstrap/certificate_setup.sh",
    {
      aws_default_region            = "eu-west-2"
      acm_cert_arn                  = aws_acm_certificate.intraday-emr.arn
      private_key_alias             = "private_key"
      truststore_aliases            = join(",", local.intraday_truststore_aliases[local.environment])
      truststore_certs              = local.intraday_truststore_certs[local.environment]
      dks_endpoint                  = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]
      s3_script_amazon_root_ca1_pem = aws_s3_object.amazon_root_ca1_pem.id
      s3_scripts_bucket             = data.terraform_remote_state.common.outputs.config_bucket["id"]
      full_proxy                    = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy                 = join(",", data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["no_proxy_list"])
  })

  tags = { Name = "intraday-emr-certificate-setup" }
}

resource "aws_s3_object" "unique_hostname" {
  bucket = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key    = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/set_unique_hostname.sh"
  content = templatefile("files/bootstrap/set_unique_hostname.sh",
    {
      aws_default_region = "eu-west-2"
      full_proxy         = data.terraform_remote_state.internal_compute.outputs.internet_proxy["url"]
      full_no_proxy      = join(",", data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["no_proxy_list"])
      name               = "hbase-replica"
  })

  tags = { Name = "intraday-emr-set-unique-hostname" }
}

resource "aws_s3_object" "start_ssm_script" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key        = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/start_ssm.sh"
  content    = data.local_file.start_ssm_script.content
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]

  tags = { Name = "intraday-emr-start-ssm-script" }
}

resource "aws_s3_object" "amazon_root_ca1_pem" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket["id"]
  key        = "${local.ingest_emr_bootstrap_scripts_s3_prefix}/AmazonRootCA1.pem"
  content    = data.local_file.amazon_root_ca_1.content
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]

  tags = { Name = "amazon-root-ca1-pem" }
}
