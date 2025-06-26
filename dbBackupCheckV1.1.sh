#!/bin/bash

# dbBackupCheck.sh - A script to check for database backups and send notifications
# Usage: ./dbBackupCheck.sh <database_name>


# Change these values as needed
recipients="user1@example.com, user2@test.com, andrew.saw@vanguardmm.com"
smb_server="vcsbkk.sapb1mm.com"
smb_dir="backup_logs"


# Check if the config.sh file exists and source it
if ! source config.sh; then
    echo "Make a file named config.sh in the current directory and put SMB credentials in that file. Otherwise smb upload won't work."
fi

# Check if the script is run with a database name argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <database_name>"
    exit 1
fi

# Get the log file path based on the database name argument
log_file=$(find /var/log/SAPBusinessOne -type f -name "$1.log" 2>/dev/null | head -n 1)


# Get the backup directory path based on the database name argument
backup_dir=$(find /hana -type d -name "$1" 2>/dev/null | head -n 1)


# Creating .muttrc file if it does not exist
# password is no longer stored in plain text, use app password instead
if [ ! -f ~/.muttrc ]; then
    cat > ~/.muttrc <<EOF
    set from = "backup.alerts.service@gmail.com"
    set realname = "DB Backup Alerts Service"
    set smtp_url = "smtp://backup.alerts.service@gmail.com@smtp.gmail.com:587/"
    set smtp_pass = "your_app_password_here"
    set ssl_starttls = yes
    set ssl_force_tls = yes
EOF
    chmod 600 ~/.muttrc
    echo "Created .muttrc file for mutt configuration."
fi

# Function to send email notification
send_email() {
    local subject="$1"
    local body="$2"
    local recipient="$3"
    local attachment="$4"
    if [ -n "$attachment" ] && [ -f "$attachment" ]; then
        echo "$body" | mutt -F ~/.muttrc -s "$subject" -- "$recipient" -a "$attachment"
    else
        echo "$body" | mutt -F ~/.muttrc -s "$subject" -- "$recipient"
    fi
}

# Function to check internet connectivity
has_internet() {
    ping -c 5 -W 2 8.8.8.8 >/dev/null 2>&1
    return $?
}

# Check if the backup directory exists
if [ ! -d "$backup_dir" ]; then
    if has_internet; then
        echo "Sending email..."
        if ! send_email "Error: Backup directory not found." "Error: Cannot find the backup directory for the '$1' database." "$recipients"; then
            echo "Failed to send email notification."
            echo "Please fill app password in ~/.muttrc."
        fi
        exit 1
    else
    echo "Error: Cannot find the backup directory for the '$1' database." > "$1@$HOSTNAME.txt"
    smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $1@$HOSTNAME.txt" "//$smb_server/$smb_dir"
        if [ $? -ne 0 ]; then
            echo "Failed to upload error file to SMB share."
        else
            echo "Error file uploaded to SMB share successfully."
        fi
        rm -f "$1@$HOSTNAME.txt"    
        exit 1
    fi
fi

# Get yesterday's date in the format used in the backup file
YESTERDAY=$(date -d "yesterday" +%Y%m%d)

# Check if database backup file for yesterday exists
file=$(find "$backup_dir" -type f -name "bck_${YESTERDAY}*.zip")

# Do actions based on whether the backup file exists
if [ -n "$file" ]; then
    echo "Yesterday's backup file found: $file"
else
    # Get yesterday's date in the format used in the log
    YESTERDAY=$(date -d "yesterday" +'%y%m%d')

    # Extract yesterday's backup logs using the delimiter "-------------"
    YESTERDAYS_LOG=$(awk -v yesterday="$YESTERDAY" '/----------------------------/{f=0} $0 ~ yesterday{f=1} f' $log_file)

    # echo yesterday's backup to a temp file
    echo "$YESTERDAYS_LOG" > "$1@$HOSTNAME.txt"

    # Example usage before sending email
    if has_internet; then
        echo "Sending email..."
        if ! send_email "Backup File Not Found" "Database backup file for $1 database was not found at the time of script execution." "$recipients" -a "$1@$HOSTNAME.txt"; then
            echo "Failed to send email notification."
            echo "Please fill app password in ~/.muttrc."
        fi
    else
        echo "No internet connection. Uploading backup log file to TSPlus GW server via smb."
        # Check whether smb shared folder exist
        if smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -L "$smb_server" | grep -q "$smb_dir"; then
            smbclient -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $1@$HOSTNAME.txt" "//$smb_server/$smb_dir"
        else
            echo "Shared folder '$smb_dir' does not exist."
        fi
    fi
    # remove temp file
    rm "$1@$HOSTNAME.txt"
fi
