#!/bin/sh
set -e

BROKER_HOME=/var/lib/artemis
CONFIG_PATH=$BROKER_HOME/etc
export BROKER_HOME CONFIG_PATH

# Update users and roles with if username and password is passed as argument
if [ "${ARTEMIS_USERNAME}" ] && [ "${ARTEMIS_PASSWORD}" ]; then
	echo "${ARTEMIS_USERNAME} = ${ARTEMIS_PASSWORD}" > ${CONFIG_PATH}/artemis-users.properties
	echo "technology-messaging-service-admin = ${ARTEMIS_USERNAME}" > ${CONFIG_PATH}/artemis-roles.properties
	cat ${CONFIG_PATH}/artemis-users.properties
fi

# If global max size is set.
if [ "${ARTEMIS_GLOBAL_MAX_SIZE}" ]; then
	# Adds the global max size to the configuration.
	sed -i "s#<!-- Global max size\. -->#<!-- Global max size. -->\n\t\t<global-max-size>${ARTEMIS_GLOBAL_MAX_SIZE}</global-max-size>#" ${CONFIG_PATH}/broker.xml
fi
# If global max size is set.
if [ "${JOURNAL_BUFFER_SIZE}" ]; then
	# Adds the global max size to the configuration.
	sed -i "s#<journal-buffer-size>1M</journal-buffer-size>#<journal-buffer-size>${JOURNAL_BUFFER_SIZE}</journal-buffer-size>#" ${CONFIG_PATH}/broker.xml
fi

# Runs performance journal.
performanceJournal() {
	perfJournalConfiguration=${ARTEMIS_PERF_JOURNAL:-NONE}
	if [ "$perfJournalConfiguration" = "AUTO" ] || [ "$perfJournalConfiguration" = "ALWAYS" ]; then

		if [ "$perfJournalConfiguration" = "AUTO" ] && [ -e /var/lib/artemis/data/.perf-journal-completed ]; then
			echo "Volume's journal buffer already fine tuned"
			return
		fi

		echo "Calculating performance journal ... "
		RECOMMENDED_JOURNAL_BUFFER=$("./artemis" "perf-journal" | grep "<journal-buffer-timeout" | xmlstarlet sel -t -c '/journal-buffer-timeout/text()' || true)
		if [ -z "$RECOMMENDED_JOURNAL_BUFFER" ]; then
			echo "There was an error calculating the performance journal, gracefully handling it"
			return
		fi

		xmlstarlet ed -L \
			-N activemq="urn:activemq" \
			-N core="urn:activemq:core" \
			-u "/activemq:configuration/core:core/core:journal-buffer-timeout" \
			-v "$RECOMMENDED_JOURNAL_BUFFER" ../etc/broker.xml
			echo "$RECOMMENDED_JOURNAL_BUFFER"

		if [ "$perfJournalConfiguration" = "AUTO" ]; then
			touch /var/lib/artemis/data/.perf-journal-completed
		fi
	else
		echo "Skipping performance journal tuning as per user request"
	fi
}
if (echo "${ACTIVEMQ_ARTEMIS_VERSION}" | grep -Eq	"(1.5\\.[^12]|[^1]\\.[0-9]+\\.[0-9]+)" ) ; then 
	performanceJournal
else
	echo "Ignoring any performance journal parameter as version predates it: ${ACTIVEMQ_ARTEMIS_VERSION}"
fi

# Runs Artemis.
exec "$@"
