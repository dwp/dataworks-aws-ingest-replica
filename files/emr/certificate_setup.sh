#!/usr/bin/env bash
echo "Creating directories"
sudo mkdir -p /opt/emr
sudo mkdir -p /var/log/acm
sudo mkdir -p /var/log/cdl
sudo mkdir -p /var/log/hdl
sudo chown hadoop:hadoop /opt/emr
sudo chown hadoop:hadoop /var/log/acm
sudo chown hadoop:hadoop /var/log/cdl
sudo chown hadoop:hadoop /var/log/hdl
sudo chmod a+rwx /var/log/acm

(
echo "Downloading metadata store certificate"
aws s3 cp "s3://${s3_scripts_bucket}/${s3_script_amazon_root_ca1_pem}" /opt/emr/AmazonRootCA1.pem

export AWS_DEFAULT_REGION=${aws_default_region}

echo "Setting proxy"
FULL_PROXY="${full_proxy}"
FULL_NO_PROXY="${full_no_proxy}"
export http_proxy="$FULL_PROXY"
export HTTP_PROXY="$FULL_PROXY"
export https_proxy="$FULL_PROXY"
export HTTPS_PROXY="$FULL_PROXY"
export no_proxy="$FULL_NO_PROXY"
export NO_PROXY="$FULL_NO_PROXY"

echo "Get DKS certificate"
export TRUSTSTORE_PASSWORD=$(uuidgen -r)
export KEYSTORE_PASSWORD=$(uuidgen -r)
export PRIVATE_KEY_PASSWORD=$(uuidgen -r)
export ACM_KEY_PASSWORD=$(uuidgen -r)

touch /opt/emr/dks.properties
cat >> /opt/emr/dks.properties <<EOF
identity.store.alias=${private_key_alias}
identity.key.password=$PRIVATE_KEY_PASSWORD
spark.ssl.fs.enabled=true
spark.ssl.keyPassword=$KEYSTORE_PASSWORD
identity.keystore=/opt/emr/keystore.jks
identity.store.password=$KEYSTORE_PASSWORD
trust.keystore=/opt/emr/truststore.jks
trust.store.password=$TRUSTSTORE_PASSWORD
data.key.service.url=${dks_endpoint}
EOF

acm-cert-retriever \
    --acm-cert-arn "${acm_cert_arn}" \
    --acm-key-passphrase "$ACM_KEY_PASSWORD" \
    --keystore-path "/opt/emr/keystore.jks" \
    --keystore-password "$KEYSTORE_PASSWORD" \
    --private-key-alias "${private_key_alias}" \
    --private-key-password "$PRIVATE_KEY_PASSWORD" \
    --truststore-path "/opt/emr/truststore.jks" \
    --truststore-password "$TRUSTSTORE_PASSWORD" \
    --truststore-aliases "${truststore_aliases}" \
    --truststore-certs "${truststore_certs}" \
    --jks-only true >> /var/log/acm/acm-cert-retriever.log 2>&1


sudo -E acm-cert-retriever \
    --acm-cert-arn "${acm_cert_arn}" \
    --acm-key-passphrase "$ACM_KEY_PASSWORD" \
    --private-key-alias "${private_key_alias}" \
    --truststore-aliases "${truststore_aliases}" \
    --truststore-certs "${truststore_certs}"  >> /var/log/acm/acm-cert-retriever.log 2>&1


echo "Completed the certificate-setup.sh step of the EMR Cluster"

) >> /var/log/acm/nohup.log 2>&1
