
variable "emr_mapreduce_task_timeout_seconds" {
  type        = map(number)
  description = "Task timeout in seconds for mapreduce tasks, zero is off - size of files varies massively so off used generally"
  default = {
    development = 0
    qa          = 0
    integration = 0
    preprod     = 0
    production  = 0
  }
}

variable "emr_mapreduce_map_java_opts" {
  type        = map(string)
  description = "The java options to pass to the map tasks, usually used to set JVM memory limits"
  default = {
    development = "-Xmx1229m"
    qa          = "-Xmx1229m"
    integration = "-Xmx1229m"
    preprod     = "-Xmx1229m"
    production  = "-Xmx2458m"
  }
}

variable "emr_mapreduce_reduce_java_opts" {
  type        = map(string)
  description = "The java options to pass to the reduce tasks, usually used to set JVM memory limits"
  default = {
    development = "-Xmx2458m"
    qa          = "-Xmx2458m"
    integration = "-Xmx2458m"
    preprod     = "-Xmx2458m"
    production  = "-Xmx4916m"
  }
}

variable "emr_mapreduce_map_memory_mb" {
  type        = map(number)
  description = "The total memory possibly available for map tasks"
  default = {
    development = 1536
    qa          = 1536
    integration = 1536
    preprod     = 1536
    production  = 3072
  }
}

variable "emr_mapreduce_reduce_memory_mb" {
  type        = map(number)
  description = "The total memory possibly available for reduce tasks"
  default = {
    development = 3072
    qa          = 3072
    integration = 3072
    preprod     = 3072
    production  = 6144
  }
}

variable "emr_mapreduce_shuffle_memory_limit_percent" {
  type        = map(string)
  description = "Amount of reduce memory that can be assigned to a single shuffle, given HBase is mainly a shuffle, set it high"
  default = {
    development = "0.50"
    qa          = "0.50"
    integration = "0.50"
    preprod     = "0.50"
    production  = "0.50"
  }
}

variable "emr_yarn_app_mapreduce_am_resource_mb" {
  type        = map(number)
  description = "Amount of memory available to the application master to manage all the yarn tasks"
  default = {
    development = 3072
    qa          = 3072
    integration = 3072
    preprod     = 3072
    production  = 6144
  }
}

variable "emr_yarn_scheduler_minimum_allocation_mb" {
  type        = map(number)
  description = "Min amount of memory available to the application master to manage all the yarn tasks - must be bigger than emr_yarn_app_mapreduce_am_resource_mb"
  default = {
    development = 32
    qa          = 32
    integration = 32
    preprod     = 32
    production  = 32
  }
}

variable "emr_yarn_scheduler_maximum_allocation_mb" {
  type        = map(number)
  description = "Max amount of memory available to the application master to manage all the yarn tasks - must be bigger than emr_yarn_app_mapreduce_am_resource_mb"
  default = {
    development = 6144
    qa          = 6144
    integration = 6144
    preprod     = 6144
    production  = 10240
  }
}

variable "emr_yarn_nodemanager_resource_memory_mb" {
  type        = map(number)
  description = "Amount of memory available to the application master to manage all the yarn tasks"
  default = {
    development = 6144
    qa          = 6144
    integration = 6144
    preprod     = 6144
    production  = 10240
  }
}

# Source - https://aws.amazon.com/blogs/big-data/best-practices-for-successfully-managing-memory-for-apache-spark-applications-on-amazon-emr/
variable "emr_yarn_nodemanager_vmem_check_enabled" {
  type        = map(bool)
  description = "A boolean indicating where to perform virtual memory checks, recommended by AWS docs to be off"
  default = {
    development = false
    qa          = false
    integration = false
    preprod     = false
    production  = false
  }
}

# Source - https://aws.amazon.com/blogs/big-data/best-practices-for-successfully-managing-memory-for-apache-spark-applications-on-amazon-emr/
variable "emr_yarn_nodemanager_pmem_check_enabled" {
  type        = map(bool)
  description = "A boolean indicating where to perform permanent memory checks, recommended by AWS docs to be off"
  default = {
    development = false
    qa          = false
    integration = false
    preprod     = false
    production  = false
  }
}

