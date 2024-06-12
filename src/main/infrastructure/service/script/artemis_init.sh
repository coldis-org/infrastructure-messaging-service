#!/bin/sh
set -e

# Makes sure data is available.
chown -R artemis.artemis /var/lib/artemis
su - artemis

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
export BROKER_HOME CONFIG_PATH EXTENSION_CONFIG_PATH
INT_MAX=2147483647

# Memory limit.
memory_limit() {
  awk -F: '/^[0-9]+:memory:/ {
    filepath="/sys/fs/cgroup/memory"$3"/memory.limit_in_bytes";
    getline line < filepath;
    print line
  }' /proc/self/cgroup
}

# Configures users, connectors and routers.
artemis_add_user
artemis_add_connector
artemis_add_router

# Threads.
if [ -z "${MAX_CPU}" ]
then
	MAX_CPU=$(cat "/sys/fs/cgroup/cpu/cpu.cfs_quota_us" || echo "error")
fi
if [ -z "${MAX_CPU}" ] || [ "${MAX_CPU}" = "error" ] || [ ${MAX_CPU} -le 0 ]
then
	MAX_CPU=100000
fi
THREAD_POOL=$(echo $((MAX_CPU * THREAD_POOL_PROC_PERC / 100 / 100000)))
SCHEDULED_THREAD_POOL=$(echo $((MAX_CPU * SCHEDULED_THREAD_POOL_PROC_PERC / 100 / 100000)))
if [ -z "${CONN_REMOTING_THREADS}" ]
then
	CONN_REMOTING_THREADS=$(echo $((MAX_CPU * CONN_REMOTING_THREADS_PROC_PERC / 100 / 100000)))
fi
export THREAD_POOL SCHEDULED_THREAD_POOL CONN_REMOTING_THREADS

# Queue sizes.
if [ -z "${MAX_MEMORY}" ]
then
	MAX_MEMORY=$(memory_limit || echo "error")
fi
if [ -z "${MAX_MEMORY}" ] || [ "${MAX_MEMORY}" = "error" ] || [ ${MAX_MEMORY} -le 0 ]
then
	MAX_MEMORY=$((1024 * 1024 * 1024))
fi
if [ -z "${CONN_CONNECTIONS_ALLOWED}" ]
then
	CONN_CONNECTIONS_ALLOWED=$( echo $(( MAX_MEMORY * CONN_CONNECTIONS_ALLOWED_MEM_PERC / 100 / 1024 / 1024 )))
fi
if [ -z "${CONN_CONNECTIONS_ALLOWED}" ] || [ "${CONN_CONNECTIONS_ALLOWED}" = "error" ] || [ ${CONN_CONNECTIONS_ALLOWED} -le 0 ]
then
	CONN_CONNECTIONS_ALLOWED=8192
fi
GLOBAL_MAX_SIZE=$( echo $(( MAX_MEMORY * MAX_GLOBAL_SIZE_MEM_PERC / 100 )) )
QUEUE_MAX_SIZE=$( echo $(( MAX_MEMORY * MAX_QUEUE_SIZE_MEM_PERC / 100 )) )
QUEUE_MAX_SIZE=$(( QUEUE_MAX_SIZE > INT_MAX ? INT_MAX : QUEUE_MAX_SIZE ))
QUEUE_PRETECH_SIZE=$( echo $(( MAX_MEMORY * PREFECTH_QUEUE_SIZE_MEM_PERC / 100 )))
QUEUE_PRETECH_SIZE=$(( QUEUE_PRETECH_SIZE > INT_MAX ? INT_MAX : QUEUE_PRETECH_SIZE ))
export CONN_CONNECTIONS_ALLOWED GLOBAL_MAX_SIZE QUEUE_MAX_SIZE QUEUE_PRETECH_SIZE

# Network configuration.
CONN_LOW_BUFFER_WATERMARK=$(( CONN_LOW_BUFFER_WATERMARK_PERC * CONN_TCP_BUFFER_SIZE / 100 ))
CONN_HIGH_BUFFER_WATERMARK=$(( CONN_HIGH_BUFFER_WATERMARK_PERC * CONN_TCP_BUFFER_SIZE / 100 ))
export CONN_LOW_BUFFER_WATERMARK CONN_HIGH_BUFFER_WATERMARK

# Disk configutation.
DISK_SIZE=$(df --output=size --total ${BROKER_HOME} | tail -1)
DISK_SIZE_MB=$(( DISK_SIZE / 1024 ))
JOURNAL_MAX_FILES=$(( DISK_SIZE_MB / JOURNAL_FILE_SIZE ))
JOURNAL_MIN_FILES=$(( JOURNAL_MAX_FILES * JOURNAL_MIN_FILES_PERC / 100 ))
JOURNAL_MIN_FILES=$(( JOURNAL_MIN_FILES > JOURNAL_MIN_FILES_CAP ? JOURNAL_MIN_FILES_CAP : JOURNAL_MIN_FILES ))
JOURNAL_POOL_FILES=$(( JOURNAL_MAX_FILES * JOURNAL_POOL_FILES_PERC / 100 ))
JOURNAL_COMPACT_MIN_FILES=$(( JOURNAL_MAX_FILES * JOURNAL_COMPACT_MIN_FILES_PERC / 100 ))
JOURNAL_COMPACT_MIN_FILES=$(( JOURNAL_COMPACT_MIN_FILES > JOURNAL_COMPACT_MIN_FILES_CAP ? JOURNAL_COMPACT_MIN_FILES_CAP : JOURNAL_COMPACT_MIN_FILES ))
JOURNAL_BUFFER_SIZE=$(( MAX_MEMORY * JOURNAL_BUFFER_SIZE_PERC / 100 ))
export JOURNAL_MIN_FILES JOURNAL_POOL_FILES JOURNAL_COMPACT_MIN_FILES

# Last value.
LAST_VALUE_QUEUE=false
if [ ! -z "${LAST_VALUE_KEY}" ]
then
	LAST_VALUE_QUEUE=true
fi
export LAST_VALUE_QUEUE

ENV_VARIABLES=$(awk 'BEGIN{for(v in ENVIRON) print "$"v}')
envsubst "$ENV_VARIABLES" <"${CONFIG_PATH}/broker.xml" | sponge "${CONFIG_PATH}/broker.xml"
cat "${CONFIG_PATH}/broker.xml"


# Makes sure extension files exist.
ls ${EXTENSION_CONFIG_PATH}/connectors.xml || cp ${CONFIG_PATH}/connectors.xml ${EXTENSION_CONFIG_FILE}/connectors.xml
ls ${EXTENSION_CONFIG_PATH}/routers.xml || cp ${CONFIG_PATH}/routers.xml ${EXTENSION_CONFIG_FILE}/routers.xml

exec "$@"
