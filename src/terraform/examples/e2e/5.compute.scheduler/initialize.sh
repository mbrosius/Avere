#!/bin/bash -ex

source /etc/profile.d/aaa.sh # https://github.com/Azure/WALinuxAgent/issues/1561

%{ for fsMount in fileSystemMounts }
  fsMountPoint=$(cut -d ' ' -f 2 <<< "${fsMount}")
  mkdir -p $fsMountPoint
  echo "${fsMount}" >> /etc/fstab
%{ endfor }
mount -a

databaseHost=$(hostname)
databasePort=27100
databaseName="deadline10db"
deadlinecommand -UpdateDatabaseSettings /DeadlineRepository MongoDB $databaseHost $databaseName $databasePort 0 false false "" "" "" false

customDataInput="/var/lib/waagent/ovf-env.xml"
customDataOutput="/var/lib/waagent/scale.sh"
if [ -f $customDataInput ]; then
  customData=$(xmllint --xpath "//*[local-name()='Environment']/*[local-name()='ProvisioningSection']/*[local-name()='LinuxProvisioningConfigurationSet']/*[local-name()='CustomData']/text()" $customDataInput)
  echo $customData | base64 -d | gzip -d > $customDataOutput

  servicePath="/etc/systemd/system/scale.service"
  echo "[Unit]" > $servicePath
  echo "Description=Render Farm Scaler Service" >> $servicePath
  echo "" >> $servicePath
  echo "[Service]" >> $servicePath
  echo "Environment=PATH=$schedulerPath:$PATH" >> $servicePath
  echo "ExecStart=/bin/bash $customDataOutput" >> $servicePath
  echo "" >> $servicePath
  timerPath="/etc/systemd/system/scale.timer"
  echo "[Unit]" > $timerPath
  echo "Description=Render Farm Scaler Timer" >> $timerPath
  echo "" >> $timerPath
  echo "[Timer]" >> $timerPath
  echo "OnBootSec=10" >> $timerPath
  echo "OnUnitActiveSec=60" >> $timerPath
  echo "AccuracySec=1us" >> $timerPath
  echo "" >> $timerPath
  echo "[Install]" >> $timerPath
  echo "WantedBy=timers.target" >> $timerPath
  systemctl enable scale.timer
  systemctl start scale.timer
fi