# Must start with "hbase-" to honour the input bucket lifecycle_rule 'hbase-root-dir in business-data'"
variable "hbase_rootdir" {
  type        = map(string)
  description = "The root directory in s3 used for the files HBase stores. Must start with `hbase-` see lifecycle_rules"
  default = {
    development = "hbase-storage-dev"
    qa          = "hbase-storage-qa"
    integration = "hbase-storage"
    preprod     = "hbase-storage"
    production  = "hbase-corporate-storage-25-october-2020"
  }
}


variable "hbase_ssmenabled" {
  type        = map(string)
  description = "Determines whether SSM is enabedl"
  default = {
    development = "True"
    qa          = "True"
    integration = "True"
    preprod     = "False"
    // OFF by IAM Policy
    production = "False"
    // OFF by IAM Policy
  }
}

variable "hbase_ipc_server_callqueue_read_ratio" {
  type        = map(string)
  description = "The percentage (as a factor between 1 and 0) of queues dedicated to reads (as opposed to writes) where 1 is all the queues, except 1 which always is left for writes. The % as a ratio of queues (and therefore handlers) available to reads, can be lowered to 0.1 for write heavy"
  default = {
    development = ".5"
    qa          = ".5"
    integration = ".5"
    preprod     = ".5"
    production  = ".5" // 0.1 = write heavy. 0.5 = balanced due to writes from k2hb but reads from htme and reconciler
  }
}

###--- End stuff changed during bulk loads ---###

variable "hbase_master_balancer_stochastic_run_max_steps" {
  type        = map(string)
  description = "Whether or not the region balancer limits its calulation steps - confines the region splitting behaviour. Defaults to false. Can set to true to alter the behaviour. Not well understood."
  // ### Info from AWS support case 7203499161, 28th Aug 20200 from Leon ###
  // For loadbalancers stochastic walk is larger than maxSteps:30000.
  // Hence load balancing may not work well. Setting parameter "hbase.master.balancer.stochastic.runMaxSteps" to true
  // can overcome this issue. (This config change does not require service restart)

  default = {
    development = "true"
    qa          = "true"
    integration = "true"
    preprod     = "true"
    production  = "true" // MM 28-Aug-2020: see above.
  }
}

variable "hbase_regionserver_region_split_policy" {
  type        = map(string)
  description = "The policy used to decide when regions are split. Reference Guide https://hbase.apache.org/book.html#table_schema_rules_of_thumb"
  // ### Info from AWS support case 7203499161, 28th Aug 20200 from Leon ###
  // Default is ConstantSizeRegionSplitPolicy.
  //
  // SteppingSplitPolicy :
  //   flushSize * 2 if there is exactly one region of the table in question found on this regionserver.
  // Otherwise max file size.
  // This allows a table to spread quickly across servers, while avoiding creating too many regions.
  // This https://hbase.apache.org/devapidocs/org/apache/hadoop/hbase/regionserver/SteppingSplitPolicy.html
  // was only introduced in HBase 2.0 so is not available and it is failing back to default which is actually
  // IncreasingToUpperBoundRegionSplitPolicy, which splits increasingly quite frequently
  // We want ConstantSizeRegionSplitPolicy because we generate regions up front now


  default = {
    development = "org.apache.hadoop.hbase.regionserver.ConstantSizeRegionSplitPolicy"
    qa          = "org.apache.hadoop.hbase.regionserver.ConstantSizeRegionSplitPolicy"
    integration = "org.apache.hadoop.hbase.regionserver.ConstantSizeRegionSplitPolicy"
    preprod     = "org.apache.hadoop.hbase.regionserver.ConstantSizeRegionSplitPolicy"
    production  = "org.apache.hadoop.hbase.regionserver.ConstantSizeRegionSplitPolicy"
  }
}

variable "hbase_hstore_blocking_store_files" {
  type        = map(number)
  description = "Enables writes to continue even though the write cache is full without waiting for the cache to flush, to enable writes to keep processing when memstore full"
  default = {
    development = 10
    qa          = 10
    integration = 10
    preprod     = 10
    production  = 20
  }
}

variable "hbase_regionserver_global_memstore_size_upper_limit" {
  type        = map(string)
  description = "This is the heap % as a ratio available to the write cache, can be as high as 0.7 for write heavy. Total size of all write caches before they are all flushed as a factor between 0 and 1, they can't go above this limit."
  default = {
    development = "0.95"
    qa          = "0.95"
    integration = "0.95"
    preprod     = "0.95"
    production  = "0.95" //0.95 = write heavy, but this is ok for HTME to function so we leave it favouring K2HB
  }
}

