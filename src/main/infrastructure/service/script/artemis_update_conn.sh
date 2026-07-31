#!/bin/sh

# Default script behavior.
set -o errexit

# Default parameters.
DEBUG=true
DEBUG_OPT=
LOGIN_CONFIG=/var/lib/artemis/etc/login.config
ENV_FILE="/local/application.env"
SKIP_RELOAD=false

# For each argument.
while :; do
	case ${1} in

		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;

		# If actual reload should be done.
		--skip-reload)
			SKIP_RELOAD=true
			;;

		# No more options.
		*)
			break

	esac
	shift
done

# Enables interruption signal handling.
trap - INT TERM

# Update environment variables
if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi

CHECK_LDAP_CONN () {
  LDAP_CONN_FILE=$( grep -oE 'connectionURL="ldap://[^"]*"' ${LOGIN_CONFIG} | sed -e 's#.*ldap://##' -e 's/"$//' )

  if [ "$LDAP_CONN_FILE" != "${LDAP_URI}:${LDAP_PORT}" ]; then
    # Written in place so the timestamp changes and the file keeps its inode.
    sed "s#connectionURL=\"ldap://${LDAP_CONN_FILE}\"#connectionURL=\"ldap://${LDAP_URI}:${LDAP_PORT}\"#" ${LOGIN_CONFIG} > /tmp/login.config.new
    cat /tmp/login.config.new > ${LOGIN_CONFIG}
    rm -f /tmp/login.config.new
    echo "UPDATING LDAP_CONN=${LDAP_URI} - LDAP_PORT=${LDAP_PORT}"
  else
    ${DEBUG} && echo "LDAP_CONN unchanged: ${LDAP_CONN_FILE}"
  fi
}

RELOAD_LDAP_CONN () {
  # No command to call, unlike the databases' pg_reload_conf(): JAAS caches login.config for the life
  # of the JVM, so the JaasRefreshAgent watches the file and does the reload from inside the process.
  # It picks the rewrite above up within its polling period.
  echo "Reloading configuration"
}

if [ -z "$LDAP_URI" ] || [ -z "$LDAP_PORT" ]; then
  echo "Not found LDAP environment values"
else
  echo "Update LDAP connection"
  CHECK_LDAP_CONN

  if [ $SKIP_RELOAD != "true" ]; then
    RELOAD_LDAP_CONN
  else
    echo "Skiping reload configuration"
  fi
fi
