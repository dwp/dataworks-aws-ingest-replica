#!/bin/bash

set -Eeuo pipefail
# shellcheck disable=SC2034
# shellcheck disable=SC1083
# shellcheck disable=SC2288
(
collection_interval="${cwa_metrics_collection_interval}"
namespace="${cwa_namespace}"
lg_name="${cwa_log_group_name}"
lg_name_bootstrap="${cwa_bootstrap_loggrp_name}"
lg_name_steps="${cwa_steps_loggrp_name}"
lg_name_yarnspark="${cwa_yarnspark_loggrp_name}"
lg_name_tests="${cwa_tests_loggrp_name}"
lg_path_steps="${step_log_path}"

export AWS_DEFAULT_REGION="${aws_default_region}"

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWAGENTCONFIG
{
  "agent": {
    "metrics_collection_interval": $${collection_interval},
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "$${lg_name}",
            "log_stream_name": "{instance_id}-amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "$${lg_name}",
            "log_stream_name": "{instance_id}-messages",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "$${lg_name}",
            "log_stream_name": "{instance_id}-secure",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "$${lg_name}",
            "log_stream_name": "{instance_id}-cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/emr-bootstrap/installer.log",
            "log_group_name": "$${lg_name_bootstrap}",
            "log_stream_name": "{instance_id}-installer.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/emr-bootstrap/install-pycrypto.log",
            "log_group_name": "$${lg_name_bootstrap}",
            "log_stream_name": "{instance_id}-install-pycrypto.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/emr-bootstrap/install-boto3.log",
            "log_group_name": "$${lg_name_bootstrap}",
            "log_stream_name": "{instance_id}-install-boto3.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/emr-bootstrap/install-requests.log",
            "log_group_name": "$${lg_name_bootstrap}",
            "log_stream_name": "{instance_id}-install-requests.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/emr-bootstrap/download_scripts.log",
            "log_group_name": "$${lg_name_bootstrap}",
            "log_stream_name": "{instance_id}-download_scripts.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/emr-bootstrap/acm-cert-retriever.log",
            "log_group_name": "$${lg_name_bootstrap}",
            "log_stream_name": "{instance_id}-acm-cert-retriever.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/containers/application_*/container_*/stdout**",
            "log_group_name": "$${lg_name_yarnspark}",
            "log_stream_name": "{instance_id}-spark-stdout.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/containers/application_*/container_*/stderr**",
            "log_group_name": "$${lg_name_yarnspark}",
            "log_stream_name": "{instance_id}-spark-stderror.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/hadoop-yarn/yarn-yarn-nodemanager**.log",
            "log_group_name": "$${lg_name_yarnspark}",
            "log_stream_name": "{instance_id}-yarn_nodemanager.log",
            "timezone": "UTC"
          },
          {
            "file_path": "$${lg_path_steps}",
            "log_group_name": "$${lg_name_steps}",
            "log_stream_name": "{instance_id}-steps.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/tests.log",
            "log_group_name": "$${lg_name_tests}",
            "log_stream_name": "{instance_id}-tests.log",
            "timezone": "UTC"
          },
        ]
      }
    },
    "log_stream_name": "$${namespace}",
    "force_flush_interval" : 15
  }
}
CWAGENTCONFIG

%{ if emr_release == "5.29.0" ~}
# Download and install CloudWatch Agent
curl https://s3.$${AWS_DEFAULT_REGION}.amazonaws.com/amazoncloudwatch-agent-$${AWS_DEFAULT_REGION}/centos/amd64/latest/amazon-cloudwatch-agent.rpm -O
rpm -U ./amazon-cloudwatch-agent.rpm
# To maintain CIS compliance
usermod -s /sbin/nologin cwagent

start amazon-cloudwatch-agent
%{ else ~}
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl start amazon-cloudwatch-agent
%{ endif ~}
) >> /var/log/emr-bootstrap/enable_cloudwatch.log 2>&1
