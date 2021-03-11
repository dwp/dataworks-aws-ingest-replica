variable "emr_al2_ami_id" {
  type = string
}

variable "hbase_master_instance_type" {
  type        = map(string)
  description = "The instance type for the master nodes - if changing, you should also look to change hbase_namenode_hdfs_threads to match new vCPU value"
  default = {
    development = "m4.xlarge"
    qa          = "m4.xlarge"
    integration = "m4.xlarge"
    preprod     = "m4.xlarge"
    production  = "r5.8xlarge"
    # Larger to allow memory for bulk loading reductions
  }
}

variable "hbase_master_instance_count" {
  type        = map(number)
  description = "Number of master instances, should be 1 or 3 to enable multiple masters"
  default = {
    development = 1
    qa          = 1
    integration = 3
    preprod     = 3
    production  = 3
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
    development = "m4.xlarge"
    qa          = "m4.xlarge"
    integration = "m4.xlarge"
    preprod     = "m4.xlarge"
    production  = "m5.2xlarge"
    # Due to eu-/west/-2a AZ outage, r5's are a no go right now.
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


variable "hbase_ssmenabled" {
  type        = map(string)
  description = "Switch for setting SSM on/off - moved from ingest-hbase locals"
  default = {
    development = "True"
    qa          = "True"
    integration = "True"
    preprod     = "False" // OFF by IAM Policy
    production  = "False" // OFF by IAM Policy
  }
}

variable "hbase_az" {
  type        = map(string)
  description = "Availability Zone for HBase, moved from locals"
  default = {
    development = "eu-west-2a"
    qa          = "eu-west-2a"
    integration = "eu-west-2a"
    preprod     = "eu-west-2a"
    production  = "eu-west-2a"
  }

}