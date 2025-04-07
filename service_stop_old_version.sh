#!/bin/bash
source config.sh
LOG_DIR=/var/log/SAPBusinessOne
mkdir -p "$LOG_DIR"

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

check_hana_stopped() {
    local processes=("hdbnameserver" "hdbcompileserver" "hdbpreprocessor" "hdbindexserver" "hdbxsengine" "hdbwebdispatcher")
    local timeout=1800      # Total max wait time in seconds
    local check_interval=10 # Check every X seconds
    local elapsed=0
    local running_services=()

    while [[ $elapsed -lt $timeout ]]; do
        running_services=()  # Reset list on each check

        # Check each process and record running ones
        for process in "${processes[@]}"; do
            if pgrep -u ndbadm -f "$process" > /dev/null; then
                running_services+=("$process")
            fi
        done

        # If no running services, HANA is stopped
        if [[ ${#running_services[@]} -eq 0 ]]; then
            echo "HANA is stopped (all services are stopped)"
            return 0
        fi

        # If some services are running, report and wait
        if [[ $elapsed -eq 0 ]]; then
            echo "Waiting for HANA services to stop (timeout: ${timeout}s)..."
        fi
        echo "Waiting for services: ${running_services[*]} to stop ..."

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    # Timeout reached, still running services
    echo "HANA is still running (timeout reached)"
    echo "The following services did not stop: ${running_services[*]}"
    return 1
}

stop_hana() {
    echo "Stopping HANA database services..."
    #timeout has been reduced as we want to proceed to next step and check which services are still running
    timeout 3 su - ndbadm -c "HDB stop" > "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
    if check_hana_stopped; then
        echo "HANA Database has been stopped successfully."
    else
        echo "HANA Database failed to stop within timeout. Exiting..."
        exit 1
    fi
}

# Step 1: Stop SAP Business One Server Tools service
stop_sap sapb1servertools

# Step 2: Stop HANA Database
stop_hana
