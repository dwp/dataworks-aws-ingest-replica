#!/bin/bash

sudo mkdir -p /var/log/emr-bootstrap/
sudo mkdir -p /opt/emr
sudo mkdir -p /opt/shared
sudo mkdir -p /var/ci

sudo chown hadoop:hadoop /var/log/emr-bootstrap/
sudo chown hadoop:hadoop /opt/emr
sudo chown hadoop:hadoop /opt/shared
sudo chown hadoop:hadoop /var/ci

# Download the logging scripts
$(which aws) s3 cp "${S3_COMMON_LOGGING_SHELL}"  /opt/shared/common_logging.sh
$(which aws) s3 cp "${S3_LOGGING_SHELL}"         /opt/emr/logging.sh

# Set permissions
chmod u+x /opt/shared/common_logging.sh
chmod u+x /opt/emr/logging.sh

echo "${ENVIRONMENT_NAME}" > /opt/emr/environment
echo "${EMR_LOG_LEVEL}" > /opt/emr/log_level


(
    # Import the logging functions
    source /opt/emr/logging.sh

    function log_wrapper_message() {
        log_incremental_replica_message "$${1}" "download_scripts.sh" "$${PID}" "$${@:2}" "Running as: ,$USER"
    }

    log_wrapper_message "Downloading latest bootstrap scripts"
    $(which aws) s3 cp --recursive "${bootstrap_scripts_location}/" /var/ci/ --include "*.sh"
    log_wrapper_message "Downloading latest step scripts"
    $(which aws) s3 cp --recursive "${step_scripts_location}/" /var/ci/ --include "*.sh"

    log_wrapper_message "Applying recursive execute permissions to the folder"
    sudo chmod --recursive a+rx /var/ci

    log_wrapper_message "Script downloads completed"

)  >> /var/log/emr-bootstrap/download_scripts.log 2>&1
