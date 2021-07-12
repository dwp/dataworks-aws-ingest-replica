resource "aws_acm_certificate" "intraday-emr" {
  certificate_authority_arn = data.terraform_remote_state.certificate_authority.outputs.root_ca["arn"]
  domain_name               = "intraday${local.dns_subdomain[local.environment]}.dataworks.dwp.gov.uk"
  tags                      = { Name = "intraday-emr" }
}
