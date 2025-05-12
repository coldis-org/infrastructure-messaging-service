#!/bin/sh

# Retry count.
retry_count=${retry_count:=6}
retry_wait=${retry_wait:=5}
check_type="curl"

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
        
        # Retry wait.
        -w|--retry-wait)
            retry_wait=${2}
            shift
            ;;
            
        # Check type.
        -t|--check-type)
            check_type=${2}
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

health_check_success=false

# Shell scripts.
if [ "${check_type}" = "shell" ]
then

	if bin/artemis check queue \
	  --url tcp://localhost:61616 \
	  --user "${ARTEMIS_USERNAME}" \
	  --password "${ARTEMIS_PASSWORD}" \
	  --name "health-check" \
	  --timeout ${receive_timeout} \
	  --produce 1 \
	  --consume 1
	then
		health_check_success=true
	fi	

else 

	send_response=$(curl -f -s -u ${ARTEMIS_USERNAME}:${ARTEMIS_PASSWORD} -X POST -H "Origin: localhost" \
		-H "Content-Type: application/json" "http://localhost:8161/console/jolokia/exec" -d \
	"{\
		\"type\": \"EXEC\", \
		\"mbean\": \"org.apache.activemq.artemis:broker=\\\"0.0.0.0\\\",component=addresses,address=\\\"health-check\\\",subcomponent=queues,routing-type=\\\"anycast\\\",queue=\\\"health-check\\\"\", \
		\"operation\": \"sendMessage(java.util.Map,int,java.lang.String,boolean,java.lang.String,java.lang.String)\", \
		\"arguments\": [ {}, 1, \"test\", false, \"${ARTEMIS_USERNAME}\", \"${ARTEMIS_PASSWORD}\" ]\
	}")
	send_response_status=$(echo ${send_response} | jq ".status")
	echo "Post status: ${send_response_status}"
	
	if [ "${send_response_status}" = "404" ]
	then
        echo "Queue not found. Creating queue..."
	    bin/artemis queue create \
	        --url tcp://localhost:61616 \
	        --user "${ARTEMIS_USERNAME}" \
	        --password "${ARTEMIS_PASSWORD}" \
	        --name "health-check" \
	        --auto-create-address \
	        --durable --anycast \
	        --silent
	        
        # Tries sending the message again.
		send_response=$(curl -f -s -u ${ARTEMIS_USERNAME}:${ARTEMIS_PASSWORD} -X POST -H "Origin: localhost" \
			-H "Content-Type: application/json" "http://localhost:8161/console/jolokia/exec" -d \
		"{\
			\"type\": \"EXEC\", \
			\"mbean\": \"org.apache.activemq.artemis:broker=\\\"0.0.0.0\\\",component=addresses,address=\\\"health-check\\\",subcomponent=queues,routing-type=\\\"anycast\\\",queue=\\\"health-check\\\"\", \
			\"operation\": \"sendMessage(java.util.Map,int,java.lang.String,boolean,java.lang.String,java.lang.String)\", \
			\"arguments\": [ {}, 1, \"test\", false, \"${ARTEMIS_USERNAME}\", \"${ARTEMIS_PASSWORD}\" ]\
		}")
		send_response_status=$(echo ${send_response} | jq ".status")
		echo "Post status: ${send_response_status}"
    fi
	
	peek_response=$(curl -f -s -u ${ARTEMIS_USERNAME}:${ARTEMIS_PASSWORD} -X POST -H "Origin: localhost" \
		-H "Content-Type: application/json" "http://localhost:8161/console/jolokia/exec" -d \
	"{\
		\"type\": \"EXEC\", \
		\"mbean\": \"org.apache.activemq.artemis:broker=\\\"0.0.0.0\\\",component=addresses,address=\\\"health-check\\\",subcomponent=queues,routing-type=\\\"anycast\\\",queue=\\\"health-check\\\"\", \
		\"operation\": \"removeAllMessages()\", \
		\"arguments\": [ ]\
	}")
	peek_response_status=$(echo ${peek_response} | jq ".status")
	echo "Peek status: ${peek_response_status}"
	if ( [ "${send_response_status}" = "200" ] || (echo ${send_response_status} | grep "AMQ229119") ) && [ "${peek_response_status}" = "200" ]
	then
		health_check_success=true
	fi
	
fi
 

# Adds a message to the expiry queue.
if ${health_check_success}
then 
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