variable "hbase_hregion_memstore_flush_size" {
  type        = map(number)
  description = "Size in bytes the memstore can set to before being flushed. Increase during bulk data load to make less files which bigger. Defaults to 128mb in higher envs, 10mb in lower envs."
  default = {
    development = "10485760"
    qa          = "10485760"
    integration = "134217728"
    preprod     = "134217728"
    production  = "134217728"
  }
}

variable "hbase_hstore_compaction_max" {
  type        = map(number)
  description = "Increase this to a higher value so that more Hfiles are covered in compaction process. Defaults to 10."
  default = {
    development = "10"
    qa          = "10"
    integration = "10"
    preprod     = "10"
    production  = "10"
  }
}

variable "hbase_hfile_block_cache_size" {
  type        = map(string)
  description = "This is the heap % as a ratio available to the read cache, can be as low as 0.1 for write heavy. Percentage of the heap assigned to the read cache (note the heap on EMR HBase is 50% of instance RAM or 32GB max) - this and hbase_regionserver_global_memstore_size together must not be above 0.8 or region servers won't start"
  default = {
    development = "0.35"
    qa          = "0.35"
    integration = "0.35"
    preprod     = "0.35"
    production  = "0.35" // 35 = write heavy, but this is enough for HTME to function so we leave it favouring K2HB
  }
}

variable "hbase_regionserver_global_memstore_size_lower_limit" {
  type        = map(string)
  description = "This is the heap % as a ratio available to the write cache, can be as high as 0.7 for write heavy. Total size of all write caches before they are all flushed as a factor between 0 and 1, they can't go above this limit."
  default = {
    development = "0.8"
    qa          = "0.8"
    integration = "0.8"
    preprod     = "0.8"
    production  = "0.8" //0.80 = write heavy, but this is ok for HTME to function so we leave it favouring K2HB
  }
}

variable "hbase_procedure_store_wal_use_hsync" {
  type        = map(string)
  description = "Whether or not to use hsync (Syncl WAL to HDFS, I think). Defaults to true for resillience."
  // ### Info from AWS support case 7203499161, 28th Aug 20200 from Leon ###
  // The procedure WAL relies on the ability to hsync for proper operation during component failures,
  // but the underlying filesystem does not [may not] support doing so.
  // Please check the config value of 'hbase.procedure.store.wal.use.hsync' to set the desired level of robustness
  // and [if true] ensure the config value of 'hbase.wal.dir' points to a FileSystem mount that can provide it.
  // MM 28-Aug-2020: My additions above [thus]
  default = {
    development = "true"
    qa          = "true"
    integration = "true"
    preprod     = "true"
    production  = "true"
  }
}

# Because we pre-provision tables, the average size of regions will be 1GB, so 5 GB seems a reasonable split point
variable "hbase_hregion_max_filesize" {
  type        = map(number)
  description = "Larger means less region changes. The maximum size, in bytes, of each region file."
  default = {
    development = 5368706371
    qa          = 5368706371
    integration = 5368706371
    preprod     = 5368706371
    production  = 21474825484 # 20GB in production due to size of load in each region
  }
}

# The running of these is every fortnight and controlled by CI
variable "hbase_regionserver_majorcompaction" {
  type        = map(number)
  description = "The time between automatic major compactions, 0 means they are off"
  default = {
    development = 0
    qa          = 0
    integration = 0
    preprod     = 0
    production  = 0
  }
}

variable "hbase_hstore_compaction_threshold" {
  type        = map(number)
  description = "The number of HStore files that will be included in a minor compaction - default is 3, higher numbers delay minor compactions but mean they take longer to complete"
  default = {
    development = 3
    qa          = 3
    integration = 3
    preprod     = 3
    production  = 5
  }
}

variable "hbase_hstore_flusher_count" {
  type        = map(number)
  description = "Number of threads available to perform flushing of the memstore write cache (default 2)"
  default = {
    development = 2
    qa          = 2
    integration = 2
    preprod     = 2
    production  = 4
  }
}

variable "hbase_regionserver_codecs" {
  type        = map(string)
  description = "Ensures these codecs are loaded for each new region server - we use gz for compression"
  default = {
    development = "snappy,gz"
    qa          = "snappy,gz"
    integration = "snappy,gz"
    preprod     = "snappy,gz"
    production  = "snappy,gz"
  }
}

