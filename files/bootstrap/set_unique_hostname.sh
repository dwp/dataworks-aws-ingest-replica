#!/usr/bin/env bash

echo "Setting proxy"
FULL_PROXY="${full_proxy}"
FULL_NO_PROXY="${full_no_proxy}"
export http_proxy="$FULL_PROXY"
export HTTP_PROXY="$FULL_PROXY"
export https_proxy="$FULL_PROXY"
export HTTPS_PROXY="$FULL_PROXY"
export no_proxy="$FULL_NO_PROXY"
export NO_PROXY="$FULL_NO_PROXY"

# rename ec2 instance to be unique
export AWS_DEFAULT_REGION=${aws_default_region}
UUID=$(dbus-uuidgen | cut -c 1-8)
TOKEN=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" "http://169.254.169.254/latest/api/token")

instance=$(curl -H "X-aws-ec2-metadata-token:$TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
role=$(jq .instanceRole /mnt/var/lib/info/extraInstanceData.json)
host="${name}-$${INSTANCE_ROLE//\"}-$UUID"

export INSTANCE_ID="$instance"
export INSTANCE_ROLE="$role"
export HOSTNAME="$host"

hostnamectl set-hostname "$HOSTNAME"
aws ec2 create-tags --resources "$INSTANCE_ID" --tags Key=Name,Value="$HOSTNAME"
