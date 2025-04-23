#!/bin/bash
source config.sh
LOG_DIR=/var/log/SAPBusinessOne
mkdir -p "$LOG_DIR"

copy_smb(){
SMB_SERVER="172.16.10.171"
SMB_DIR="backup_logs"
smbclient "//$SMB_SERVER/$SMB_DIR" -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $LOG_DIR/$HOSTNAME.$1.log $HOSTNAME.$1.log" || echo "SMB upload failed."
}

copy_smb hanaservice
