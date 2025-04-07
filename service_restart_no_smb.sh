#!/bin/bash
source config.sh
LOG_DIR=/var/log/SAPBusinessOne
mkdir -p "$LOG_DIR"

start_sap() {
    local retries=20
    local count=0
    echo "Starting $1"
    systemctl start "$1" > "$LOG_DIR/$HOSTNAME.$1.log" 2>&1
    while true; do
        if systemctl is-active --quiet "$1"; then
            echo "$1 has been started successfully."
            systemctl status "$1" >> "$LOG_DIR/$HOSTNAME.$1.log"
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
    systemctl stop "$1" > "$LOG_DIR/$HOSTNAME.$1.log" 2>&1
    while true; do
        if ! systemctl is-active --quiet "$1"; then
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

check_hana_stopped() {
    local processes=("hdbnameserver" "hdbcompileserver" "hdbpreprocessor" "hdbindexserver" "hdbxsengine" "hdbwebdispatcher")
    local timeout=1800      # Total max wait time in seconds
    local check_interval=10 # Check every X seconds
    local elapsed=0
    local running_services=()

    while [[ $elapsed -lt $timeout ]]; do
        running_services=()  # Reset list on each check

        for process in "${processes[@]}"; do
            if pgrep -u ndbadm -f "$process" > /dev/null; then
                running_services+=("$process")
            fi
        done

        if [[ ${#running_services[@]} -eq 0 ]]; then
            echo "HANA is stopped (all services are stopped)"
            return 0
        fi

        if [[ $elapsed -eq 0 ]]; then
            echo "Waiting for HANA services to stop (timeout: ${timeout}s)..."
        fi
        echo "Waiting for services: ${running_services[*]} to stop ..."

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    echo "HANA is still running (timeout reached)"
    echo "The following services did not stop: ${running_services[*]}"
    return 1
}

check_hana_started() {
    local processes=("hdbnameserver" "hdbcompileserver" "hdbpreprocessor" "hdbindexserver" "hdbxsengine" "hdbwebdispatcher")
    local timeout=3600       # Total max wait time in seconds
    local check_interval=10 # Check every X seconds
    local elapsed=0
    local missing_services=()

    while [[ $elapsed -lt $timeout ]]; do
        missing_services=()  # Reset list on each check

        for process in "${processes[@]}"; do
            if ! pgrep -u ndbadm -f "$process" > /dev/null; then
                missing_services+=("$process")
            fi
        done

        if [[ ${#missing_services[@]} -eq 0 ]]; then
            echo "HANA is running (all services up)"
            return 0
        fi

        if [[ $elapsed -eq 0 ]]; then
            echo "Waiting for HANA services to start (timeout: ${timeout}s)..."
        fi
        echo "Waiting for services: ${missing_services[*]} ..."

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    echo "HANA is not running (timeout reached)"
    echo "The following services did not start: ${missing_services[*]}"
    return 1
}

stop_hana() {
    echo "Stopping HANA database services..."
    timeout 3 su - ndbadm -c "HDB stop" > "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
    if check_hana_stopped; then
        echo "HANA Database has been stopped successfully."
    else
        echo "HANA Database failed to stop within timeout. Exiting..."
        start_sap sapb1servertools.service
        stop_sap sapb1servertools-authentication.service
        start_sap sapb1servertools-authentication.service
        exit 1
    fi
}

start_hana() {
    echo "Starting HANA database services..."
    timeout 3600 su - ndbadm -c "HDB start" > "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
    if check_hana_started; then
        echo "HANA Database has been started successfully."
        su - ndbadm -c "HDB info" >> "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
    else
        echo "HANA Database failed to start within timeout. Exiting..."
        su - ndbadm -c "HDB info" >> "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
        exit 1
    fi
}

# Step 1: Stop SAP Business One Server Tools service
stop_sap sapb1servertools.service

# Step 2: Stop HANA Database
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
