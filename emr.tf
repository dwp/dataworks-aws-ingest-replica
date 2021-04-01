//data "local_file" "amazon_root_ca1_pem" {
//  filename = ""
//}

//todo:fix aws_key_pair

//resource "aws_key_pair" "emr-key" {
//  key_name   = "emr-key"
//  public_key = local.emr_key[local.environment]
//
//
//  tags = merge(
//    local.common_tags,
//    {
//      Name = "emr-key"
//    },
//  )
//}

resource "aws_emr_cluster" "hbase_read_replica" {
  name                              = "hbase-read-replica"
  release_label                     = "emr-5.30.1"
  applications                      = local.emr_applications[local.environment]
  termination_protection            = false
  keep_job_flow_alive_when_no_steps = true
  service_role                      = aws_iam_role.emr_service.arn
  log_uri                           = "s3n://${data.terraform_remote_state.security-tools.outputs.logstore_bucket["id"]}/${aws_s3_bucket_object.emr_logs_folder.id}"
  security_configuration            = aws_emr_security_configuration.replica_hbase_ebs_encryption.name
  custom_ami_id                     = var.emr_al2_ami_id
  ebs_root_volume_size              = 40

  master_instance_group {
    instance_type  = var.hbase_master_instance_type[local.environment]
    instance_count = var.hbase_master_instance_count[local.environment]
    name           = "hbase-replica-master"

    ebs_config {
      size = var.hbase_master_ebs_size[local.environment]
      type = var.hbase_master_ebs_type[local.environment]
    }
  }

  core_instance_group {
    instance_type  = var.hbase_core_instance_type_one[local.environment]
    instance_count = var.hbase_core_instance_count[local.environment]
    name           = "hbase-replica-core"

    ebs_config {
      size = var.hbase_core_ebs_size[local.environment]
      type = var.hbase_core_ebs_type[local.environment]
    }
  }

  ec2_attributes {
    // todo: create new subnets for hosting replica
    subnet_id                         = data.terraform_remote_state.internal_compute.outputs.hbase_emr_subnet["id"][0]
    instance_profile                  = aws_iam_instance_profile.emr_hbase_replica.id
    emr_managed_master_security_group = aws_security_group.emr_hbase_master.id
    additional_master_security_groups = aws_security_group.replica_emr_hbase_common.id
    emr_managed_slave_security_group  = aws_security_group.replica_emr_hbase_slave.id
    additional_slave_security_groups  = aws_security_group.replica_emr_hbase_common.id
    service_access_security_group     = aws_security_group.emr_hbase_service.id
    //    key_name                          = aws_key_pair.emr-key.key_name
  }

  # Optional: ignore outside changes to running cluster steps
  lifecycle {
    ignore_changes = [step]
  }

  bootstrap_action {
    name = "Certificate Setup"
    path = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket.id, aws_s3_bucket_object.certificate_setup.key)
  }

  bootstrap_action {
    name = "Unique Hostname"
    path = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket.id, aws_s3_bucket_object.unique_hostname.key)
  }

  bootstrap_action {
    name = "Start SSM Agent"
    path = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket.id, aws_s3_bucket_object.start_ssm_script.key)
  }
