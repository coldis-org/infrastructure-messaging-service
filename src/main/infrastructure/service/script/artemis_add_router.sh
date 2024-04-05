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
ROUTER_CONFIG_TAG="<xi:include href=\"${ARTEMIS_DIR}/extension/${ROUTER_NAME}.xml\" />"
ROUTERS_END_TAG="</connection-routers>"
if ! (cat ${EXTENSION_CONFIG_FILE} | grep "${ROUTER_CONFIG_TAG}")
then
    sed -i "s#^${ROUTERS_END_TAG}\$#${ROUTER_CONFIG_TAG}#" ${EXTENSION_CONFIG_FILE}
    echo "${ROUTERS_END_TAG}" >> ${EXTENSION_CONFIG_FILE}
fi

# Reads the input file line by line.
mkdir -p $(dirname ${VHOST})
rm -f ${VHOST}.old ${VHOST}.tmp
while read VHOST_LINE
do
	echo "${VHOST_LINE}" >> ${VHOST}.tmp
done
${DEBUG} && cat ${VHOST}.tmp

# Updates the file only if it has changed.
touch ${VHOST}
nginx_variables --files ${VHOST}.tmp
if !(diff -s ${VHOST} ${VHOST}.tmp)
then
	# Changes the configuration.
	mv ${VHOST} ${VHOST}.old
	mv ${VHOST}.tmp ${VHOST}
	# If the config cannot be reloaded.
	${DEBUG} && echo "Reloading config"
	nginx_variables
	nginx_check_config
	rm -f ${VHOST}.old
else 
	echo "Config file '${VHOST}' has not changed. Skipping."
fi
