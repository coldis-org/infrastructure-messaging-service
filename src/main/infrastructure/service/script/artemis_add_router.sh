#!/bin/sh
set -e

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
EXTENSION_CONFIG_FILE=${EXTENSION_CONFIG_PATH}/routers.xml
DEBUG=false

# For each argument.
while :; do
    case ${1} in
        
        # Debug argument.
        --debug)
            DEBUG=true
            DEBUG_OPT="--debug"
            ;;
            
        # Router name.
        -n|--router-name)
            ROUTER_NAME=${2}
            shift
            ;;
            
        # Other option.
        ?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;

        # No more options.
        *)
            break

    esac 
    shift
done

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'artemis_add_connector.sh'"
${DEBUG} && echo "ROUTER_NAME=${ROUTER_NAME}"
${DEBUG} && echo "ROUTER_URL=${ROUTER_URL}"

# Makes sure file exists.
ls ${EXTENSION_CONFIG_FILE} || touch ${EXTENSION_CONFIG_FILE} 

# Adds or updates the connector.
ROUTER_FILE_NAME="${ROUTER_NAME}.xml"
ROUTER_CONFIG_TAG="<xi:include href=\"${ARTEMIS_DIR}/extension/${ROUTER_FILE_NAME}\" />"
ROUTERS_END_TAG="</connection-routers>"
if ! (cat ${EXTENSION_CONFIG_FILE} | grep "${ROUTER_CONFIG_TAG}")
then
    sed -i "s#^${ROUTERS_END_TAG}\$#${ROUTER_CONFIG_TAG}#" ${EXTENSION_CONFIG_FILE}
    echo "${ROUTERS_END_TAG}" >> ${EXTENSION_CONFIG_FILE}
fi

# Reads the input file line by line.
rm -f ${ROUTER_FILE_NAME}.old ${ROUTER_FILE_NAME}.tmp
while read ROUTER_FILE_LINE
do
	echo "${ROUTER_FILE_LINE}" >> ${ROUTER_FILE_NAME}.tmp
done
${DEBUG} && cat ${ROUTER_FILE_NAME}.tmp

# Changes the configuration.
touch ${ROUTER_FILE_NAME}
mv ${ROUTER_FILE_NAME} ${ROUTER_FILE_NAME}.old
mv ${ROUTER_FILE_NAME}.tmp ${ROUTER_FILE_NAME}

# TODO Fix when broken.