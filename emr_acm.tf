//resource "aws_acm_certificate" "emr_ingest_hbase" {
//  certificate_authority_arn = data.terraform_remote_state.certificate_authority.outputs.root_ca.arn
//  domain_name               = "ingest-hbase${local.dns_subdomain[local.environment]}.dataworks.dwp.gov.uk"
//  tags = merge(
//    local.common_tags,
//    {
//      Name = "emr-ingest-hbase"
//    },
//  )
//}
//
//data "aws_iam_policy_document" "emr_ingest_hbase_acm" {
//  statement {
//    effect = "Allow"
//
//    actions = [
//      "acm:ExportCertificate",
//    ]
//
//    resources = [
//      aws_acm_certificate.emr_ingest_hbase.arn
//    ]
//  }
//}
//
//resource "aws_iam_policy" "emr_ingest_hbase_acm" {
//  name        = "ACMExportIngestHBaseCert"
//  description = "Allow export of Ingest HBase certificate"
//  policy      = data.aws_iam_policy_document.emr_ingest_hbase_acm.json
//}
