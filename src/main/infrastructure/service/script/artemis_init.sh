#!/bin/sh
set -e

BROKER_HOME=/var/lib/artemis
CONFIG_PATH=$BROKER_HOME/etc
export BROKER_HOME CONFIG_PATH

# Log to tty to enable docker logs container-name
sed -i "s/logger.handlers=.*/logger.handlers=CONSOLE/g" ${CONFIG_PATH}/logging.properties

# Update users and roles with if username and password is passed as argument
if [ "$ARTEMIS_USERNAME" ] && [ "$ARTEMIS_PASSWORD" ]; then
	$BROKER_HOME/bin/artemis user rm --user artemis
	$BROKER_HOME/bin/artemis user add --user "$ARTEMIS_USERNAME" --password "$ARTEMIS_PASSWORD" --role "technology-messaging-service-admin"
fi

# Runs performance journal.
performanceJournal() {
	perfJournalConfiguration=${ARTEMIS_PERF_JOURNAL:-AUTO}
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
