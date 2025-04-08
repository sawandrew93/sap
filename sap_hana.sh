#!/bin/bash

LOG_DIR=/var/log/SAPBusinessOne
mkdir -p "$LOG_DIR"

start_sap() {
    local retries=18
    local count=0
    echo "Starting $1"
    service $1 start > $LOG_DIR/$HOSTNAME.$1.log 2>&1
    while true; do
        if service $1 status | grep -q "Running with PID"; then
            echo "$1 has been started successfully."
            break
        fi
        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            echo "Failed to start $1 after retries. Exiting..."
            return 1
        fi
        echo "$1 has not started yet. Retrying..."
        service $1 start > $LOG_DIR/$HOSTNAME.$1.log 2>&1
        sleep 10
    done
}

stop_sap() {
    local retries=18
    local count=0
    echo "Stopping $1"
    service $1 stop > $LOG_DIR/$HOSTNAME.$1.log 2>&1
    while true; do
        if service $1 status | grep -q "but no PID file exists"; then
            echo "$1 has been stopped successfully."
            break
        fi
        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            echo "Failed to stop $1 after retries. Exiting..."
            return 1
        fi
        echo "$1 has not stopped yet. Retrying..."
        service $1 stop > $LOG_DIR/$HOSTNAME.$1.log 2>&1
        sleep 10
    done
}

check_hana_stopped() {
    local processes=("hdbnameserver" "hdbcompileserver" "hdbpreprocessor" "hdbindexserver" "hdbxsengine" "hdbwebdispatcher")
    local timeout=1800
    local check_interval=10
    local elapsed=0
    local running_services=()

    while [[ $elapsed -lt $timeout ]]; do
        running_services=()
        for process in "${processes[@]}"; do
            if pgrep -u ndbadm -f "$process" > /dev/null; then
                running_services+=("$process")
            fi
        done
        if [[ ${#running_services[@]} -eq 0 ]]; then
            echo "HANA is stopped (all services are stopped)"
            return 0
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
    local timeout=3600
    local check_interval=10
    local elapsed=0
    local missing_services=()

    while [[ $elapsed -lt $timeout ]]; do
        missing_services=()
        for process in "${processes[@]}"; do
            if ! pgrep -u ndbadm -f "$process" > /dev/null; then
                missing_services+=("$process")
            fi
        done
        if [[ ${#missing_services[@]} -eq 0 ]]; then
            echo "HANA is running (all services up)"
            return 0
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
    su - ndbadm -c "HDB stop" > "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
    check_hana_stopped || return 1
}

start_hana() {
    echo "Starting HANA database services..."
    su - ndbadm -c "HDB start" > "$LOG_DIR/$HOSTNAME.hanaservice.log" 2>&1
    check_hana_started || return 1
}

case "$1" in
    start)
        stop_sap sapb1servertools
        stop_hana || exit 1
        start_hana || exit 1
        stop_sap sapb1servertools
        start_sap sapb1servertools || exit 1
        ;;
    stop)
        stop_sap sapb1servertools
        stop_hana || exit 1
        ;;
    restart)
        $0 stop && $0 start
        ;;
    status)
        echo "Status:"
        service sapb1servertools status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
