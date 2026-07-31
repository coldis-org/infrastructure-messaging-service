#!/bin/sh

# Default script behavior.
set -o errexit

# Default parameters.
BROKER_HOME=${BROKER_HOME:=/var/lib/artemis}
CONFIG_PATH=${BROKER_HOME}/etc
USERS_FILE=${CONFIG_PATH}/breakglass-users.properties
ROLES_FILE=${CONFIG_PATH}/breakglass-roles.properties
ACTION=status

# For each argument.
while :; do
	case ${1} in

		# Opens console access for the break glass account.
		--enable)
			ACTION=enable
			;;

		# Closes it again.
		--disable)
			ACTION=disable
			;;

		# Reports whether it is open.
		--status)
			ACTION=status
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

# Enables interruption signal handling.
trap - INT TERM

# Opens or closes CONSOLE access for the break glass account. The account itself always exists in the
# 'activemq' realm (see artemis_add_user), so management over CORE never depends on this script - use
# it only when the browser UI is needed while the directory is unreachable.
#
# There is no reload to trigger: the console realm's properties module runs with 'reload=true', so it
# notices these files changing on its own.
case ${ACTION} in

	enable)
		if [ -z "${ARTEMIS_BREAKGLASS_USERNAME}" ] || [ -z "${ARTEMIS_BREAKGLASS_PASSWORD}" ]
		then
			echo "Not found BREAKGLASS environment values"
			exit 1
		fi
		echo "${ARTEMIS_BREAKGLASS_USERNAME}=${ARTEMIS_BREAKGLASS_PASSWORD}" > ${USERS_FILE}
		echo "${ARTEMIS_BREAKGLASS_ROLE:-breakglass}=${ARTEMIS_BREAKGLASS_USERNAME}" > ${ROLES_FILE}
		echo "BREAKGLASS CONSOLE ACCESS ENABLED for ${ARTEMIS_BREAKGLASS_USERNAME} - disable it once the incident is over"
		;;

	disable)
		: > ${USERS_FILE}
		: > ${ROLES_FILE}
		echo "Breakglass console access disabled"
		;;

	status)
		if [ -s "${USERS_FILE}" ]
		then
			echo "Breakglass console access is ENABLED"
		else
			echo "Breakglass console access is disabled"
		fi
		;;

esac
