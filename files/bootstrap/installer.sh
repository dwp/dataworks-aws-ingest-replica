#!/bin/bash

FULL_PROXY="${full_proxy}"
FULL_NO_PROXY="${full_no_proxy}"
export http_proxy="$FULL_PROXY"
export HTTP_PROXY="$FULL_PROXY"
export https_proxy="$FULL_PROXY"
export HTTPS_PROXY="$FULL_PROXY"
export no_proxy="$FULL_NO_PROXY"
export NO_PROXY="$FULL_NO_PROXY"

if [ ! -d "/var/log/emr-bootstrap" ]; then
  sudo mkdir -p /var/log/emr-bootstrap
  sudo chown hadoop:hadoop /var/log/emr-bootstrap
fi

PIP=/usr/local/bin/pip3

if [ ! -x $PIP ]; then
  # EMR <= 5.29.0 doesn't install a /usr/bin/pip3 wrapper
  PIP=/usr/bin/pip3
fi

if [ ! -x $PIP ]; then
  # EMR <= 5.29.0 doesn't install a /usr/bin/pip3 wrapper
  PIP=/usr/bin/pip-3.6
fi

if [ ! -x $PIP ]; then
  # PIP not found
  echo "pip3 not found" >> /var/log/emr-bootstrap/installer.log 2>&1
  exit 1
fi

sudo /var/ci/cloudwatch.sh

#shellcheck disable=SC2024
sudo -E $PIP install boto3 >> /var/log/emr-bootstrap/install-boto3.log 2>&1
#shellcheck disable=SC2024
sudo -E $PIP install requests >> /var/log/emr-bootstrap/install-requests.log 2>&1
#shellcheck disable=SC2024
{
  sudo yum install -y python3-devel
  sudo -E $PIP install pycryptodome
  sudo yum remove -y python3-devel
} >> /var/log/emr-bootstrap/install-pycrypto.log 2>&1
