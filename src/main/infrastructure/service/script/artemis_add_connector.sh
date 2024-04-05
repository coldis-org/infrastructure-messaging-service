#!/bin/sh
set -e

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
EXTENSION_CONFIG_FILE=${EXTENSION_CONFIG_PATH}/connectors.xml
DEBUG=false

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Connector name.
		-n|--connector-name)
			CONNECTOR_NAME=${2}
			shift
			;;

        # Connector url.
        -u|--connector-url)
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

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'artemis_add_connector.sh'"
${DEBUG} && echo "CONNECTOR_NAME=${CONNECTOR_NAME}"
${DEBUG} && echo "CONNECTOR_URL=${CONNECTOR_URL}"

# Makes sure file exists.
ls ${EXTENSION_CONFIG_FILE} || touch ${EXTENSION_CONFIG_FILE} 

# Adds or updates the connector.
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
