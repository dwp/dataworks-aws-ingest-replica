########        Additional EMR cluster config
resource "aws_emr_security_configuration" "intraday_emr" {
  name = "intraday_emr"

  configuration = jsonencode(
    {
      EncryptionConfiguration : {
        EnableInTransitEncryption : false,
        EnableAtRestEncryption : true,
        AtRestEncryptionConfiguration : {
          S3EncryptionConfiguration = {
            EncryptionMode             = "CSE-Custom"
            S3Object                   = "s3://${data.terraform_remote_state.management_artefact.outputs.artefact_bucket["id"]}/emr-encryption-materials-provider/encryption-materials-provider-all.jar"
            EncryptionKeyProviderClass = "uk.gov.dwp.dataworks.dks.encryptionmaterialsprovider.DKSEncryptionMaterialsProvider"
          }
          LocalDiskEncryptionConfiguration : {
            EnableEbsEncryption : true,
            EncryptionKeyProviderType : "AwsKms",
            AwsKmsKey : data.terraform_remote_state.security-tools.outputs.ebs_cmk["arn"]
          }
        }
      }
    }
  )
}

#
########        IAM
########        Instance role & profile
resource "aws_iam_role" "intraday_emr" {
  name               = "intraday-emr"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = { Name = "intraday-emr" }
}