variable "hbase_regionserver_global_memstore_size" {
  type        = map(string)
  description = "Percentage of the heap assigned to the write cache (note the heap on EMR HBase is 50% of instance RAM or 32GB max) - this and hbase_hfile_block_cache_size together must not be above 0.8"
  default = {
    development = "0.45"
    qa          = "0.45"
    integration = "0.45"
    preprod     = "0.45"
    production  = "0.45"
  }
}

variable "hbase_hregion_memstore_block_multiplier" {
  type        = map(number)
  description = "Number of times a region can grow it's memstore, must not be too high so out of memory exceptions don't occur"
  default = {
    development = 1
    qa          = 1
    integration = 1
    preprod     = 1
    production  = 10
  }
}

variable "hbase_rpc_timeout_ms" {
  type        = map(number)
  description = "The timeout of the server side (per client can overwrite) for a single RPC call"
  default = {
    development = 600000
    qa          = 600000
    integration = 600000
    preprod     = 600000
    production  = 900000
  }
}

variable "hbase_client_scanner_timeout_ms" {
  type        = map(number)
  description = "The timeout of the server side (per client can overwrite) for a scanner to complete its work"
  default = {
    development = 600000
    qa          = 600000
    integration = 600000
    preprod     = 600000
    production  = 900000
  }
}

variable "hbase_client_pause_milliseconds" {
  type        = map(number)
  description = "The time between retries for client retries (per client can overwrite) - default 100"
  default = {
    development = 100
    qa          = 101
    integration = 100
    preprod     = 100
    production  = 100
  }
}

variable "hbase_client_retries_number" {
  type        = map(number)
  description = "The number of retries for client calls (per client can overwrite) - default 35"
  default = {
    development = 50
    qa          = 50
    integration = 50
    preprod     = 50
    production  = 50
  }
}

variable "hbase_balancer_period_milliseconds" {
  type        = map(number)
  description = "The time between balancer checks - higher for stability (default is 300000)"
  default = {
    development = 300000
    qa          = 300000
    integration = 300000
    preprod     = 300000
    production  = 300000
  }
}

variable "hbase_balancer_max_balancing_milliseconds" {
  type        = map(number)
  description = "The time the balancer is allowed to run for each time it runs as a max (default is half balancer period)"
  default = {
    development = 150000
    qa          = 150000
    integration = 150000
    preprod     = 150000
    production  = 150000
  }
}

variable "hbase_balancer_max_rit_percent" {
  type        = map(string)
  description = "The max percent of regions in transition when balancing as a ratio (default is 1.0)"
  default = {
    development = "0.5"
    qa          = "0.5"
    integration = "0.5"
    preprod     = "0.5"
    production  = "0.5"
  }
}


variable "hbase_regionserver_thread_compaction_small" {
  type        = map(number)
  description = "The number of available threads (default is 1) used for minor compactions per region server"
  default = {
    development = 2
    qa          = 2
    integration = 2
    preprod     = 2
    production  = 4
  }
}

variable "hbase_s3_maxconnections" {
  type        = map(number)
  description = "Allowed connections HBase can make to S3 - should be high due to lots of file movements in HBase"
  default = {
    development = 1000
    qa          = 1000
    integration = 1000
    preprod     = 1000
    production  = 50000
  }
}

variable "hbase_s3_max_retry_count" {
  type        = map(number)
  description = "Times that EMRFS retries s3 requests before giving up"
  default = {
    development = 20
    qa          = 20
    integration = 20
    preprod     = 20
    production  = 20
  }
}

variable "hbase_fs_multipart_th_fraction_parts_completed" {
  type        = map(number)
  description = "Reduces the chance of partial fs data uploads, reducing inconsistency errors. The altering of the setting to a high valid value (less than 1.0) such as 0.99, will essentially disable speculative UploadParts in MultipartUpload requests initiated by fs"
  default = {
    development = 0.99
    qa          = 0.99
    integration = 0.99
    preprod     = 0.99
    production  = 0.99
  }
}

# As we control all the clients so don't need this protection
variable "hbase_server_keyvalue_max_size_bytes" {
  type        = map(number)
  description = "The max value to put in a cell, set to 0 for unlimited"
  default = {
    development = 0
    qa          = 0
    integration = 0
    preprod     = 0
    production  = 0
  }
}

