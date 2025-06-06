#!/bin/sh
set -e

# Default execution.
EXEC="$@"

# Makes sure data is available.
chown -R artemis:artemis /var/lib/artemis
#su - artemis

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=${BROKER_HOME}/etc
EXTENSION_CONFIG_PATH=${CONFIG_PATH}/extension
export BROKER_HOME CONFIG_PATH EXTENSION_CONFIG_PATH
INT_MAX=2147483647

# OS limits.
DEBUG=true
EXPORT=true
. os_limits

# Configures users, connectors and routers.
artemis_add_user
artemis_add_connector
artemis_add_router

# Threads.
if [ -z "${MAX_CPU}" ]
then
	MAX_CPU="${AVAILABLE_CPUS}"
fi
THREAD_POOL=$(( THREAD_POOL_PROC_PERC < 0 ? -1 : ( MAX_CPU * THREAD_POOL_PROC_PERC / 100 ) ))
THREAD_POOL=$(( THREAD_POOL < THREAD_POOL_MIN && THREAD_POOL > -1 ? THREAD_POOL_MIN : THREAD_POOL ))
SCHEDULED_THREAD_POOL=$(( SCHEDULED_THREAD_POOL_PROC_PERC < 0 ? -1 : ( MAX_CPU * SCHEDULED_THREAD_POOL_PROC_PERC / 100 ) ))
SCHEDULED_THREAD_POOL=$(( SCHEDULED_THREAD_POOL < SCHEDULED_THREAD_POOL_MIN && SCHEDULED_THREAD_POOL > -1 ? SCHEDULED_THREAD_POOL_MIN : SCHEDULED_THREAD_POOL ))
IO_THREAD_POOL=$(( IO_THREAD_POOL_PROC_PERC < 0 ? -1 : ( MAX_CPU * IO_THREAD_POOL_PROC_PERC / 100 ) ))
IO_THREAD_POOL=$(( IO_THREAD_POOL <IO_THREAD_POOL_MIN && IO_THREAD_POOL > -1 ? IO_THREAD_POOL_MIN : IO_THREAD_POOL ))
if [ -z "${CONN_REMOTING_THREADS}" ]
then
	CONN_REMOTING_THREADS=$(( MAX_CPU * CONN_REMOTING_THREADS_PROC_PERC / 100 ))
	CONN_REMOTING_THREADS=$(( CONN_REMOTING_THREADS < CONN_REMOTING_THREADS_MIN ? CONN_REMOTING_THREADS_MIN : CONN_REMOTING_THREADS ))
	
fi
export THREAD_POOL SCHEDULED_THREAD_POOL IO_THREAD_POOL CONN_REMOTING_THREADS 

# Queue sizes.
if [ -z "${MAX_MEMORY}" ]
then
	MAX_MEMORY="$(( ${AVAILABLE_MEMORY} * 1024 * 1024 ))"
fi
if [ -z "${CONN_CONNECTIONS_ALLOWED}" ]
then
	CONN_CONNECTIONS_ALLOWED=$(( MAX_MEMORY * CONN_CONNECTIONS_ALLOWED_MEM_PERC / 100 / 1024 / 1024 ))
fi
if [ -z "${CONN_CONNECTIONS_ALLOWED}" ] || [ "${CONN_CONNECTIONS_ALLOWED}" = "error" ] || [ ${CONN_CONNECTIONS_ALLOWED} -le 0 ]
then
	CONN_CONNECTIONS_ALLOWED=8192
