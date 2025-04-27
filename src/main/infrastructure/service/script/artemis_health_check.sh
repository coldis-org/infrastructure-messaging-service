#!/bin/sh

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
  --message-count 100 \
  --receive-timeout 1000 \
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
		exit "Health check failed."
	fi
fi



