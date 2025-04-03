#!/bin/bash
LOG_DIR=/var/log/SAPBusinessOne
mkdir -p $LOG_DIR

start_sap() {
    local retries=20
    local count=0
    echo "Starting $1"
    service $1 start > $LOG_DIR/$HOSTNAME.$1.log 2>&1
    while true; do
        if service $1 status | grep -q "running"; then
            echo "$1 has been started successfully."
            break
        fi

        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            echo "Failed to start $1 after retries. Exiting..."
            exit 1
        fi
        echo "$1 has not started yet. Retrying..."
        sleep 3
    done
}

stop_sap() {
    local retries=20
    local count=0
    echo "Stopping $1"
    service $1 stop > $LOG_DIR/$HOSTNAME.$1.log 2>&1
    while true; do
        if ! service $1 status | grep -q "running"; then
            echo "$1 has been stopped successfully."
            break
        fi

        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            echo "Failed to stop $1 after retries. Exiting..."
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
    timeout 3600 su - ndbadm -c "HDB stop" > $LOG_DIR/$HOSTNAME.hanaservice.log 2>&1
    if ! hana_running; then
        echo "HANA Database has been stopped successfully."
    else
        echo "HANA Database failed to stop within timeout. Exiting..."
        start_sap sapb1servertools
        stop_sap sapb1servertools-authentication
        start_sap sapb1servertools-authentication
        exit 1
    fi
}

start_hana() {
    echo "Starting HANA database services..."
    timeout 3600 su - ndbadm -c "HDB start" > $LOG_DIR/$HOSTNAME.hanaservice.log 2>&1
    if hana_running; then
        echo "HANA Database has been started successfully."
    else
        echo "HANA Database failed to start within timeout. Exiting..."
        exit 1
    fi
}

# Step 1: Stop SAP Business One Server Tools service
stop_sap sapb1servertools

# Step 2: Stop HANA Database
stop_hana

# Step 3: Start HANA Database
start_hana

# Step 4: Stop SAP Business One Server Tools service again
stop_sap sapb1servertools

# Step 5: Start SAP Business One Server Tools service
start_sap sapb1servertools