fi
QUEUE_MAX_SIZE_FULL=$(( MAX_MEMORY * QUEUE_MAX_SIZE_FULL_MEM_PERC / 100 ))
QUEUE_MAX_SIZE_FULL=$(( QUEUE_MAX_SIZE_FULL > (QUEUE_MAX_SIZE_FULL_ABS * 1024 * 1024) ? (QUEUE_MAX_SIZE_FULL_ABS * 1024 * 1024) : QUEUE_MAX_SIZE_FULL ))
QUEUE_MAX_SIZE_FULL=$(( QUEUE_MAX_SIZE_FULL > INT_MAX ? INT_MAX : QUEUE_MAX_SIZE_FULL ))
QUEUE_MAX_PREFECTH_SIZE=$(( CONSUMER_WINDOW_SIZE * QUEUE_MAX_PREFECTH_WINDOW_SIZE_MULT ))
QUEUE_MAX_PREFECTH_SIZE=$(( QUEUE_MAX_PREFECTH_SIZE > INT_MAX ? INT_MAX : QUEUE_MAX_PREFECTH_SIZE ))
QUEUE_MAX_EXTRA_READ_SIZE=$(( CONSUMER_WINDOW_SIZE * QUEUE_MAX_EXTRA_READ_SIZE_WINDOW_SIZE_MULT ))
QUEUE_MAX_TOTAL_READ_SIZE=$(( QUEUE_MAX_PREFECTH_SIZE + QUEUE_MAX_EXTRA_READ_SIZE ))
QUEUE_MAX_TOTAL_READ_SIZE=$(( QUEUE_MAX_TOTAL_READ_SIZE > INT_MAX ? INT_MAX : QUEUE_MAX_TOTAL_READ_SIZE ))
QUEUE_MAX_TOTAL_READ_SIZE_COUNT=$(( QUEUE_MAX_PREFECTH_SIZE_COUNT + QUEUE_MAX_EXTRA_READ_SIZE_COUNT ))
QUEUE_MAX_SIZE=$(( CONSUMER_WINDOW_SIZE * MAX_QUEUE_SIZE_WINDOW_SIZE_MULT ))
QUEUE_MAX_SIZE=$(( QUEUE_MAX_SIZE > INT_MAX ? INT_MAX : QUEUE_MAX_SIZE ))
JOURNAL_FILE_SIZE=$(( MAX_MEMORY * MAX_RAM_PERC / 100 * JOURNAL_FILE_SIZE_PERC / 100 ))
JOURNAL_FILE_SIZE=$(( JOURNAL_FILE_SIZE > JOURNAL_FILE_MAX_SIZE ? JOURNAL_FILE_MAX_SIZE : JOURNAL_FILE_SIZE ))
PAGE_SIZE=$(( MAX_MEMORY * MAX_RAM_PERC / 100 * PAGE_SIZE_PERC / 100 ))
PAGE_SIZE=$(( PAGE_SIZE > PAGE_MAX_SIZE ? PAGE_MAX_SIZE : PAGE_SIZE ))

export CONN_CONNECTIONS_ALLOWED QUEUE_MAX_SIZE_FULL QUEUE_MAX_PREFECTH_SIZE QUEUE_MAX_TOTAL_READ_SIZE QUEUE_MAX_TOTAL_READ_SIZE_COUNT JOURNAL_FILE_SIZE PAGE_SIZE

# Network configuration.
if [ "${CONN_TCP_BUFFER_SIZE}" != "-1" ] && [ "${CONN_TCP_BUFFER_SIZE}" != "" ]
then
	if [ "${CONN_LOW_BUFFER_WATERMARK}" = "" ] && [ "${CONN_LOW_BUFFER_WATERMARK_PERC}" != "" ]
	then
		CONN_LOW_BUFFER_WATERMARK=$(( CONN_LOW_BUFFER_WATERMARK_PERC * CONN_TCP_BUFFER_SIZE / 100 ))
	fi
	if [ "${CONN_HIGH_BUFFER_WATERMARK}" = "" ] && [ "${CONN_HIGH_BUFFER_WATERMARK_PERC}" != "" ]
    then
        CONN_HIGH_BUFFER_WATERMARK=$(( CONN_HIGH_BUFFER_WATERMARK_PERC * CONN_TCP_BUFFER_SIZE / 100 ))
    fi
	export CONN_LOW_BUFFER_WATERMARK CONN_HIGH_BUFFER_WATERMARK
fi

