#!/bin/bash
source config.sh
SMB_SERVER="192.168.46.13"
SMB_DIR="data1"
SAP_LOG_DIR=/var/log/SAPBusinessOne
HANA_LOG_DIR=/var/log/HANA
mkdir -p $SAP_LOG_DIR
mkdir -p $HANA_LOG_DIR

start_sap() {
    local retries=10
    local count=0
    echo "Starting $1"
    systemctl start $1 > $SAP_LOG_DIR/$HOSTNAME.$1.log 2>&1
    while true; do
        if systemctl is-active --quiet $1; then
            echo "$1 has been started successfully."
            break
        fi

        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            echo "Failed to start $1 after retries. Exiting..."
            smbclient "//$SMB_SERVER/$SMB_DIR" -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $SAP_LOG_DIR/$HOSTNAME.$1.log $HOSTNAME.$1.log" || echo "SMB upload failed."
            exit 1
        fi
        echo "$1 has not started yet. Retrying..."
        sleep 3
    done
}

stop_sap() {
    local retries=10
    local count=0
    echo "Stopping $1"
    systemctl stop "$1" > $SAP_LOG_DIR/$HOSTNAME.$1.log 2>&1
    while true; do
        if ! systemctl is-active --quiet "$1"; then
            echo "$1 has been stopped successfully."
            break
        fi

        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            echo "Failed to stop $1 after retries. Exiting..."
            smbclient "//$SMB_SERVER/$SMB_DIR" -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $SAP_LOG_DIR/$HOSTNAME.$1.log $HOSTNAME.$1.log" || echo "SMB upload failed."
            exit 1
        fi
        echo "$1 has not stopped yet. Retrying..."
        sleep 3
    done
}


hana_running() {
    if ! pgrep -u ndbadm HDB > /dev/null; then
        return 1  # HANA service is not running
    fi
    return 0  # HANA service is running
}


stop_hana() {
        echo "Stopping HANA database services..."
        timeout 3600 su - ndbadm -c "HDB stop" > $HANA_LOG_DIR/$HOSTNAME.hanaservice.log 2>&1
        if ! hana_running; then
                echo "HANA Database has been stopped successfully."
        else
                echo "HANA Database failed to stop within timeout. Exiting..."
                smbclient "//$SMB_SERVER/$SMB_DIR" -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $HANA_LOG_DIR/$HOSTNAME.hanaservice.log $HOSTNAME.hanaservice.log" || echo "SMB upload failed."
                #Below lines are to restart sap service if hana service cannot be stopped
                start_sap sapb1servertools.service
                stop_sap sapb1servertools-authentication.service
                start_sap sapb1servertools-authentication.service
                exit 1
        fi
}

start_hana() {
        echo "Starting HANA database services..."
        timeout 3600 su - ndbadm -c "HDB start" > $HANA_LOG_DIR/$HOSTNAME.hanaservice.log 2>&1
        if hana_running; then
                echo "HANA Database has been started successfully."
        else
                echo "HANA Database failed to start within timeout. Exiting..."
                smbclient "//$SMB_SERVER/$SMB_DIR" -W WORKGROUP --user="$SMB_USER%$SMB_PASS" -c "put $HANA_LOG_DIR/$HOSTNAME.hanaservice.log $HOSTNAME.hanaservice.log" || echo "SMB upload failed."
                exit 1
        fi
}

# Step 1: Stop SAP Business One Server Tools service
stop_sap sapb1servertools.service

# Step 2: stop HANA Database
stop_hana

# Step 3: Start HANA Database
start_hana

# Step 4: Stop SAP Business One Server Tools service again
stop_sap sapb1servertools.service

# Step 5: Start SAP Business One Server Tools service
start_sap sapb1servertools.service

# Step 6: Stop SAP Business One Authentication Service
stop_sap sapb1servertools-authentication.service

# Step 7: Start SAP Business One Authentication Service
start_sap sapb1servertools-authentication.service