variable "hbase_ipc_server_callqueue_handler_factor" {
  type        = map(string)
  description = "Number of handlers per thread (1 is handler for incoming tasks per thread, 0 is one for all threads and so on as a factor in between 0 and 1)"
  default = {
    development = "1"
    qa          = "1"
    integration = "1"
    preprod     = "1"
    production  = "1"
  }
}

variable "hbase_ipc_server_callqueue_scan_ratio" {
  type        = map(string)
  description = "The percentage (as a factor between 1.0 and 0) of read queues dedicated to scans (as opposed to gets) where 1 is all the queues, except 1 which always is left for gets"
  default = {
    development = "0.9"
    qa          = "0.9"
    integration = "0.9"
    preprod     = "0.9"
    production  = "0.7" //needs some for HTME Scans and some for Reconciler Batch-Gets
  }
}

variable "hbase_bulkload_retries_retryOnIOException" {
  type        = map(string)
  description = "When performing a bulk load, attempt retries if io exceptions occur"
  default = {
    development = "true"
    qa          = "true"
    integration = "true"
    preprod     = "true"
    production  = "true"
  }
}

variable "hbase_bulkload_retries_number" {
  type        = map(number)
  description = "When performing a bulk load, number of retries to attempt if io exceptions occur"
  default = {
    development = 10
    qa          = 10
    integration = 10
    preprod     = 10
    production  = 10
  }
}

variable "hbase_bucketcache_bucket_sizes" {
  type        = map(string)
  description = "Must be multiples of default block size (64KB) as comma delimited string, enables large bucket cache for storing lots of blocks"
  default = {
    development = "5120,9216,17408,33792,41984,50176,58368,66560,99328,132096,197632,263168,394240,525312,656384,787456,918528,1049600,1180672,1311744,1442816,1704960,1967104,2229248"
    qa          = "5120,9216,17408,33792,41984,50176,58368,66560,99328,132096,197632,263168,394240,525312,656384,787456,918528,1049600,1180672,1311744,1442816,1704960,1967104,2229248"
    integration = "5120,9216,17408,33792,41984,50176,58368,66560,99328,132096,197632,263168,394240,525312,656384,787456,918528,1049600,1180672,1311744,1442816,1704960,1967104,2229248"
    preprod     = "5120,9216,17408,33792,41984,50176,58368,66560,99328,132096,197632,263168,394240,525312,656384,787456,918528,1049600,1180672,1311744,1442816,1704960,1967104,2229248"
    production  = "5120,9216,17408,33792,41984,50176,58368,66560,99328,132096,197632,263168,394240,525312,656384,787456,918528,1049600,1180672,1311744,1442816,1704960,1967104,2229248"
  }
}

variable "hbase_client_write_buffer" {
  type        = map(number)
  description = "Allows clients to batch up puts within a write and then write them all at once (default is 2097152)"
  default = {
    development = 2097152
    qa          = 2097152
    integration = 2097152
    preprod     = 2097152
    production  = 8388608
  }
}

variable "hbase_regionserver_storefile_refresh_period_milliseconds" {
  type        = map(number)
  description = "Refreshes read replica regions from primary region in this time, can't be the default (0) if read replica regions enabled"
  default = {
    development = 30000
    qa          = 30000
    integration = 30000
    preprod     = 30000
    production  = 30000
  }
}

variable "hbase_regionserver_meta_storefile_refresh_period_milliseconds" {
  type        = map(number)
  description = "Refreshes read replica meta tables from primary meta table in this time, can't be the default (0) if meta replicas enabled"
  default = {
    development = 0
    qa          = 0
    integration = 0
    preprod     = 0
    production  = 0
  }
}

variable "hbase_regionserver_storefile_refresh_all" {
  type        = map(bool)
  description = "Enables the store file refresh to replicated regions in the refresh time specific above"
  default = {
    development = true
    qa          = true
    integration = true
    preprod     = true
    production  = true
  }
}

variable "hbase_master_hfilecleaner_ttl" {
  type        = map(number)
  description = "Keeps store files in the archive folder for this length, must be larger then hbase_regionserver_storefile_refresh_period_milliseconds"
  default = {
    development = 3600000
    qa          = 3600000
    integration = 3600000
    preprod     = 3600000
    production  = 172800000 # Recommended by AWS
  }
}

