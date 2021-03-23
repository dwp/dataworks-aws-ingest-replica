#!/bin/bash

set -Eeuo pipefail

# The below chmod is for removing userData errors that often show up in EMR. It is only placed here for convenience
sudo chmod 444 /var/aws/emr/userData.json

export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r`

# Create config file required for CloudWatch Agent
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > amazon-cloudwatch-agent.json <<CWAGENTCONFIG
{
  "agent": {
    "metrics_collection_interval": ${cwa_metrics_collection_interval},
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "${cwa_log_group_name}",
            "log_stream_name": "{instance_id}-amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${cwa_log_group_name}",
            "log_stream_name": "{instance_id}-messages",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "${cwa_log_group_name}",
            "log_stream_name": "{instance_id}-secure",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${cwa_log_group_name}",
            "log_stream_name": "{instance_id}-cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/acm/acm-cert-retriever.log",
            "log_group_name": "${cwa_log_group_name}",
            "log_stream_name": "{instance_id}-acm-acm-cert-retriever.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/acm/nohup.log",
            "log_group_name": "${cwa_log_group_name}",
            "log_stream_name": "{instance_id}-acm-nohup.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hbase/hbase-hbase-master**.log",
            "log_group_name": "${cwa_hbase_loggrp_name}",
            "log_stream_name": "{instance_id}-hbase-master.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hbase/hbase-hbase-region**.log",
            "log_group_name": "${cwa_hbase_loggrp_name}",
            "log_stream_name": "{instance_id}-hbase-regionserver.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hbase/hbck-details**.log",
            "log_group_name": "${cwa_hbase_hbck_loggrp_name}",
            "log_stream_name": "{instance_id}-hbase-hbck-details.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hbase/major-compaction**.log",
            "log_group_name": "${cwa_hbase_loggrp_steps_name}",
            "log_stream_name": "{instance_id}-hbase-major-compaction.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hbase/snapshot-tables**.log",
            "log_group_name": "${cwa_hbase_loggrp_steps_name}",
            "log_stream_name": "{instance_id}-hbase-snapshot-tables.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hdl/historic-data-loader**.log",
            "log_group_name": "${cwa_hdl_loggrp_name}",
            "log_stream_name": "{instance_id}-historic-data-loader.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cdl/corporate-data-loader**.log",
            "log_group_name": "${cwa_cdl_loggrp_name}",
            "log_stream_name": "{instance_id}-corporate-data-loader.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cdl/setup**.log",
            "log_group_name": "${cwa_cdl_loggrp_name}",
            "log_stream_name": "{instance_id}-setup.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hdl/setup**.log",
            "log_group_name": "${cwa_hdl_loggrp_name}",
            "log_stream_name": "{instance_id}-setup.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/bootstrap-actions/*/stdout**",
            "log_group_name": "${cwa_hbase_loggrp_bootstrapping_name}",
            "log_stream_name": "{instance_id}-stdout.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/bootstrap-actions/*/stderr**",
            "log_group_name": "${cwa_hbase_loggrp_bootstrapping_name}",
            "log_stream_name": "{instance_id}-stderr.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/bootstrap-actions/*/controller**",
            "log_group_name": "${cwa_hbase_loggrp_bootstrapping_name}",
            "log_stream_name": "{instance_id}-controller.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/bootstrap-actions/master**",
            "log_group_name": "${cwa_hbase_loggrp_bootstrapping_name}",
            "log_stream_name": "{instance_id}-master.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/containers/application_*/container_*/stdout**",
            "log_group_name": "${cwa_hbase_loggrp_yarn_name}",
            "log_stream_name": "{instance_id}-stdout.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/containers/application_*/container_*/stderr**",
            "log_group_name": "${cwa_hbase_loggrp_yarn_name}",
            "log_stream_name": "{instance_id}-stderr.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/containers/application_*/container_*/syslog**",
            "log_group_name": "${cwa_hbase_loggrp_yarn_name}",
            "log_stream_name": "{instance_id}-syslog.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/yarn-yarn-nodemanager**.log",
            "log_group_name": "${cwa_hbase_loggrp_yarn_name}",
            "log_stream_name": "{instance_id}-nodemanager.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/hadoop/steps/s-*/stdout**",
            "log_group_name": "${cwa_hbase_loggrp_steps_name}",
            "log_stream_name": "{instance_id}-stdout.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/hadoop/steps/s-*/stderr**",
            "log_group_name": "${cwa_hbase_loggrp_steps_name}",
            "log_stream_name": "{instance_id}-stderr.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/hadoop/steps/s-*/syslog**",
            "log_group_name": "${cwa_hbase_loggrp_steps_name}",
            "log_stream_name": "{instance_id}-syslog.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/mnt/var/log/hadoop/steps/s-*/controller**",
            "log_group_name": "${cwa_hbase_loggrp_steps_name}",
            "log_stream_name": "{instance_id}-controller.log",
            "timezone": "UTC"
          }
        ]
      }
    },
    "log_stream_name": "${cwa_namespace}",
    "force_flush_interval" : 15
  }
}
CWAGENTCONFIG

sudo mv amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/

# Download and install CloudWatch Agent
sudo -E rpm -ivh https://s3.$AWS_DEFAULT_REGION.amazonaws.com/amazoncloudwatch-agent-$AWS_DEFAULT_REGION/centos/amd64/latest/amazon-cloudwatch-agent.rpm

# To maintain CIS compliance
sudo usermod -s /sbin/nologin cwagent

sudo systemctl start amazon-cloudwatch-agent
