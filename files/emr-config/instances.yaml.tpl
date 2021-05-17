---
Instances:
  KeepJobFlowAliveWhenNoSteps: ${keep_cluster_alive}
  AdditionalMasterSecurityGroups:
    - "${add_master_sg_id}"
  AdditionalSlaveSecurityGroups:
    - "${add_slave_sg_id}"
  Ec2SubnetId: "${ec2_subnet_id}"
  EmrManagedMasterSecurityGroup: "${emr_managed_master_sg_id}"
  EmrManagedSlaveSecurityGroup: "${emr_managed_slave_sg_id}"
  ServiceAccessSecurityGroup: "${service_access_sg_id}"
  InstanceFleets:
    - InstanceFleetType: "MASTER"
      Name: MASTER
      TargetOnDemandCapacity: ${master_instance_count}
      InstanceTypeConfigs:
        - EbsConfiguration:
            EbsBlockDeviceConfigs:
              - VolumeSpecification:
                  SizeInGB: ${master_instance_ebs_vol_gb}
                  VolumeType: "${master_instance_ebs_vol_type}"
                VolumesPerInstance: 1
          InstanceType: "${master_instance_type}"
    - InstanceFleetType: "CORE"
      Name: CORE
      TargetOnDemandCapacity: ${core_instance_count}
      InstanceTypeConfigs:
        - EbsConfiguration:
            EbsBlockDeviceConfigs:
              - VolumeSpecification:
                  SizeInGB: ${core_instance_ebs_vol_gb}
                  VolumeType: "${core_instance_ebs_vol_type}"
                VolumesPerInstance: 1
          InstanceType: "${core_instance_type}"