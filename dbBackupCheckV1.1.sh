#!/bin/bash
source config.sh

SMB_SERVER="10.10.0.110"
SMB_DIR="backup_logs"

# Define the base directory where backups files are created
backup_dir="/hana/backup/backups/SPB_spbhana.sapb1mm.com_30013/SPB/$1"


# Get yesterday's and today's dates in the format used in the backup file
YESTERDAY=$(date -d "yesterday" +%Y%m%d)
TODAY=$(date -d "today" +%Y%m%d)


# Check whether smb shared folder exist
if ! smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -L "$SMB_SERVER" | grep -q "$SMB_DIR"; then
    echo "Error: Shared folder '$SMB_DIR' does not exist."
    exit 1
fi

file=$(find "$backup_dir" -type f -name "bck_${YESTERDAY}*.zip")



# Find the backup file for yesterday and today
yesterdayFile=$(find "$backup_dir" -type f -name "bck_${YESTERDAY}*.zip")
todayFile=$(find "$backup_dir" -type f -name "bck_${TODAY}*.zip")

# Check if the backup files were found
if [ -n "$yesterdayFile" ]; then
    echo "$1 backup for yesterday exists"
elif [ -n "$todayFile" ]; then
    echo "$1 backup for today exists"
else
    echo "$1 backup does not exist"

    # Define the log file for the database
    LOG_FILE="/var/log/SAPBusinessOne/BackupService/logs/SPB_spbhana.sapb1mm.com_30013/$1.log"

    # Get yesterday's date in the format used in the log
    YESTERDAY_LOG_DATE=$(date -d "yesterday" +'%y%m%d')

    # Extract yesterday's logs using the delimiter "-------------" if log file exists
    if [ ! -s "$LOG_FILE" ]; then
      echo "Log file not found or empty: $LOG_FILE"
    else
      echo "Log file found"
    fi

    YESTERDAYS_LOG=$(awk -v yesterday="$YESTERDAY_LOG_DATE" '/----------------------------/{f=0} $0 ~ yesterday{f=1} f' $LOGFILE)

    #copy yesterday's backup log to smbserver(tsplus gw)
    echo -e "Neither the database backup file with today's date nor the one with yesterday's date for $1 database is found in the backup directory at $date.\n\n" > "$database@$HOSTNAME.txt"
    echo "$YESTERDAYS_LOG" >> "$1@$HOSTNAME.txt"
    smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $1@$HOSTNAME.txt" "//$SMB_SERVER/$SMB_DIR"
    rm "$1@$HOSTNAME.txt"
fi