variable "hbase_region_replica_wait_for_primary_flush" {
  type        = map(string)
  description = "When new region servers created, only populate replicas when a flush has been performed to stop replica having out of date region data"
  default = {
    development = "true"
    qa          = "true"
    integration = "true"
    preprod     = "true"
    production  = "true"
  }
}

variable "hbase_meta_replica_count" {
  type        = map(number)
  description = "The number of replicas of the meta table - must be 2 or 3 in case the primary meta table goes down (max is 3)"
  default = {
    development = 3
    qa          = 3
    integration = 3
    preprod     = 3
    production  = 3 # Recommended by AWS
  }
}

variable "hbase_emr_storage_mode" {
  type        = map(string)
  description = "Storage mode for the cluster - must be s3 as we use that as the storage for EMR HBase cluste"
  default = {
    development = "s3"
    qa          = "s3"
    integration = "s3"
    preprod     = "s3"
    production  = "s3"
  }
}

# The master is not heavy on CPU or RAM so it can be a fairly small box, with high network throughput
variable "hbase_master_instance_type" {
  type        = map(string)
  description = "The instance type for the master nodes - if changing, you should also look to change hbase_namenode_hdfs_threads to match new vCPU value"
  default = {
    development = "m5.xlarge"
    qa          = "m4.large"
    integration = "m4.large"
    preprod     = "m4.large"
    production  = "r5.8xlarge" # Larger to allow memory for bulk loading reductions
  }
}

variable "hbase_master_instance_count" {
  type        = map(number)
  description = "Number of master instances, should be 1 or 3 to enable multiple masters"
  default = {
    // External Hive metastore required for multiple master nodes
    development = 1
    qa          = 1
    integration = 1
    preprod     = 1
    production  = 1
  }
}

variable "hbase_master_ebs_size" {
  type        = map(number)
  description = "Size of disk for the master, as the name node storage is on the master, this needs to be a reasonable amount"
  default = {
    development = 167
    qa          = 167
    integration = 167
    preprod     = 167
    production  = 667
  }
}

variable "hbase_master_ebs_type" {
  type        = map(string)
  description = "Type of disk for the cores, gp2 is by far the cheapest (until EMR supports gp3) and throughput can be gained with size"
  default = {
    development = "gp2"
    qa          = "gp2"
    integration = "gp2"
    preprod     = "gp2"
    production  = "gp2"
  }
}

# EMR only gives max 32GB memory to region stores so more is a waste
# More vCPUs allow more threads handling work, so it's a balance between this and cost
variable "hbase_core_instance_type_one" {
  type        = map(string)
  description = "The instance type for the core nodes - if changing, you should also look to change hbase_regionserver_handler_count and hbase_datanode_hdfs_threads to match new vCPU value"
  default = {
    development = "m4.large"
    qa          = "m4.large"
    integration = "m4.large"
    preprod     = "m4.large"
    production  = "m5.2xlarge" # Due to eu-#west-2a AZ outtage, r5's are a no go right now.
  }
}

variable "hbase_core_instance_type_two" {
  type        = map(string)
  description = "The instance type for the core nodes - if changing, you should also look to change hbase_regionserver_handler_count and hbase_datanode_hdfs_threads to match new vCPU value"
  default = {
    development = "m5a.large"
    qa          = "m5a.large"
    integration = "m5a.large"
    preprod     = "m5a.large"
    production  = "m5a.2xlarge" # Due to eu-#west-2a AZ outtage, r5's are a no go right now.
  }
}

variable "hbase_core_instance_type_three" {
  type        = map(string)
  description = "The instance type for the core nodes - if changing, you should also look to change hbase_regionserver_handler_count and hbase_datanode_hdfs_threads to match new vCPU value"
  default = {
    development = "m5d.large"
    qa          = "m5d.large"
    integration = "m5d.large"
    preprod     = "m5d.large"
    production  = "m5d.2xlarge" # Due to eu-#west-2a AZ outtage, r5's are a no go right now.
  }
}

variable "hbase_regionserver_handler_count" {
  type        = map(number)
  description = "The number of handlers for each region server, should be roughly equivalent to 8x vCPUs - if instance type for core nodes changed, change this too"
  default = {
    development = 2
    qa          = 2
    integration = 2
    preprod     = 2
    production  = 96 // 8x the vCPUs as a reasonable estimate. see hbase_core_instance_type -> for the m5.2xlarge as above.
  }
}

