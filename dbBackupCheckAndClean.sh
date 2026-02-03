#!/bin/bash
source config.sh

SMB_SERVER="172.16.10.171"
SMB_DIR="backup_logs"
LOG_FILE="/var/log/SAPBusinessOne/BackupService/logs/NDB_ldwhana.sapb1mm.com_30013/$1.log"

# Define the base directory where backups files are created
backup_dir="/hana/backup/NDB_ldwhana.sapb1mm.com_30013/NDB/$1"


# Get yesterday's date in the format used in the backup file
YESTERDAY=$(date -d "yesterday" +%Y%m%d)


# Check whether smb shared folder exist
if ! smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -L "$SMB_SERVER" | grep -q "$SMB_DIR"; then
    echo "Error: Shared folder '$SMB_DIR' does not exist."
    exit 1
fi

file=$(find "$backup_dir" -type f -name "bck_${YESTERDAY}*.zip")

if [ -n "$file" ]; then
    echo "file exist"
else
    # Get yesterday's date in the format used in the log
    YESTERDAY=$(date -d "yesterday" +'%y%m%d')

    # Extract yesterday's backup logs using the delimiter "-------------"
    YESTERDAYS_LOG=$(awk -v yesterday="$YESTERDAY" '/----------------------------/{f=0} $0 ~ yesterday{f=1} f' $LOG_FILE)

    # echo yesterday's backup to a temp file
    echo "$YESTERDAYS_LOG" > "$1@$HOSTNAME.txt"

    # copy temp file to TSPlus GW server via smb
    smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $1@$HOSTNAME.txt" "//$SMB_SERVER/$SMB_DIR"

    # remove temp file
    rm "$1@$HOSTNAME.txt"
fi

# Find and delete backup folders that were modified more than 24 hours ago.
dirs=$(find "$backup_dir" -maxdepth 1 -type d -mmin +1440)


for dir in $dirs; do
  if [ "$dir" != "$backup_dir" ]; then
    rm -rf "$dir"
    echo "Deleted: $dir"
  fi
done
