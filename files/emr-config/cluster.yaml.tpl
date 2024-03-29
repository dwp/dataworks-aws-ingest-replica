---
Applications:
%{ for application in  spark_applications }- Name: "${application}"
%{ endfor }
CustomAmiId: "${ami_id}"
EbsRootVolumeSize: 40
LogUri: "s3://${s3_log_bucket}/${s3_log_prefix}"
Name: "${emr_cluster_name}"
ReleaseLabel: "emr-${emr_release}"
SecurityConfiguration: "${security_configuration}"
ScaleDownBehavior: "${scale_down_behaviour}"
ServiceRole: "${service_role}"
JobFlowRole: "${instance_profile}"
VisibleToAllUsers: True
Tags:
- Key: "Persistence"
  Value: "Ignore"
- Key: "Owner"
  Value: "dataworks platform"
- Key: "AutoShutdown"
  Value: "False"
- Key: "CreatedBy"
  Value: "emr-launcher"
- Key: "SSMEnabled"
  Value: "True"
- Key: "Environment"
  Value: "development"
- Key: "Application"
  Value: "dataworks-aws-ingest-replica"
- Key: "Name"
  Value: "ingest-replica"
- Key: "for-use-with-amazon-emr-managed-policies"
  Value: "true"
