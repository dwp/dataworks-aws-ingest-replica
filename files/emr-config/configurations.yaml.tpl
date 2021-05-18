---
# todo: copy additional config from hbase-site terraform to here
Configurations:
- Classification: "hbase-site"
  Properties:
    "hbase.rootdir": "s3://${hbase_rootdir}"
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