//
//  bootstrap_action {
//    name = "Generate Download Scripts Script"
//    path = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket.id, aws_s3_bucket_object.generate_download_scripts_script.key)
//  }

  bootstrap_action {
    name = "Installer"
    path = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket.id, aws_s3_bucket_object.installer.key)
  }
  //
  //  bootstrap_action {
  //    name = "CloudWatch Setup"
  //    path = format("s3://%s/%s", data.terraform_remote_state.common.outputs.config_bucket.id, aws_s3_bucket_object.cloudwatch_sh.key)
  //  }

  # For HBase tunables see https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hbase-configure.html
  //todo: rationalise and add replica config
  configurations_json = <<EOF
  [
    {
      "Classification": "hbase-site",
      "Properties": {
        "hbase.rootdir": "s3://${local.hbase_rootdir}",
        "hbase.procedure.store.wal.use.hsync": "${var.hbase_procedure_store_wal_use_hsync[local.environment]}",
        "hbase.master.balancer.stochastic.runMaxSteps": "${var.hbase_master_balancer_stochastic_run_max_steps[local.environment]}",

        "hbase.hregion.max.filesize": "${var.hbase_hregion_max_filesize[local.environment]}",
        "hbase.hregion.memstore.flush.size": "${var.hbase_hregion_memstore_flush_size[local.environment]}",
        "hbase.hregion.memstore.block.multiplier": "${var.hbase_hregion_memstore_block_multiplier[local.environment]}",
        "hbase.hstore.compaction.max": "${var.hbase_hstore_compaction_max[local.environment]}",
        "hbase.hstore.blockingStoreFiles": "${var.hbase_hstore_blocking_store_files[local.environment]}",

        "hbase.regionserver.global.memstore.size": "${var.hbase_regionserver_global_memstore_size[local.environment]}",
        "hbase.regionserver.global.memstore.size.lower.limit": "${var.hbase_regionserver_global_memstore_size_lower_limit[local.environment]}",
        "hbase.regionserver.global.memstore.size.lowerLimit": "${var.hbase_regionserver_global_memstore_size_lower_limit[local.environment]}",
        "hbase.regionserver.global.memstore.size.upper.limit": "${var.hbase_regionserver_global_memstore_size_upper_limit[local.environment]}",
        "hbase.regionserver.global.memstore.size.upperLimit": "${var.hbase_regionserver_global_memstore_size_upper_limit[local.environment]}",
        "hbase.regionserver.region.split.policy": "${var.hbase_regionserver_region_split_policy[local.environment]}",


        "hbase.server.keyvalue.maxsize": "${var.hbase_server_keyvalue_max_size_bytes[local.environment]}",
        "hbase.bucketcache.bucket.sizes": "${var.hbase_bucketcache_bucket_sizes[local.environment]}",
        "hbase.client.write.buffer": "${var.hbase_client_write_buffer[local.environment]}",
        "hbase.regionserver.handler.count": "${var.hbase_regionserver_handler_count[local.environment]}",
        "hbase.hregion.majorcompaction": "${var.hbase_regionserver_majorcompaction[local.environment]}",
        "hbase.hstore.compactionThreshold": "${var.hbase_hstore_compaction_threshold[local.environment]}",
        "hbase.hstore.flusher.count": "${var.hbase_hstore_flusher_count[local.environment]}",
        "hfile.block.cache.size": "${var.hbase_hfile_block_cache_size[local.environment]}",
        "hbase.regionserver.meta.storefile.refresh.period": "${var.hbase_regionserver_meta_storefile_refresh_period_milliseconds[local.environment]}",
        "hbase.regionserver.storefile.refresh.period": "${var.hbase_regionserver_storefile_refresh_period_milliseconds[local.environment]}",
        "hbase.regionserver.storefile.refresh.all": "${var.hbase_regionserver_storefile_refresh_all[local.environment]}",
        "hbase.master.hfilecleaner.ttl": "${var.hbase_master_hfilecleaner_ttl[local.environment]}",
        "hbase.region.replica.wait.for.primary.flush": "${var.hbase_region_replica_wait_for_primary_flush[local.environment]}",
        "hbase.meta.replica.count": "${var.hbase_meta_replica_count[local.environment]}",
        "hbase.rpc.timeout": "${var.hbase_rpc_timeout_ms[local.environment]}",
        "hbase.regionserver.thread.compaction.small": "${var.hbase_regionserver_thread_compaction_small[local.environment]}",
        "hbase.regionserver.codecs": "${var.hbase_regionserver_codecs[local.environment]}",
        "hbase.ipc.server.callqueue.handler.factor": "${var.hbase_ipc_server_callqueue_handler_factor[local.environment]}",
        "hbase.ipc.server.callqueue.read.ratio": "${var.hbase_ipc_server_callqueue_read_ratio[local.environment]}",
        "hbase.ipc.server.callqueue.scan.ratio": "${var.hbase_ipc_server_callqueue_scan_ratio[local.environment]}",
        "hbase.bulkload.retries.retryOnIOException": "${var.hbase_bulkload_retries_retryOnIOException[local.environment]}",
        "hbase.bulkload.retries.number": "${var.hbase_bulkload_retries_number[local.environment]}",
        "hbase.client.pause": "${var.hbase_client_pause_milliseconds[local.environment]}",
        "hbase.client.retries.number": "${var.hbase_client_retries_number[local.environment]}",
        "hbase.balancer.period": "${var.hbase_balancer_period_milliseconds[local.environment]}",
        "hbase.balancer.max.balancing": "${var.hbase_balancer_max_balancing_milliseconds[local.environment]}",
        "hbase.master.balancer.maxRitPercent": "${var.hbase_balancer_max_rit_percent[local.environment]}",
        "hbase.master.wait.on.regionservers.mintostart": "${var.hbase_core_instance_count[local.environment]}",
        "hbase.client.scanner.timeout.period": "${var.hbase_client_scanner_timeout_ms[local.environment]}",
        "hbase.assignment.usezk": "${var.hbase_assignment_usezk[local.environment]}"
      }
    },
    {
      "Classification": "hbase",
      "Properties": {
        "hbase.emr.storageMode": "${var.hbase_emr_storage_mode[local.environment]}",
        "hbase.emr.readreplica.enabled": "true"
      }
    },
{
    "classification": "hdfs-site",
    "properties": {
      "dfs.replication": "1"
    }
  },
    {
      "Classification": "emrfs-site",
      "Properties": {
        "fs.s3.multipart.th.fraction.parts.completed": "${var.hbase_fs_multipart_th_fraction_parts_completed[local.environment]}",
        "fs.s3.maxConnections": "${var.hbase_s3_maxconnections[local.environment]}",
        "fs.s3.maxRetries": "${var.hbase_s3_max_retry_count[local.environment]}"
      }
    }
  ]
