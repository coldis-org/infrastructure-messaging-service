#!/bin/sh

# Retry count.
retry_count=${retry_count:=6}
receive_timeout=${receive_timeout:=5000}

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Retry count.
		-r|--retry-count)
            retry_count=${2}
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


# Adds a message to the expiry queue.
health_check_success=false
if bin/artemis producer \
  --url tcp://localhost:61616 \
  --user "${ARTEMIS_USERNAME}" \
  --password "${ARTEMIS_PASSWORD}" \
  --destination "health-check" \
  --message-count 1 \
  --message "Health check" \
  && \
  bin/artemis consumer \
  --url tcp://localhost:61616 \
  --user "${ARTEMIS_USERNAME}" \
  --password "${ARTEMIS_PASSWORD}" \
  --destination "health-check" \
  --message-count 5 \
  --receive-timeout ${receive_timeout} \
  --break-on-null
then 
    health_check_success=true
    echo "Message added and received in the health check queue."
else
    echo "Failed to add/receive message to the health check queue."
fi

# Ignores health check if the producers are blocked.
if [ "${health_check_success}" != "true" ]
then
	if (tail -200 /var/lib/artemis/log/artemis.log | grep "AMQ222212")
	then 
   	 	echo "Ignoring health check because the producers are blocked."
	else 
	    if [ "${retry_count}" -gt 0 ]
        then
            echo "Retrying health check in 5 seconds..."
            sleep 3
            retry_count=$((retry_count - 1))
            exec "$0" "$@" --retry-count ${retry_count}
        else
            echo "Health check failed after multiple attempts."
            exit 1
        fi
	fi
fi



