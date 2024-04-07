#!/bin/sh
set -e

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
EXTENSION_CONFIG_FILE=${EXTENSION_CONFIG_PATH}/artemis-users.properties
DEBUG=false
USER_NAME=
USER_PASSWORD=

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
${DEBUG} && echo "Running 'artemis_add_user.sh'"
${DEBUG} && echo "USER_NAME=${USER_NAME}"
${DEBUG} && echo "USER_PASSWORD=${USER_PASSWORD}"

# Makes sure file exists.
ls ${EXTENSION_CONFIG_FILE} || touch ${EXTENSION_CONFIG_FILE} 

# Adds or updates the users.
if [ -n "${USER_NAME}" ] && [ -n "${USER_PASSWORD}" ]
then
    CONFIG_START="${USER_NAME} = "
    CONFIG="${CONFIG_START} ${USER_PASSWORD}"
    if (cat ${EXTENSION_CONFIG_FILE} | grep "${CONFIG_START}")
    then
        sed -i "s#^${CONFIG_START}.*\$#${CONFIG}#" ${EXTENSION_CONFIG_FILE}
    else 
        echo "${CONFIG}" >> ${EXTENSION_CONFIG_FILE}
    fi
fi

# Reloads users.
echo "${ARTEMIS_USERNAME:-artemis} = ${ARTEMIS_PASSWORD:-artemis}" > ${CONFIG_PATH}/artemis-users.properties
echo "technology-messaging-service-admin = ${ARTEMIS_USERNAME:-artemis}" > ${CONFIG_PATH}/artemis-roles.properties
cat ${EXTENSION_CONFIG_FILE} >> ${CONFIG_PATH}/artemis-users.properties

cat ${CONFIG_PATH}/artemis-users.properties

