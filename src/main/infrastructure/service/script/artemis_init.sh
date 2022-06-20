#!/bin/sh
set -e

# Makes sure data is available.
chown -R artemis.artemis /var/lib/artemis
su - artemis

# Variables.
BROKER_HOME=/var/lib/artemis
CONFIG_PATH=$BROKER_HOME/etc
export BROKER_HOME CONFIG_PATH

# Update users and roles with if username and password is passed as argument
if [ "${ARTEMIS_USERNAME}" ] && [ "${ARTEMIS_PASSWORD}" ]; then
	echo "${ARTEMIS_USERNAME} = ${ARTEMIS_PASSWORD}" > ${CONFIG_PATH}/artemis-users.properties
	echo "technology-messaging-service-admin = ${ARTEMIS_USERNAME}" > ${CONFIG_PATH}/artemis-roles.properties
	cat ${CONFIG_PATH}/artemis-users.properties
fi

exec "$@"
