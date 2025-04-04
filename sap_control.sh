#!/bin/bash
set -eu

# global variables - provided by service ---------------------------------------
# JAVA_HOME
# JRE_HOME
# JAVA_MEMORY_HEAP_MAX
#
# HDBSQL
#
# PATH
# LD_LIBRARY_PATH
#
# CATALINA_BASE
# CATALINA_HOME
# CATALINA_TMPDIR
# CATALINA_OPTS
# CATALINA_PID
#
# REVERSEPROXY_PID
# REVERSEPROXY_SCRIPT
# REVERSEPROXY_LOG
#
# SOLUTION_TYPE

# global variables -------------------------------------------------------------
JAVA_OPTIONS=(
    '-Duser.country=US'
    '-Duser.language=en'
    '-Dfile.encoding=UTF-8'
    '-Djava.awt.headless=true'
    '-Dsap.b1.servertools.log.path=/var/log/SAPBusinessOne/ServerTools'
    # '-Dcom.sun.management.jmxremote'
    # '-Dcom.sun.management.jmxremote.port=9009'
    # '-Dcom.sun.management.jmxremote.ssl=false'
    # '-Dcom.sun.management.jmxremote.authenticate=false'
    '-server'
    '-Xms1024M'
    "-Xmx${JAVA_MEMORY_HEAP_MAX:-10240M}"
    '-XX:MetaspaceSize=128m'
    '-XX:MaxMetaspaceSize=512m'
    # '-Xdebug'
    # '-Xrunjdwp:server=y,transport=dt_socket,address=4000,suspend=n'
)

export JAVA_OPTS="${JAVA_OPTIONS[*]}"
export JAVA_ENDORSED_DIRS="${CATALINA_HOME:?}/endorsed"

#-------------------------------------------------------------------------------
function __read_servertools_pid() {
    pgrep --list-full 'java' |
        grep --fixed-strings --regexp "Dcatalina.base=${CATALINA_BASE:?}" |
        awk 'NR==1 { print $1 }'
}

function __test_port_occupied() {
    ss --numeric --tcp --listening "( sport = :${1:?} )" |
        grep --quiet --regexp ":${1:?}"
}

function __find_free_port() {
    local port

    while true; do
        port=$((8000 + ${RANDOM:0:4}))

        __test_port_occupied "${port}" && continue

        echo "${port}"
        break
    done

    return 0
}

function servertools::test_running() {
    [ -f "${CATALINA_PID:?}" ] || return 1

    local kpid
    read -r kpid < "${CATALINA_PID}"

    if [ -d "/proc/${kpid}" ]; then
        echo >&2 "ServerTools process is already running"
        return 0
    else
        echo >&2 "Lock file found but process ${kpid} does not exist"
        return 1
    fi
}

function servertools::test_hana_connection() {
    [ -f "${CATALINA_HOME:?}/conf/Catalina/localhost/sld.xml" ] || return 0

    local hana_url hana_host hana_instance hana_tenant_db
    local msg

    hana_url=$(
        xmlstarlet 'select' --template \
            --value-of "/Context/Resource[@name = 'sld']/@url" \
            "${CATALINA_HOME:?}/conf/Catalina/localhost/sld.xml"
    )

    [[ $hana_url =~ jdbc:sap://([^:]+):([0-9]+) ]] || return 0
    hana_host="${BASH_REMATCH[1]}"
    hana_instance="${BASH_REMATCH[2]:1:2}"

    [[ $hana_url =~ jdbc:sap://.*databaseName=([A-Za-z_0-9]+) ]] || return 0
    hana_tenant_db="${BASH_REMATCH[1]}"

    echo >&2 "Testing connection to ${hana_host}/${hana_instance}/${hana_tenant_db}"

    for ((timer = 0; ; timer += 10)); do
        msg=$(
            "${HDBSQL}" -x -a -j \
                -n "${hana_host}" \
                -i "${hana_instance}" \
                -d "${hana_tenant_db}" \
                -u FAKEUSER \
                -p fakepassword \
                'select 1 from DUMMY' 2>&1
        )

        if ((timer >= 300)); then
            echo >&2 "HANA Server (${hana_host}/${hana_instance}/${hana_tenant_db}) isn't started even after 5 mins."
            return 1
        fi

        if (echo "${msg}" | grep --quiet 'Connection.*refused'); then
            echo >&2 "Waiting for HANA Server (${hana_host}/${hana_instance}/${hana_tenant_db}) to start..."
            sleep 10
            continue
        fi

        break
    done

    return 0
}

function servertools::configuration::assign_random_port() {
    local -r random_port=$(__find_free_port)

    xmlstarlet edit --inplace \
            --update "/Server/@port" \
            --value "${random_port}" \
            "${CATALINA_HOME:?}/conf/server.xml"
}

function servertools::log_folders::create() {
    mkdir --parents "/var/log/SAPBusinessOne/ServerTools/SLD"
    mkdir --parents "/var/log/SAPBusinessOne/ServerTools/License"
    mkdir --parents "/var/log/SAPBusinessOne/ServerTools/Mailer"
    mkdir --parents "/var/log/SAPBusinessOne/ServerTools/BackupService"
}

function __tomcat_start() {
    /bin/bash -c "'${CATALINA_BASE:?}/bin/catalina.sh' start" \
        >> "${CATALINA_HOME:?}/logs/catalina.out" 2>&1
}

function __tomcat_stop() {
    /bin/bash -c "'${CATALINA_BASE:?}/bin/catalina.sh' stop 5 -force" 2>&1 |
        tee --append "${CATALINA_HOME:?}/logs/catalina.out"
}


function servertools::start() {
    if __tomcat_start; then
        touch "${CATALINA_PID:?}"
        return 0
    else
        rm --force "${CATALINA_PID:?}"
        return 7
    fi
}

function servertools::stop() {
    __tomcat_stop
    rm --force "${CATALINA_PID:?}"
    return 0
}

function servertools::kill() {
    local kpid

    kpid=$(__read_servertools_pid)
    [ -z "${kpid}" ] && return 0

    echo >&2 "Killing process ${kpid}"
    kill -9 "${kpid}" || true

    return 0
}

function servertools::reverseproxy::start() {
    [ -f "${REVERSEPROXY_SCRIPT:?}" ] || return 0

    echo >&2 "start up mdx reverse proxy."
    /bin/sh -c "nohup '${REVERSEPROXY_SCRIPT:?}' '${REVERSEPROXY_PID:?}' >> '${REVERSEPROXY_LOG:?}' 2>&1 &"

    return 0
}

function servertools::reverseproxy::stop() {
    [ -f "${REVERSEPROXY_SCRIPT:?}" ] || return 0
    [ -f "${REVERSEPROXY_PID:?}" ] || return 0

    echo >&2 "kill mdx proxy process"

    local -r ppid=$(pgrep -f /AnalyticsPlatform/TcpReverseProxy/proxy.py)
    kill -9 "${ppid}" || true

    return 0
}


################################################################################
case "${1:?}" in
    start)
        servertools::test_running && exit 0
        servertools::test_hana_connection || exit 1

        servertools::log_folders::create
        servertools::configuration::assign_random_port

        servertools::start
        servertools::reverseproxy::start
        exit 0
        ;;
    stop)
        servertools::stop
        servertools::reverseproxy::stop
        servertools::kill
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
################################################################################
