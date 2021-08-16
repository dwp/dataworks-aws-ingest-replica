variable "emr_release" {
  default = {
    development = "5.30.1"
    qa          = "5.30.1"
    integration = "5.30.1"
    preprod     = "5.30.1"
    production  = "5.30.1"
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
    qa          = "m5.xlarge"
    integration = "m5.xlarge"
    preprod     = "m5.xlarge"
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
    development = "m5.xlarge"
    qa          = "m5.xlarge"
    integration = "m5.xlarge"
    preprod     = "m5.2xlarge"
    production  = "m5.2xlarge" # Due to eu-#west-2a AZ outtage, r5's are a no go right now.
  }
}

variable "hbase_regionserver_handler_count" {
  type        = map(number)
  description = "The number of handlers for each region server, should be roughly equivalent to 8x vCPUs - if instance type for core nodes changed, change this too"
  default = {
    development = 32
    qa          = 32
    integration = 32
    preprod     = 64
    production  = 64 // 8x the vCPUs as a reasonable estimate. see hbase_core_instance_type -> for the m5.2xlarge as above.
  }
}

# Region servers should look to serve around 100 regions or less each for optimal performance
variable "hbase_core_instance_count" {
  type        = map(number)
  description = "The number of cores (region servers) to deploy"
  default = {
    development = 2
    qa          = 2
    integration = 2
    preprod     = 20
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
