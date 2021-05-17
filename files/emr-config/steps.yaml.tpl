---
BootstrapActions:
- Name: "certificate_setup"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/${certificate_setup_sh_key}"
- Name: "unique_hostname"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/${unique_hostname_sh_key}"
- Name: "start_ssm"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/${start_ssm_sh_key}"
- Name: "installer"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/${installer_sh_key}"
Steps:
  # todo: add steps
- Name: "submit-job"
  HadoopJarStep:
    Args:
    - "exit"
    - "0"
    Jar: "command-runner.jar"
  ActionOnFailure: "${pyspark_action_on_failure}"