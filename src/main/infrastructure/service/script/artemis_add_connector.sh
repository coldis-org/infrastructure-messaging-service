#!/bin/sh
set -e

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
EXTENSION_CONFIG_FILE=${EXTENSION_CONFIG_PATH}/connectors.xml
DEBUG=false
USER_NAME=
USER_PASSWORD=
CONNECTOR_NAME=
CONNECTOR_URL=

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
if [ -n "${USER_NAME}" ] && [ -n "${USER_PASSWORD}" ]
then
    artemis_add_user -u "${USER_NAME}" -p "${USER_PASSWORD}"
fi

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'artemis_add_connector.sh'"
${DEBUG} && echo "CONNECTOR_NAME=${CONNECTOR_NAME}"
${DEBUG} && echo "CONNECTOR_URL=${CONNECTOR_URL}"

# Makes sure file exists.
ls ${EXTENSION_CONFIG_FILE} || cp ${CONFIG_PATH}/connectors.xml ${EXTENSION_CONFIG_FILE} 

# Adds or updates the connector.
if [ -n "${CONNECTOR_NAME}" ] && [ -n "${CONNECTOR_URL}" ]
then
    
    CONNECTOR_CONFIG_TAG_START="<connector name=\"${CONNECTOR_NAME}\">"
    CONNECTOR_CONFIG_TAG="${CONNECTOR_CONFIG_TAG_START}${CONNECTOR_URL}</connector>"
    CONNECTORS_END_TAG="</connectors>"
    if (cat ${EXTENSION_CONFIG_FILE} | grep "${CONNECTOR_CONFIG_TAG_START}")
    then
        sed -i "s#${CONNECTOR_CONFIG_TAG_START}.*\$#${CONNECTOR_CONFIG_TAG}#" ${EXTENSION_CONFIG_FILE}
    else 
        sed -i "s#^${CONNECTORS_END_TAG}\$#${CONNECTOR_CONFIG_TAG}#" ${EXTENSION_CONFIG_FILE}
        echo "${CONNECTORS_END_TAG}" >> ${EXTENSION_CONFIG_FILE}
    fi

fi