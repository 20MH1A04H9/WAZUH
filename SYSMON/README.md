Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

cd $env:USERPROFILE\Downloads

.\Install-Sysmon-Wazuh.ps1
