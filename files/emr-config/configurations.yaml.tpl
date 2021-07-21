---
# todo: copy additional config from hbase-site terraform to here
Configurations:
- Classification: "hbase-site"
  Properties:
    "hbase.rootdir": "${hbase_rootdir}"
    "hbase.master.wait.on.regionservers.mintostart": "${core_instance_count}"
    "hbase.client.scanner.timeout.period": "${hbase_client_scanner_timeout_ms}"
    "hbase.assignment.usezk": "${hbase_assignment_usezk}"

- Classification: "hbase"
  Properties:
    "hbase.emr.storageMode": "${hbase_emr_storage_mode}"
    "hbase.emr.readreplica.enabled": "true"
- Classification: "hdfs-site"
  Properties:
    "dfs.replication": "1"

- Classification: "emrfs-site"
  Properties:
    "fs.s3.multipart.th.fraction.parts.completed": "${hbase_fs_multipart_th_fraction_parts_completed}"
    "fs.s3.maxConnections": "${hbase_s3_maxconnections}"
    "fs.s3.maxRetries": "${hbase_s3_max_retry_count}"

- Classification: "hive-site"
  Properties:
    "hive.metastore.warehouse.dir": "s3://${s3_published_bucket}/analytical-dataset/hive/DW-Enhancement"
    "hive.txn.manager": "org.apache.hadoop.hive.ql.lockmgr.DbTxnManager"
    "hive.enforce.bucketing": "true"
    "hive.exec.dynamic.partition.mode": "nostrict"
    "hive.compactor.initiator.on": "true"
    "hive.compactor.worker.threads": "1"
    "hive.support.concurrency": "true"
    "javax.jdo.option.ConnectionURL": "jdbc:mysql://${hive_metastore_endpoint}:3306/${hive_metastore_database_name}?createDatabaseIfNotExist=true"
    "javax.jdo.option.ConnectionDriverName": "org.mariadb.jdbc.Driver"
    "javax.jdo.option.ConnectionUserName": "${hive_metastore_username}"
    "javax.jdo.option.ConnectionPassword": "${hive_metastore_pwd}"
    "hive.metastore.client.socket.timeout": "7200"

- Classification: "spark-hive-site"
  Properties:
    "hive.txn.manager": "org.apache.hadoop.hive.ql.lockmgr.DbTxnManager"
    "hive.enforce.bucketing": "true"
    "hive.exec.dynamic.partition.mode": "nostrict"
    "hive.compactor.initiator.on": "true"
    "hive.compactor.worker.threads": "1"
    "hive.support.concurrency": "true"
    "javax.jdo.option.ConnectionURL": "jdbc:mysql://${hive_metastore_endpoint}:3306/${hive_metastore_database_name}"
    "javax.jdo.option.ConnectionDriverName": "org.mariadb.jdbc.Driver"
    "javax.jdo.option.ConnectionUserName": "${hive_metastore_username}"
    "javax.jdo.option.ConnectionPassword": "${hive_metastore_pwd}"
    "hive.metastore.client.socket.timeout": "7200"

