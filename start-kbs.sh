#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

FLUSH_DB=0

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Start Key Broker Server and SVSM proxy for QEMU"
    echo -e ""
    echo -e " -f, --flush-db      flush the entire KBS database"
    echo -e " -h, --help          print this help"
}

while [ "$1" != "" ]; do
    case $1 in
        -f | --flush-db )
            FLUSH_DB=1
            ;;
        -h | --help )
            usage
            exit
            ;;
        * )
            echo -e "\nParameter not found: $1\n"
            usage
            exit 1
    esac
    shift
done

if [ "${FLUSH_DB}" == "1" ]; then
    rm $KBS_MEASUREMENT $KBS_SECRET
fi

monitor_kbs() {
    pushd "${SCRIPT_PATH}/kbs/kbs-test"
    while true; do
        echo "KBS reloading"
        cargo run -- -m "$(cat $KBS_MEASUREMENT 2>/dev/null)" \
            -s "$(cat $KBS_SECRET 2>/dev/null)" &
        echo $! > "$KBS_PID"
        wait $!
        sleep 1
    done
    popd
}

cleanup() {
    if [ -n "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null
    fi

    if [ -f "$KBS_PID" ]; then
        PID=$(cat "$KBS_PID")
        rm -f "$KBS_PID"
        kill "$PID" 2>/dev/null
    fi

    exit 0
}

trap cleanup SIGINT

monitor_kbs &
MONITOR_PID=$!

set -x

pushd "${SCRIPT_PATH}/svsm"
bin/aproxy --protocol kbs-test --unix "${PROXY_SOCK}" --url "${KBS_URL}" --force
popd
