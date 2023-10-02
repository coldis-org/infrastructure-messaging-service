#!/bin/sh
set -e

# Makes sure data is available.
chown -R artemis.artemis /var/lib/artemis
su - artemis

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=$BROKER_HOME/etc
export BROKER_HOME CONFIG_PATH

# Max CPU, threads and connections.
if [ -z "${MAX_CPU}" ]
then
	MAX_CPU=$(cat "/sys/fs/cgroup/cpu/cpu.cfs_quota_us" || echo 0)
	if ! [ ${MAX_CPU} -ne 0 ]
	then
		MAX_CPU=100000
	fi
fi
THREAD_POOL=$(echo $((MAX_CPU * THREAD_POOL_RATIO / 100000)))
SCHEDULED_THREAD_POOL=$(echo $((MAX_CPU * SCHEDULED_THREAD_POOL_RATIO / 100000)))
if [ -z "${CONN_REMOTING_THREADS}" ]
then
	CONN_REMOTING_THREADS=$(echo $((MAX_CPU * CONN_REMOTING_THREADS_RATIO / 100000)))
fi
if [ -z "${CONN_CONNECTIONS_ALLOWED}" ]
then
	CONN_CONNECTIONS_ALLOWED=$(echo $((MAX_CPU * CONN_CONNECTIONS_ALLOWED_RATIO / 100000)))
fi
export THREAD_POOL SCHEDULED_THREAD_POOL CONN_REMOTING_THREADS CONN_CONNECTIONS_ALLOWED

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
export QUEUE_MAX_SIZE GLOBAL_MAX_SIZE

LAST_VALUE_QUEUE=false
if [ ! -z "${LAST_VALUE_KEY}" ]
then
	LAST_VALUE_QUEUE=true
fi
export LAST_VALUE_QUEUE

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