resource "aws_iam_instance_profile" "intraday_emr" {
  name = "intraday-emr"
  role = aws_iam_role.intraday_emr.id

  tags = { Name = "intraday-emr" }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#        Attach AWS policies
resource "aws_iam_role_policy_attachment" "emr_for_ec2_attachment" {
  role       = aws_iam_role.intraday_emr.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ec2_for_ssm_attachment" {
  role       = aws_iam_role.intraday_emr.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

#        Create and attach custom policies
data "aws_iam_policy_document" "intraday_emr_main" {
  statement {
    sid    = "ListInputBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn["input_bucket"],
    ]
  }

  statement {
    sid    = "HbaseRootDir"
    effect = "Allow"

    actions = [
      "s3:GetObject*",
      "s3:DeleteObject*",
      "s3:PutObject*",
    ]

    resources = [
      # This must track the hbase root dir
      "arn:aws:s3:::${local.hbase_root_bucket}/${local.hbase_root_prefix}/*",
    ]
  }

  statement {
    sid    = "AllowGetandListOnPublishedBucket"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.published_bucket["arn"],
    ]
  }

  statement {
    sid    = "AllowGetPutDeleteOnPublishedDirs"
    effect = "Allow"

    actions = [
      "s3:GetObject*",
      "s3:DeleteObject*",
      "s3:PutObject*",
    ]

    resources = [
      "${data.terraform_remote_state.common.outputs.published_bucket["arn"]}/intraday/*",
      "${data.terraform_remote_state.common.outputs.published_bucket["arn"]}/intraday-tests/*",
    ]
  }

  statement {
    sid    = "AllowKMSForPublished"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.published_bucket_cmk["arn"],
    ]
  }

  statement {
    sid    = "ListConfigBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.config_bucket["arn"]
    ]
  }

  statement {
    sid    = "KMSDecryptForConfigBucket"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [
      data.terraform_remote_state.common.outputs.config_bucket_cmk["arn"]
    ]
  }

  statement {
    sid    = "AllowBucketAccessForS3InputBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn["input_bucket"],
    ]
  }

  statement {
    sid    = "AllowGetForInputBucket"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn["input_bucket"]}/*",
    ]
  }

  statement {
    sid    = "AllowKMSDecryptionOfS3InputBucketObj"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [
      data.terraform_remote_state.ingest.outputs.input_bucket_cmk["arn"],
    ]
  }

  statement {
    sid    = "AllowKMSEncryptionOfS3InputBucketObj"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]


    resources = [
      data.terraform_remote_state.ingest.outputs.input_bucket_cmk["arn"],
    ]
  }

  statement {
    sid    = "AllowUseDefaultEbsCmk"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]


    resources = [data.terraform_remote_state.security-tools.outputs.ebs_cmk["arn"]]
  }

  statement {
    sid     = "AllowAccessToArtefactBucket"
    effect  = "Allow"
    actions = ["s3:GetBucketLocation"]

    resources = [data.terraform_remote_state.management_artefact.outputs.artefact_bucket["arn"]]
  }

  statement {
    sid       = "AllowPullFromArtefactBucket"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${data.terraform_remote_state.management_artefact.outputs.artefact_bucket["arn"]}/*"]
  }

  statement {
    sid    = "AllowDecryptArtefactBucket"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [data.terraform_remote_state.management_artefact.outputs.artefact_bucket["cmk_arn"]]
  }

  statement {
    sid    = "AllowIntradayHbaseToGetSecretManagerPassword"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      data.terraform_remote_state.ingest.outputs.metadata_store_secrets["hbasewriter"]["arn"]
    ]
  }

  statement {
    sid    = "ListManifests"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.internal_compute.outputs.manifest_bucket["arn"],
    ]
  }

  statement {
    sid    = "AllowKMSEncryptionOfS3ManifestBucketObj"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]


    resources = [
      data.terraform_remote_state.internal_compute.outputs.manifest_bucket_cmk["arn"]
    ]
  }

  statement {
    sid    = "AllowACM"
    effect = "Allow"

    actions = [
      "acm:*Certificate",
    ]

    resources = [aws_acm_certificate.intraday-emr.arn]
  }

  statement {
    sid    = "GetPublicCerts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket["arn"]]
  }
}

resource "aws_iam_policy" "intraday_S3_main" {
  name        = "intraday-S3-main"
  description = "Allow Intraday Cluster to write HBase data to the input bucket"
  policy      = data.aws_iam_policy_document.intraday_emr_main.json

  tags = { Name = "intraday-S3-main" }
}

resource "aws_iam_role_policy_attachment" "intraday_emr_main" {
  role       = aws_iam_role.intraday_emr.name
  policy_arn = aws_iam_policy.intraday_S3_main.arn
}

data "aws_iam_policy_document" "intraday_emr_ec2" {
  statement {
    sid    = "EnableEC2PermissionsHost"
    effect = "Allow"

    actions = [
      "ec2:ModifyInstanceMetadataOptions",
      "ec2:*Tags",
    ]
    resources = ["arn:aws:ec2:${var.region}:${local.account[local.environment]}:instance/*"]
  }
}

resource "aws_iam_policy" "intraday_emr_ec2" {
  name        = "intraday-emr-ec2"
  description = "Policy to allow access to modify Ec2 tags"
  policy      = data.aws_iam_policy_document.intraday_emr_ec2.json

  tags = { Name = "intraday-emr-ec2" }
}

resource "aws_iam_role_policy_attachment" "intraday_emr_ec2" {
  role       = aws_iam_role.intraday_emr.name
  policy_arn = aws_iam_policy.intraday_emr_ec2.arn
}

#
########        IAM
########        EMR Service role

resource "aws_iam_role" "emr_service" {
  name               = "intraday-emr-service-role"
  assume_role_policy = data.aws_iam_policy_document.emr_assume_role.json

  tags = { Name = "intraday-emr-service" }
}

data "aws_iam_policy_document" "emr_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["elasticmapreduce.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#        Attach default EMR policy
resource "aws_iam_role_policy_attachment" "emr_attachment" {
  role       = aws_iam_role.emr_service.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

#        Create and attach custom policy to allow use of CMK for EBS encryption
data "aws_iam_policy_document" "emr_ebs_cmk" {
  statement {
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]


    resources = [data.terraform_remote_state.security-tools.outputs.ebs_cmk["arn"]]
  }

  statement {
    effect = "Allow"

    actions = ["kms:CreateGrant"]


    resources = [data.terraform_remote_state.security-tools.outputs.ebs_cmk["arn"]]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "emr_ebs_cmk" {
  name        = "IntradayEmrUseEbsCmk"
  description = "Allow Intraday EMR cluster to use EB CMK for encryption"
  policy      = data.aws_iam_policy_document.emr_ebs_cmk.json

  tags = { Name = "IntradayEmrUseEbsCmk" }
}

resource "aws_iam_role_policy_attachment" "emr_ebs_cmk" {
  role       = aws_iam_role.emr_service.id
  policy_arn = aws_iam_policy.emr_ebs_cmk.arn
}

#
########        Security groups

resource "aws_security_group" "intraday_emr_common" {
  name                   = "intraday-emr-common"
  description            = "Contains rules for both EMR cluster master nodes and EMR cluster slave nodes"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["vpc"]["id"]

  tags = { Name = "intraday-emr-common" }

}


resource "aws_security_group_rule" "vpce_ingress" {
  //todo: move to internal-compute vpc module
  security_group_id = data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["interface_vpce_sg_id"]

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  type                     = "ingress"
  source_security_group_id = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "egress_to_vpce" {
  //todo: move to internal-compute vpc module
  security_group_id = aws_security_group.intraday_emr_common.id

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  type                     = "egress"
  source_security_group_id = data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["interface_vpce_sg_id"]
}


resource "aws_security_group_rule" "intraday_egress_dks" {
  description = "Allow outbound requests to DKS from EMR HBase"
  type        = "egress"
  from_port   = 8443
  to_port     = 8443
  protocol    = "tcp"

  cidr_blocks       = data.terraform_remote_state.crypto.outputs.dks_subnet["cidr_blocks"]
  security_group_id = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "intraday_egress_metadata_store" {
  description              = "Allow outbound requests to Metadata Store DB from intraday EMR"
  type                     = "egress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = data.terraform_remote_state.ingest.outputs.metadata_store["rds"]["sg_id"]
  security_group_id        = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "intraday_ingress_metadata_store" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.intraday_emr_common.id
  security_group_id        = data.terraform_remote_state.ingest.outputs.metadata_store["rds"]["sg_id"]
  description              = "Allow inbound requests from Metadata Store DB to intraday EMR"
}

resource "aws_security_group_rule" "emr_common_egress_s3_vpce_https" {
  description = "Allow outbound HTTPS traffic from EMR nodes to S3 VPC Endpoint"
  type        = "egress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"

  prefix_list_ids   = [data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["prefix_list_ids"]["s3"]]
  security_group_id = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "emr_common_egress_s3_vpce_http" {
  description = "Allow outbound HTTP (YUM) traffic from EMR nodes to S3 VPC Endpoint"
  type        = "egress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"

  prefix_list_ids   = [data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["prefix_list_ids"]["s3"]]
  security_group_id = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "emr_common_egress_dynamodb_vpce_https" {
  description = "Allow outbound HTTPS traffic from EMR nodes to DynamoDB VPC Endpoint"
  type        = "egress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"

  prefix_list_ids   = [data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["prefix_list_ids"]["dynamodb"]]
  security_group_id = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "emr_common_egress_between_nodes" {
  description              = "Allow outbound traffic between EMR nodes"
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.intraday_emr_common.id
  security_group_id        = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "egress_emr_common_to_internet" {
  description              = "Allow EMR access to Internet Proxy (for ACM-PCA)"
  type                     = "egress"
  source_security_group_id = data.terraform_remote_state.internal_compute.outputs.internet_proxy["sg"]
  //  source_security_group_id = aws_security_group.internet_proxy_endpoint.id
  protocol          = "tcp"
  from_port         = 3128
  to_port           = 3128
  security_group_id = aws_security_group.intraday_emr_common.id
}

resource "aws_security_group_rule" "ingress_emr_common_to_internet" {
  description              = "Allow EMR access to Internet Proxy (for ACM-PCA)"
  type                     = "ingress"
  source_security_group_id = aws_security_group.intraday_emr_common.id
  protocol                 = "tcp"
  from_port                = 3128
  to_port                  = 3128
  security_group_id        = data.terraform_remote_state.internal_compute.outputs.internet_proxy["sg"]
  //  security_group_id        = aws_security_group.internet_proxy_endpoint.id
}

# EMR will add more rules to this SG during cluster provisioning;
# see https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-man-sec-groups.html#emr-sg-elasticmapreduce-master-private
resource "aws_security_group" "intraday_emr_master" {
  name                   = "intraday-emr-master"
  description            = "Contains rules for EMR cluster master nodes"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["vpc"]["id"]

  tags = { Name = "intraday-emr-master" }
}

# EMR will add more rules to this SG during cluster provisioning;
# see https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-man-sec-groups.html#emr-sg-elasticmapreduce-master-private
resource "aws_security_group" "intraday-emr-slave" {
  name                   = "intraday-emr-slave"
  description            = "Contains rules for EMR cluster slave nodes"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["vpc"]["id"]

  tags = { Name = "intraday-emr-slave" }
}


# EMR 5.30.0+ requirement
resource "aws_security_group_rule" "emr_server_ingress_from_service" {
  description              = "Required by EMR"
  type                     = "ingress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.intraday_emr_master.id
  security_group_id        = aws_security_group.intraday_emr_service.id
}

resource "aws_security_group" "intraday_emr_service" {
  name                   = "intraday-emr-service"
  description            = "Contains rules automatically added by the EMR service itself. See https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-man-sec-groups.html#emr-sg-elasticmapreduce-sa-private"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc["vpc"]["vpc"]["id"]

  tags = { Name = "intraday-emr-service" }
}

resource "aws_s3_bucket_object" "intraday_emr_logs_folder" {
  bucket = data.terraform_remote_state.security-tools.outputs.logstore_bucket["id"]
  acl    = "private"
  key    = "emr/aws-intraday/"
  source = "/dev/null"

  tags = { Name = "intraday-emr-logs-folder" }
}
