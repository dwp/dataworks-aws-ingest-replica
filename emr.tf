########        Additional EMR cluster config
resource "aws_emr_security_configuration" "ingest_read_replica" {
  name = "ingest_read_replica"

  configuration = jsonencode(
    {
      EncryptionConfiguration : {
        EnableInTransitEncryption : false,
        EnableAtRestEncryption : true,
        AtRestEncryptionConfiguration : {
          S3EncryptionConfiguration = {
            EncryptionMode             = "CSE-Custom"
            S3Object                   = "s3://${data.terraform_remote_state.management_artefact.outputs.artefact_bucket.id}/emr-encryption-materials-provider/encryption-materials-provider-all.jar"
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
resource "aws_iam_role" "emr_hbase_replica" {
  name               = "emr_hbase_replica"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_instance_profile" "emr_hbase_replica" {
  name = "emr_hbase_replica"
  role = aws_iam_role.emr_hbase_replica.id
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
  role       = aws_iam_role.emr_hbase_replica.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ec2_for_ssm_attachment" {
  role       = aws_iam_role.emr_hbase_replica.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

#        Create and attach custom policies
data "aws_iam_policy_document" "hbase_replica_main" {
  statement {
    sid    = "ListInputBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn.input_bucket,
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
      "${data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn.input_bucket}/${local.hbase_rootdir_prefix}/*",
    ]
  }

  statement {
    sid    = "ListConfigBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.config_bucket.arn
    ]
  }

  statement {
    sid    = "IngestConfigBucketScripts"
    effect = "Allow"

    actions = [
      "s3:GetObject*",
    ]

    resources = [
      "${data.terraform_remote_state.common.outputs.config_bucket.arn}/component/ingest_emr/*"
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
      data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
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
      data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn.input_bucket,
    ]
  }

  statement {
    sid    = "AllowGetForInputBucket"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${data.terraform_remote_state.ingest.outputs.s3_input_bucket_arn.input_bucket}/*",
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
      data.terraform_remote_state.ingest.outputs.input_bucket_cmk.arn,
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
      data.terraform_remote_state.ingest.outputs.input_bucket_cmk.arn,
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


    resources = [data.terraform_remote_state.security-tools.outputs.ebs_cmk.arn]
  }

  statement {
    sid     = "AllowAccessToArtefactBucket"
    effect  = "Allow"
    actions = ["s3:GetBucketLocation"]

    resources = [data.terraform_remote_state.management_artefact.outputs.artefact_bucket.arn]
  }

  statement {
    sid       = "AllowPullFromArtefactBucket"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${data.terraform_remote_state.management_artefact.outputs.artefact_bucket.arn}/*"]
  }

  statement {
    sid    = "AllowDecryptArtefactBucket"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [data.terraform_remote_state.management_artefact.outputs.artefact_bucket.cmk_arn]
  }

  statement {
    sid    = "AllowIngestHbaseToGetSecretManagerPassword"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      data.terraform_remote_state.ingest.outputs.metadata_store_secrets.hbasewriter.arn
    ]
  }


  statement {
    sid    = "WriteManifestsInManifestBucket"
    effect = "Allow"

    actions = [
      "s3:DeleteObject*",
      "s3:PutObject",
    ]

    resources = [
      "${data.terraform_remote_state.internal_compute.outputs.manifest_bucket["arn"]}/${local.s3_manifest_prefix[local.environment]}/*",
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

    resources = [aws_acm_certificate.emr_replica_hbase.arn]
  }

  statement {
    sid    = "GetPublicCerts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [data.terraform_remote_state.certificate_authority.outputs.public_cert_bucket.arn]
  }
}

resource "aws_iam_policy" "replica_hbase_main" {
  name        = "ReplicaHbaseS3Main"
  description = "Allow Ingestion EMR cluster to write HBase data to the input bucket"
  policy      = data.aws_iam_policy_document.hbase_replica_main.json
}

resource "aws_iam_role_policy_attachment" "emr_ingest_hbase_main" {
  role       = aws_iam_role.emr_hbase_replica.name
  policy_arn = aws_iam_policy.replica_hbase_main.arn
}

data "aws_iam_policy_document" "replica_hbase_ec2" {
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

resource "aws_iam_policy" "replica_hbase_ec2" {
  name        = "replica_hbase_ec2"
  description = "Policy to allow access to modify Ec2 tags"
  policy      = data.aws_iam_policy_document.replica_hbase_ec2.json
}

resource "aws_iam_role_policy_attachment" "ingest_hbase_ec2" {
  role       = aws_iam_role.emr_hbase_replica.name
  policy_arn = aws_iam_policy.replica_hbase_ec2.arn
}

#
########        IAM
########        EMR Service role

resource "aws_iam_role" "emr_service" {
  name               = "replica_emr_service_role"
  assume_role_policy = data.aws_iam_policy_document.emr_assume_role.json
  tags               = local.common_tags
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


    resources = [data.terraform_remote_state.security-tools.outputs.ebs_cmk.arn]
  }

  statement {
    effect = "Allow"

    actions = ["kms:CreateGrant"]


    resources = [data.terraform_remote_state.security-tools.outputs.ebs_cmk.arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "emr_ebs_cmk" {
  name        = "ReplicaEmrUseEbsCmk"
  description = "Allow Ingestion EMR cluster to use EB CMK for encryption"
  policy      = data.aws_iam_policy_document.emr_ebs_cmk.json
}

resource "aws_iam_role_policy_attachment" "emr_ebs_cmk" {
  role       = aws_iam_role.emr_service.id
  policy_arn = aws_iam_policy.emr_ebs_cmk.arn
}

#
########        Security groups

resource "aws_security_group" "replica_emr_hbase_common" {
  name                   = "replica_hbase_emr_common"
  description            = "Contains rules for both EMR cluster master nodes and EMR cluster slave nodes"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.id

  tags = merge(
    local.common_tags,
    {
      Name = "replica-hbase-emr-common"
    },
  )
}


resource "aws_security_group_rule" "vpce_ingress" {
  //todo: move to internal-compute vpc module
  security_group_id = data.terraform_remote_state.internal_compute.outputs.vpc.vpc.interface_vpce_sg_id

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  type                     = "ingress"
  source_security_group_id = aws_security_group.replica_emr_hbase_common.id
}
resource "aws_security_group_rule" "egress_to_vpce" {
  //todo: move to internal-compute vpc module
  security_group_id = aws_security_group.replica_emr_hbase_common.id

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  type                     = "egress"
  source_security_group_id = data.terraform_remote_state.internal_compute.outputs.vpc.vpc.interface_vpce_sg_id
}


resource "aws_security_group_rule" "replica_emr_hbase_egress_dks" {
  description = "Allow outbound requests to DKS from EMR HBase"
  type        = "egress"
  from_port   = 8443
  to_port     = 8443
  protocol    = "tcp"

  cidr_blocks       = data.terraform_remote_state.crypto.outputs.dks_subnet["cidr_blocks"]
  security_group_id = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "emr_hbase_egress_metadata_store" {
  description              = "Allow outbound requests to Metadata Store DB from EMR HBase"
  type                     = "egress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = data.terraform_remote_state.ingest.outputs.metadata_store.rds.sg_id
  security_group_id        = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "metadata_store_from_emr_hbase" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.replica_emr_hbase_common.id
  security_group_id        = data.terraform_remote_state.ingest.outputs.metadata_store.rds.sg_id
  description              = "Metadata store from EMR HBase"
}

resource "aws_security_group_rule" "emr_common_egress_s3_vpce_https" {
  description = "Allow outbound HTTPS traffic from EMR nodes to S3 VPC Endpoint"
  type        = "egress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"

  prefix_list_ids   = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.prefix_list_ids.s3]
  security_group_id = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "emr_common_egress_s3_vpce_http" {
  description = "Allow outbound HTTP (YUM) traffic from EMR nodes to S3 VPC Endpoint"
  type        = "egress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"

  prefix_list_ids   = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.prefix_list_ids.s3]
  security_group_id = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "emr_common_egress_dynamodb_vpce_https" {
  description = "Allow outbound HTTPS traffic from EMR nodes to DynamoDB VPC Endpoint"
  type        = "egress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"

  prefix_list_ids   = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.prefix_list_ids.dynamodb]
  security_group_id = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "emr_common_egress_between_nodes" {
  description              = "Allow outbound traffic between EMR nodes"
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.replica_emr_hbase_common.id
  security_group_id        = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "egress_emr_common_to_internet" {
  description              = "Allow EMR access to Internet Proxy (for ACM-PCA)"
  type                     = "egress"
  source_security_group_id = data.terraform_remote_state.internal_compute.outputs.internet_proxy.sg
  //  source_security_group_id = aws_security_group.internet_proxy_endpoint.id
  protocol          = "tcp"
  from_port         = 3128
  to_port           = 3128
  security_group_id = aws_security_group.replica_emr_hbase_common.id
}

resource "aws_security_group_rule" "ingress_emr_common_to_internet" {
  description              = "Allow EMR access to Internet Proxy (for ACM-PCA)"
  type                     = "ingress"
  source_security_group_id = aws_security_group.replica_emr_hbase_common.id
  protocol                 = "tcp"
  from_port                = 3128
  to_port                  = 3128
  security_group_id        = data.terraform_remote_state.internal_compute.outputs.internet_proxy.sg
  //  security_group_id        = aws_security_group.internet_proxy_endpoint.id
}

# EMR will add more rules to this SG during cluster provisioning;
# see https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-man-sec-groups.html#emr-sg-elasticmapreduce-master-private
resource "aws_security_group" "emr_hbase_master" {
  name                   = "replica_hbase_emr_master"
  description            = "Contains rules for EMR cluster master nodes"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.id

  tags = merge(
    local.common_tags,
    {
      Name = "hbase-emr-master"
    },
  )
}

# EMR will add more rules to this SG during cluster provisioning;
# see https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-man-sec-groups.html#emr-sg-elasticmapreduce-master-private
resource "aws_security_group" "replica_emr_hbase_slave" {
  name                   = "replica_hbase_emr_slave"
  description            = "Contains rules for EMR cluster slave nodes"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.id

  tags = merge(
    local.common_tags,
    {
      Name = "hbase-emr-slave"
    },
  )
}


# EMR 5.30.0+ requirement
resource "aws_security_group_rule" "emr_server_ingress_from_service" {
  description              = "Required by EMR"
  type                     = "ingress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.emr_hbase_master.id
  security_group_id        = aws_security_group.emr_hbase_service.id
}

resource "aws_security_group" "emr_hbase_service" {
  name                   = "replica_hbase_emr_service"
  description            = "Contains rules automatically added by the EMR service itself. See https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-man-sec-groups.html#emr-sg-elasticmapreduce-sa-private"
  revoke_rules_on_delete = true
  vpc_id                 = data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.id

  tags = merge(
    local.common_tags,
    {
      Name = "emr-hbase-service"
    },
  )
}

resource "aws_s3_bucket_object" "emr_logs_folder" {
  bucket = data.terraform_remote_state.security-tools.outputs.logstore_bucket.id
  acl    = "private"
  key    = "emr/aws-read-replica/"
  source = "/dev/null"

  tags = merge(
    local.common_tags,
    {
      Name = "emr-replica-logs-folder"
    },
  )
}

output "replica_emr_hbase_common" {
  value = aws_security_group.replica_emr_hbase_common
}