EOF


  tags = merge(
    local.common_tags,
    {
      Name      = "ingest-hbase-replica"
      ShortName = "ingest-hbase-replica"
    },
    {
      "Persistence" = "Ignore"
    },
    {
      "SSMEnabled" = var.hbase_ssmenabled[local.environment]
    },
  )
}

#
########        Additional EMR cluster config
resource "aws_emr_security_configuration" "replica_hbase_ebs_encryption" {
  name = "replica_hbase_ebs_encryption"

  configuration = <<EOF
{
    "EncryptionConfiguration": {
        "EnableInTransitEncryption" : false,
        "EnableAtRestEncryption" : true,
        "AtRestEncryptionConfiguration" : {
            "LocalDiskEncryptionConfiguration" : {
                "EnableEbsEncryption" : true,
                "EncryptionKeyProviderType" : "AwsKms",
                "AwsKmsKey" : "${data.terraform_remote_state.security-tools.outputs.ebs_cmk["arn"]}"
            }
        }
     }
}
EOF

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

/*
master:2181    TCP (zookeeper)
master:16000   TCP    (hbase master)
master:16020   TCP    (region server)
master:16030   HTTP    (region server)
slave:16020    TCP    (region server)
slave:16030    HTTP    (region server)
*/

# DW-4134 - Rule for the dev Workspaces, gated to dev - "Ganglia"
resource "aws_security_group_rule" "emr_server_ingress_workspaces_master_80" {
  count             = local.environment == "development" ? 1 : 0
  description       = "Allow WorkSpaces (internal-compute VPC) access to Hbase"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.cidr_block]
  security_group_id = aws_security_group.emr_hbase_master.id
}

# DW-4134 - Rule for the dev Workspaces, gated to dev - "Yarn NodeManager"
resource "aws_security_group_rule" "emr_server_ingress_workspaces_master_8042" {
  count             = local.environment == "development" ? 1 : 0
  description       = "Allow WorkSpaces (internal-compute VPC) access to Yarn NodeManager"
  type              = "ingress"
  from_port         = 8042
  to_port           = 8042
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.cidr_block]
  security_group_id = aws_security_group.emr_hbase_master.id
}

# DW-4134 - Rule for the dev Workspaces, gated to dev - "Yarn ResourceManager"
resource "aws_security_group_rule" "emr_server_ingress_workspaces_master_8088" {
  count             = local.environment == "development" ? 1 : 0
  description       = "Allow WorkSpaces (internal-compute VPC) access to Yarn ResourceManager"
  type              = "ingress"
  from_port         = 8088
  to_port           = 8088
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.cidr_block]
  security_group_id = aws_security_group.emr_hbase_master.id
}

# DW-4134 - Rule for the dev Workspaces, gated to dev - "Hbase"
resource "aws_security_group_rule" "emr_server_ingress_workspaces_master_16010" {
  count             = local.environment == "development" ? 1 : 0
  description       = "Allow WorkSpaces (internal-compute VPC) access to Hbase"
  type              = "ingress"
  from_port         = 16010
  to_port           = 16010
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.cidr_block]
  security_group_id = aws_security_group.emr_hbase_master.id
}

# DW-4134 - Rule for the dev Workspaces, gated to dev - "Region Server"
resource "aws_security_group_rule" "emr_server_ingress_workspaces_slave_16030" {
  count             = local.environment == "development" ? 1 : 0
  description       = "Allow WorkSpaces (internal-compute VPC) access to Region Server"
  type              = "ingress"
  from_port         = 16030
  to_port           = 16030
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.cidr_block]
  security_group_id = aws_security_group.replica_emr_hbase_slave.id
}


# DW-4134 - Rule for the dev Workspaces, gated to dev - "Spark"
resource "aws_security_group_rule" "emr_server_ingress_workspaces_master_18080" {
  count             = local.environment == "development" ? 1 : 0
  description       = "Allow WorkSpaces (internal-compute VPC) access to Spark"
  type              = "ingress"
  from_port         = 18080
  to_port           = 18080
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.internal_compute.outputs.vpc.vpc.vpc.cidr_block]
  security_group_id = aws_security_group.emr_hbase_master.id
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


resource "aws_route53_record" "hbase_replica" {
  provider = aws.management_dns
  zone_id  = data.terraform_remote_state.management_dns.outputs.dataworks_zone.id
  name     = "replica-hbase${local.dns_subdomain[local.environment]}"
  type     = "CNAME"
  ttl      = "60"
  records  = [aws_emr_cluster.hbase_read_replica.master_public_dns]
}

