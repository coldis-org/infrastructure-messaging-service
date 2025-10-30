#!/bin/sh
set -e

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
EXTENSION_CONFIG_FILE=${EXTENSION_CONFIG_PATH}/routers.xml
DEBUG=false
USER_NAME=
USER_PASSWORD=
CONNECTOR_NAME=
CONNECTOR_URL=
ROUTER_NAME=

# For each argument.
while :; do
    case ${1} in
        
        # Debug argument.
        --debug)
            DEBUG=true
            DEBUG_OPT="--debug"
            ;;
            
        # User name.
        -u|--user-name)
            USER_NAME=${2}
            shift
            ;;

        # User password.
        -p|--user-password)
            USER_PASSWORD=${2}
            shift
            ;;
            
        # Connector name.
        -c|--connector-name)
            CONNECTOR_NAME=${2}
            shift
            ;;

        # Connector url.
        -a|--connector-url)
            CONNECTOR_URL=${2}
            shift
            ;;
            
        # Router name.
        -r|--router-name)
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

# Adds connectors if available.
if [ -n "${CONNECTOR_NAME}" ] && [ -n "${CONNECTOR_URL}" ]
then
    artemis_add_connector -u "${USER_NAME}" -p "${USER_PASSWORD}" -c "${CONNECTOR_NAME}" -a "${CONNECTOR_URL}"
fi

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'artemis_add_router.sh'"
${DEBUG} && echo "ROUTER_NAME=${ROUTER_NAME}"

# Makes sure file exists.
cd ${EXTENSION_CONFIG_PATH}
ls ${EXTENSION_CONFIG_FILE} || cp ${CONFIG_PATH}/routers.xml ${EXTENSION_CONFIG_FILE} 

# Adds or updates the connector.
if [ -n "${ROUTER_NAME}" ]
then
    ROUTER_FILE_NAME="${ROUTER_NAME}.xml"
    ROUTER_CONFIG_TAG="<xi:include href=\"${ARTEMIS_DIR}/extension/${ROUTER_FILE_NAME}\" />"
    ROUTERS_END_TAG="</connection-routers>"

    cat > "$ROUTER_FILE_NAME" <<EOF
<connection-router xmlns="urn:activemq:core" name="${ROUTER_NAME}-router">
    <key-type>USER_NAME</key-type>
    <key-filter>${ROUTER_NAME}</key-filter>
    <pool>
        <username>${USER_NAME}</username>
        <password>${USER_PASSWORD}</password>
        <local-target-enabled>false</local-target-enabled>
        <static-connectors>
            <connector-ref>${ROUTER_NAME}</connector-ref>
        </static-connectors>
    </pool>
</connection-router>
EOF


    if ! (cat ${EXTENSION_CONFIG_FILE} | grep "${ROUTER_CONFIG_TAG}")
    then
        sed -i "s#^${ROUTERS_END_TAG}\$#${ROUTER_CONFIG_TAG}#" ${EXTENSION_CONFIG_FILE}
        echo "${ROUTERS_END_TAG}" >> ${EXTENSION_CONFIG_FILE}
    fi
    
fi