# Disk configutation.
DISK_SIZE=$( df --output=size --total -B1 ${BROKER_HOME} | tail -1 )
DISK_SIZE_MB=$(( DISK_SIZE / 1024 ))
JOURNAL_MAX_FILES=$(( DISK_SIZE_MB / JOURNAL_FILE_SIZE ))
JOURNAL_MIN_FILES=$(( JOURNAL_MAX_FILES * JOURNAL_MIN_FILES_PERC / 100 ))
JOURNAL_MIN_FILES_CAP=$(( JOURNAL_MIN_FILES_DISK_CAP / JOURNAL_FILE_SIZE ))
JOURNAL_MIN_FILES=$(( JOURNAL_MIN_FILES > JOURNAL_MIN_FILES_CAP ? JOURNAL_MIN_FILES_CAP : JOURNAL_MIN_FILES ))
JOURNAL_MIN_FILES=$(( JOURNAL_MIN_FILES < 2 ? 2 : JOURNAL_MIN_FILES ))
JOURNAL_POOL_FILES=$(( JOURNAL_MAX_FILES * JOURNAL_POOL_FILES_PERC / 100 ))
JOURNAL_POOL_FILES_CAP=$(( JOURNAL_POOL_FILES_DISK_CAP / JOURNAL_FILE_SIZE ))
JOURNAL_POOL_FILES=$(( JOURNAL_POOL_FILES > JOURNAL_POOL_FILES_CAP ? JOURNAL_POOL_FILES_CAP : JOURNAL_POOL_FILES ))
JOURNAL_POOL_FILES=$(( JOURNAL_POOL_FILES < 2 ? 2 : JOURNAL_POOL_FILES ))
if [ ! -z "${JOURNAL_COMPACT_MIN_FILES_PERC}" ]
then
	JOURNAL_COMPACT_MIN_FILES=$(( JOURNAL_MAX_FILES * JOURNAL_COMPACT_MIN_FILES_PERC / 100 ))
fi
JOURNAL_COMPACT_MIN_FILES_CAP=$(( JOURNAL_COMPACT_MIN_FILES_DISK_CAP / JOURNAL_FILE_SIZE ))
JOURNAL_COMPACT_MIN_FILES=$(( JOURNAL_COMPACT_MIN_FILES > JOURNAL_COMPACT_MIN_FILES_CAP ? JOURNAL_COMPACT_MIN_FILES_CAP : JOURNAL_COMPACT_MIN_FILES ))
JOURNAL_BUFFER_SIZE=$(( MAX_MEMORY * JOURNAL_BUFFER_SIZE_PERC / 100 ))
JOURNAL_BUFFER_SIZE=$(( JOURNAL_BUFFER_SIZE > INT_MAX ? INT_MAX : JOURNAL_BUFFER_SIZE ))
JOURNAL_BUFFER_TIMEOUT=$(( 1000000000 / JOURNAL_BUFFER_PER_SEC ))
PAGE_SYNC_TIMEOUT=$(( 1000000000 / PAGE_SYNC_PER_SEC ))
export JOURNAL_MIN_FILES JOURNAL_POOL_FILES JOURNAL_COMPACT_MIN_FILES JOURNAL_BUFFER_SIZE JOURNAL_BUFFER_TIMEOUT PAGE_SYNC_TIMEOUT

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

# Size of Journal.
JOURNAL_SIZE=$( du -sb ./data/journal | sed 's/\([^ \t]*\).*/\1/' )
LARGE_MESSAGE_SIZE=$( du -sb ./data/large-messages | sed 's/\([^ \t]*\).*/\1/' )
PAGING_SIZE=$( du -sb ./data/paging | sed 's/\([^ \t]*\).*/\1/' )
TOTAL_JOURNAL_SIZE=$(( JOURNAL_SIZE + LARGE_MESSAGE_SIZE + PAGING_SIZE ))
JOURNAL_COMPACT_MIN_MEM=$(( JOURNAL_COMPACT_MIN_FILES * JOURNAL_FILE_SIZE * 1024 * 1024 ))
echo "TOTAL_JOURNAL_SIZE=${TOTAL_JOURNAL_SIZE}"
echo "JOURNAL_COMPACT_MIN_MEM=${JOURNAL_COMPACT_MIN_MEM}"

# Compacts the journal.
if ${FORCE_COMPACT} #|| [ "${TOTAL_JOURNAL_SIZE}" -gt "${JOURNAL_COMPACT_MIN_MEM}" ]
then
	echo "Journal too big. Compacting files before starting."
	./bin/artemis data compact
fi

# Recovers the journal.
if ${FORCE_RECOVER}
then
	echo "Recovering journal."
	./bin/artemis data recover
fi

# Tunes Java opts.
. java_tune_opts
java_tune_opts

# Starts the broker.
echo "Starting broker."
exec ${EXEC}
