#!/bin/sh
set -e

# Makes sure data is available.
chown -R artemis.artemis /var/lib/artemis
su - artemis

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=$BROKER_HOME/etc
export BROKER_HOME CONFIG_PATH

# Max memory and global size and queue size.
if [ -z "${MAX_MEMORY}" ]
then
	MAX_MEMORY=$(cat "/sys/fs/cgroup/memory/memory.limit_in_bytes" || echo 0)
	if ! [ ${MAX_MEMORY} -ne 0 ]
	then
		MAX_MEMORY=$((1024 * 1024 * 1024))
	fi
fi

QUEUE_MAX_SIZE=$(echo $((MAX_MEMORY / MAX_QUEUE_SIZE_RATIO)))
GLOBAL_MAX_SIZE=$(echo $((MAX_MEMORY / MAX_GLOBAL_SIZE_RATIO)))

export QUEUE_MAX_SIZE
export GLOBAL_MAX_SIZE

echo MAX_MEMORY=${MAX_MEMORY}
echo QUEUE_MAX_SIZE=${QUEUE_MAX_SIZE}
echo GLOBAL_MAX_SIZE=${GLOBAL_MAX_SIZE}

ENV_VARIABLES=$(awk 'BEGIN{for(v in ENVIRON) print "$"v}')
envsubst "$ENV_VARIABLES" <"${CONFIG_PATH}/broker.xml" | sponge "${CONFIG_PATH}/broker.xml"
cat "${CONFIG_PATH}/broker.xml"

# Update users and roles with if username and password is passed as argument
if [ "${ARTEMIS_USERNAME}" ] && [ "${ARTEMIS_PASSWORD}" ]; then
	echo "${ARTEMIS_USERNAME} = ${ARTEMIS_PASSWORD}" > ${CONFIG_PATH}/artemis-users.properties
	echo "technology-messaging-service-admin = ${ARTEMIS_USERNAME}" > ${CONFIG_PATH}/artemis-roles.properties
	cat ${CONFIG_PATH}/artemis-users.properties
fi

exec "$@"
