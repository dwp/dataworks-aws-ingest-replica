resource "aws_security_group_rule" "ingress_ingest_hbase_read_replica" {
  description              = "Allow mysql traffic to Aurora RDS from dataworks hbase read replica"
  from_port                = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.hive_metastore_v2.id
  to_port                  = 3306
  type                     = "ingress"
  source_security_group_id = data.terraform_remote_state.internal_compute.outputs.hive_metastore_v2.security_group.id
}

resource "aws_security_group_rule" "egress_ingest_hbase_read_replica" {
  description              = "Allow mysql traffic to Aurora RDS from dataworks hbase read replica"
  from_port                = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.replica_emr_hbase_commonreplica_emr_hbase_common.id
  to_port                  = 3306
  type                     = "egress"
  source_security_group_id = data.terraform_remote_state.internal_compute.outputs.hive_metastore_v2.security_group.id
}
