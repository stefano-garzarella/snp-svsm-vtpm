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

pushd "${SCRIPT_PATH}/kbs/reference-kbs"
if [ "${FLUSH_DB}" == "1" ]; then
    rm -f db/diesel/db.sqlite
fi
cargo run &
popd

# Wait till the server is listening on port 8000
while ! netstat -tna | grep 'LISTEN\>' | grep -q ':8000\>'; do
  sleep 1
done

set -x

pushd "${SCRIPT_PATH}/kbs/raclients"
RUST_LOG=info cargo run --example=proxy-reference-kbs -- --unix "${PROXY_SOCK}" \
    --url "${KBS_URL}" --workload-id svsm -f
popd

kill "$(jobs -p)"
