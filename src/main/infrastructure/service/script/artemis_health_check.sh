#!/bin/bash

# Absolute, because this runs as an orchestrator health check and cannot assume a working directory:
# the CLI calls below used to be relative, which passed under 'docker exec' (it inherits the image's
# WORKDIR) and failed with "bin/artemis: not found" wherever the check was invoked from elsewhere.
BROKER_HOME=${BROKER_HOME:=/var/lib/artemis}

# Retry count.
retry_count=${retry_count:=6}
retry_wait=${retry_wait:=5}
receive_timeout=${receive_timeout:=10000}
# Checks over the messaging protocol, not over the console: the console and its Jolokia endpoint
# authenticate in the 'console' realm (LDAP only), so ARTEMIS_USERNAME cannot reach them.
# 'stomp' does what 'shell' does - produce one message and consume it back, in the 'activemq' realm -
# but from bash, over the loopback-only STOMP acceptor in broker.xml. 'shell' starts a whole JVM for
# the CLI on every run: measured ~2.5 CPU seconds per check against ~0.1 for 'stomp', and at the
# orchestrator's check rate that alone pinned small brokers at their CPU quota. 'shell' stays as a
# fallback, and 'curl' for brokers whose console realm still accepts system accounts.
check_type="stomp"
stomp_port=${stomp_port:=61613}
health_check_queue="health-check"

# Produces one persistent message to the health check queue and waits to consume that same message
# back. Sending first, and only subscribing once the broker has receipted the send, is deliberate:
# the send auto-creates the anycast queue on a fresh broker, and a subscription opened before the
# queue existed was measured never receiving the message. Anything else found in the queue, left by
# an earlier run that timed out, is consumed along the way.
stomp_check() {
	local message_id
	local deadline
	message_id="health-check-$$-$(date +%s%N)"
	deadline=$(( $(date +%s) + receive_timeout / 1000 ))
	local frame=
	local success=false

	# A broker that drops the connection (bad credentials, shutting down) must fail the check and go
	# through the retries below, not kill the script with SIGPIPE on the next write.
	trap '' PIPE
	if ! exec 3<>"/dev/tcp/127.0.0.1/${stomp_port}"
	then
		echo "Could not connect to the STOMP acceptor on port ${stomp_port}."
		return 1
	fi

	# Frames are NUL terminated; between them the broker may send bare EOLs, stripped on read.
	send_frame() { printf '%s\n\n%s\0' "${1}" "${2:-}" >&3 2>/dev/null; }
	read_frame() {
		local wait=$(( deadline - $(date +%s) ))
		[ "${wait}" -gt 0 ] && IFS= read -r -d '' -t "${wait}" -u 3 frame && frame="${frame#"${frame%%[!$'\n']*}"}"
	}

	send_frame "CONNECT
accept-version:1.2
host:localhost
heart-beat:0,0
login:${ARTEMIS_USERNAME}
passcode:${ARTEMIS_PASSWORD}"

	while read_frame
	do
		case "${frame}" in
			ERROR*)
				echo "${frame}" | grep '^message:'
				break
				;;
			CONNECTED*)
				send_frame "SEND
destination:${health_check_queue}
destination-type:ANYCAST
persistent:true
content-type:text/plain
receipt:sent" "${message_id}"
				;;
			RECEIPT*)
				send_frame "SUBSCRIBE
id:0
destination:${health_check_queue}
destination-type:ANYCAST
ack:auto"
				;;
			MESSAGE*"${message_id}")
				success=true
				break
				;;
		esac
	done

	send_frame "DISCONNECT"
	exec 3>&-
	${success}
}

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument: still accepted so callers passing it keep working, but this script has no
		# debug output - tracing it would print the credentials in the CONNECT frame.
		--debug)
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

# STOMP, from bash.
if [ "${check_type}" = "stomp" ]
then

	if stomp_check
	then
		health_check_success=true
	fi

# Artemis CLI.
elif [ "${check_type}" = "shell" ]
then

	if ${BROKER_HOME}/bin/artemis check queue \
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
	    ${BROKER_HOME}/bin/artemis queue create \
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