# Region servers should look to serve around 100 regions or less each for optimal performance
variable "hbase_core_instance_count" {
  type        = map(number)
  description = "The number of cores (region servers) to deploy"
  default = {
    development = 4
    qa          = 4
    integration = 4
    preprod     = 4
    production  = 175
  }
}

variable "hbase_core_ebs_size" {
  type        = map(number)
  description = "Size of disk for the cores, as the HDFS for the write cache are on the cores, this needs to be a reasonable amount"
  default = {
    development = 167
    qa          = 167
    integration = 167
    preprod     = 167
    production  = 667
  }
}

variable "hbase_core_ebs_type" {
  type        = map(string)
  description = "Type of disk for the cores, gp2 is by far the cheapest (until EMR supports gp3) and throughput can be gained with size"
  default = {
    development = "gp2"
    qa          = "gp2"
    integration = "gp2"
    preprod     = "gp2"
    production  = "gp2"
  }
}

variable "hbase_namenode_hdfs_threads" {
  type        = map(number)
  description = "The number of threads handling writes and reads to name nodes on the master, number of vCPUs on the master should be considered"
  default = {
    development = 10
    qa          = 10
    integration = 10
    preprod     = 10
    production  = 42
  }
}

variable "hbase_datanode_hdfs_threads" {
  type        = map(number)
  description = "The number of threads handling writes and reads to data nodes on the cores, number of vCPUs on the cores should be considered"
  default = {
    development = 3
    qa          = 3
    integration = 3
    preprod     = 3
    production  = 12
  }
}

variable "hbase_datanode_max_transfer_threads" {
  type        = map(number)
  description = "Upper bound on the number of files that the hadoop data nodes can serve at any one time"
  default = {
    development = 4096
    qa          = 4096
    integration = 4096
    preprod     = 4096
    production  = 8192
  }
}

variable "hbase_client_socket_timeout" {
  type        = map(number)
  description = "Timeout in milliseconds for a connection to HDFS (default 60000)"
  default = {
    development = 60000
    qa          = 60000
    integration = 60000
    preprod     = 60000
    production  = 90000
  }
}

variable "hbase_datanode_socket_write_timeout" {
  type        = map(number)
  description = "Timeout in milliseconds for a write to HDFS (default 480000)"
  default = {
    development = 480000
    qa          = 480000
    integration = 480000
    preprod     = 480000
    production  = 600000
  }
}

variable "hbase_compaction_offpeak_start" {
  type        = map(number)
  description = "Start time from midnight in hours of off peak period (default is -1 which is off)"
  default = {
    development = 15
    qa          = 15
    integration = 15
    preprod     = 15
    production  = 15 # Start off peak after full export and some ingestion
  }
}

variable "hbase_compaction_offpeak_end" {
  type        = map(number)
  description = "End time from midnight in hours of off peak period (default is -1 which is off)"
  default = {
    development = 17
    qa          = 17
    integration = 17
    preprod     = 17
    production  = 17 # End off peak in time for kafka ingestion to catch up before midnight
  }
}

variable "hbase_compaction_ratio" {
  type        = map(number)
  description = "Ratio of storefiles larger than compaction min size including in peak time compactions (default is 1.2)"
  default = {
    development = 0.1
    qa          = 0.1
    integration = 0.1
    preprod     = 0.1
    production  = 0.1 # Very low to effectively turn it off during peak times
  }
}

variable "hbase_compaction_ratio_offpeak" {
  type        = map(number)
  description = "Ratio of storefiles larger than compaction min size included in offpeak compactions (default is 5.0)"
  default = {
    development = 5.0
    qa          = 5.0
    integration = 5.0
    preprod     = 5.0
    production  = 5.0
  }
}

variable "hbase_assignment_usezk" {
  type        = map(bool)
  description = "Enables the regions to be stored in Zookeeper as well as HBase master - we turn off so that Zookeeper doesn't get out of sync with the HBase master"
  default = {
    development = false
    qa          = false
    integration = false
    preprod     = false
    production  = false # Recommended by AWS
  }
}

//output "hbase_replica" {
//  value = aws_emr_cluster.hbase_read_replica
//}
//
//output "hbase_replica_cluster_counts" {
//  value = {
//    core_instance_count   = var.hbase_core_instance_count[local.environment]
//    master_instance_count = var.hbase_master_instance_count[local.environment]
//  }
//}
