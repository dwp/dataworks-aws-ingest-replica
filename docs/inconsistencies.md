# Inconsistencies and Testing in Pre-production

### Inconsistencies caused by read-replica cluster
Each HBase Read-Replica cluster will create a directory following this pattern in the HBase root dir: 
`data/hbase/meta_j-<cluster_id>/`

The primary HBase scans this folder and considers it to be data.  Since it doesn't have metadata for this data, 
'inconsistencies' are detected when running the `hbase hbck` command.

There are instances where the replica cluster leaves behind corrupted metadata in the `meta_j-<cluster_id>` folder.
This results in the `hbck` tool raising an Exception.  It also prevents a master from becoming active over the root
directory in the following scenarios:
- hbase master failover
- `ingest-hbase` redeployment

Deleting the data under the prefix is enough to allow the hbase master to become active, and prevent detection
of the inconsistencies.  The metadata-removal-lambda is triggered on termination of an intraday cluster, removing the
`meta_j-<cluster_id>` prefix.

### Testing in Pre-production
#### Preparation
ingest-hbase in the Preproduction environment had significant inconsistencies.  These were cleared before testing
commenced.

The following steps were taken to prepare the preprod environment for intraday testing:
- Inconsistencies reduced from ~500 to 0 by running the `sudo -u hbase hbase hbck -repair`
  and `sudo -u hbase hbase hbck -fixEmptyMetaCells` commands alternately
- Ingest-hbase maintenance start/end jobs corrected to match other environments
- Intraday infrastructure deployed to preproduction with the schedule disabled
- Initial dynamodb items added for each collection to be processed, preventing excessive historical data processing
- First cluster triggered manually and monitored
- Intraday schedule enabled

The following issues occurred during/after intraday deployment.  Causality is not yet established, but the environment
had been stable for a long period before the inconsistency repairs and intraday deployment.  

Clearing inconsistencies is complicated - it's possible that the issues were not fulling resolved before
testing started.

#### Failure to archive/delete files
The HBase logs are flooded with Errors relating to ~6 collections where it is unable to archive/delete files.  These
seemed to be the same collections that were previously affected by the inconsistencies.

Insights on the `hbase_logs` logstream:

```filter @message like /org.apache.hadoop.hbase.backup.FailedArchiveException/```

#### Region Server Deaths and Inconsistencies
On 2 occasions over approx. 3 weeks of testing, region server deaths occurred followed by the detection of 
inconsistencies.  The inconsistencies appear to affect a limited number of collections/hbase tables.

#### Failure of primary HBase
Some time after the intraday schedule was disabled, ingest-hbase was redeployed. The cluster failed to start,
due to errors reading the data in `data/hbase/namespace/.tabledesc/`.  The error is similar to that seen when 
corrupted replica metadata is present, but the corrupted data in this instance belongs to the primary cluster.
