---
BootstrapActions:
- Name: "download_scripts"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/${download_scripts_sh_key}"
- Name: "certificate_setup"
  ScriptBootstrapAction:
    Path: "file:/var/ci/certificate_setup.sh"
- Name: "unique_hostname"
  ScriptBootstrapAction:
    Path: "file:/var/ci/set_unique_hostname.sh"
- Name: "start_ssm"
  ScriptBootstrapAction:
    Path: "file:/var/ci/start_ssm.sh"
- Name: "installer"
  ScriptBootstrapAction:
    Path: "file:/var/ci/installer.sh"
Steps:
- Name: "spark-submit"
  HadoopJarStep:
    Args:
      - "spark-submit"
      - "/var/ci/generate_dataset_from_hbase.py"
    Jar: "command-runner.jar"
  ActionOnFailure: "${pyspark_action_on_failure}"
