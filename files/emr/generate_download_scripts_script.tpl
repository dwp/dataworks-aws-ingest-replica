#! /bin/bash

# Make the directory to store the new file if it doesn't exist
sudo mkdir -p /var/ci
sudo chmod a+rwx /var/ci

# ... we have a combination of root, hbase and hadoop users needing access just from running this job
sudo chmod a+rwx /var/log/hbase /var/log/hbase/hbase.log

# Create the script in the right directory
export OUTFILE="/var/ci/download_scripts.sh"
sudo bash -c "cat >$OUTFILE" <<'EOF'
#! /bin/bash
aws s3 cp --recursive ${ingest_emr_scripts_location}/ /var/ci/ --include "*.sh"
sudo chmod --recursive a+rx /var/ci
EOF

# Ensure the new script is executable
sudo chmod a+rx $OUTFILE

# Perform initial download of scripts
/var/ci/download_scripts.sh
