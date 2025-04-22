#!/bin/bash
source config.sh

SMB_SERVER="172.16.10.171"
SMB_DIR="backup_logs"

# Check whether SMB shared folder exists
if ! smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -L "$SMB_SERVER" | grep -q "$SMB_DIR"; then
    echo "Error: Shared folder '$SMB_DIR' does not exist."
    exit 1
fi

# Retrieve current database names under the backup service directory
databases=($(ls /hana/backup/NDB_shihana.sapb1mm.com_30013/NDB | grep "LIVE"))

# Get yesterday's and today's dates in the format used in the backup file
YESTERDAY=$(date -d "yesterday" +%Y%m%d)
TODAY=$(date +%Y%m%d)

# Iterate over each database backup
for database in "${databases[@]}"; do
    # Define the base directory where backup files are created
    backup_dir="/hana/backup/NDB_shihana.sapb1mm.com_30013/NDB/$database"

    # Find the backup file for yesterday and today
    yesterdayFile=$(find "$backup_dir" -type f -name "bck_${YESTERDAY}*.zip")
    todayFile=$(find "$backup_dir" -type f -name "bck_${TODAY}*.zip")

    # Check if the backup files were found
    if [ -n "$yesterdayFile" ]; then
        echo "$database backup for yesterday exists."
    elif [ -n "$todayFile" ]; then
        echo "$database backup for today exists."
    else
        echo "$database backup does not exist."

        # Define the log file for the database
        LOG_FILE="/var/log/SAPBusinessOne/BackupService/logs/NDB_shihana.sapb1mm.com_30013/$database.log"

        # Get yesterday's date in the format used in the log
        YESTERDAY_LOG_DATE=$(date -d "yesterday" +'%y%m%d')

        # Extract yesterday's logs using the delimiter "-------------"
        YESTERDAYS_LOG=$(awk -v yesterday="$YESTERDAY_LOG_DATE" '/----------------------------/{f=0} $0 ~ yesterday{f=1} f' "$LOG_FILE")

        # Copy yesterday's backup log to SMB server (tsplus gw)
        echo "$YESTERDAYS_LOG" >> "$database@$HOSTNAME.txt"
        smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $database@$HOSTNAME.txt" "//$SMB_SERVER/$SMB_DIR"
        rm "$database@$HOSTNAME.txt"
    fi
done
