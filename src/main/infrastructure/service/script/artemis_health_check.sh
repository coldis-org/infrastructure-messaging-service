#!/bin/sh

# Adds a message to the expiry queue.
POST_RESPONSE=$(curl -f -s -u ${ARTEMIS_USERNAME}:${ARTEMIS_PASSWORD} -X POST -H "Origin: localhost" \
	-H "Content-Type: application/json" "http://localhost:8161/console/jolokia/exec" -d \
"{\
	\"type\": \"EXEC\", \
	\"mbean\": \"org.apache.activemq.artemis:broker=\\\"0.0.0.0\\\",component=addresses,address=\\\"ExpiryQueue\\\",subcomponent=queues,routing-type=\\\"anycast\\\",queue=\\\"ExpiryQueue\\\"\", \
	\"operation\": \"sendMessage(java.util.Map,int,java.lang.String,boolean,java.lang.String,java.lang.String)\", \
	\"arguments\": [ {}, 1, \"test\", false, \"${ARTEMIS_USERNAME}\", \"${ARTEMIS_PASSWORD}\" ]\
}")
#echo ${POST_RESPONSE}
POST_MESSAGE_ID=$(echo ${POST_RESPONSE} | jq ".value")
POST_RESPONSE_STATUS=$(echo ${POST_RESPONSE} | jq ".status")
echo "Post status: ${POST_RESPONSE_STATUS}"
if [ "${POST_RESPONSE_STATUS}" != "200" ]
then

	# If producers are blocked
	if (tail -100 /var/lib/artemis/log/artemis.log | grep "AMQ222212")
	then 
		# Logs it an exit. 
		echo "System will start blocking producers"
		exit 0;
	else 
		# Exits with an error.
		exit "Message could not be added. Status: ${POST_RESPONSE_STATUS}"
	fi
	
fi

# Removes the test message from the queue.
DELETE_RESPONSE=$(curl -f -s -u ${ARTEMIS_USERNAME}:${ARTEMIS_PASSWORD} -X POST -H "Origin: localhost" \
	-H "Content-Type: application/json" "http://localhost:8161/console/jolokia/exec" -d \
"{\
	\"type\": \"EXEC\", \
	\"mbean\": \"org.apache.activemq.artemis:broker=\\\"0.0.0.0\\\",component=addresses,address=\\\"ExpiryQueue\\\",subcomponent=queues,routing-type=\\\"anycast\\\",queue=\\\"ExpiryQueue\\\"\", \
	\"operation\": \"removeMessage(long)\", \
	\"arguments\": [ ${POST_MESSAGE_ID} ]\
}")
#echo ${DELETE_RESPONSE}
DELETE_RESPONSE_STATUS=$(echo ${DELETE_RESPONSE} | jq ".status")
echo "Delete status: ${DELETE_RESPONSE_STATUS}"
if [ "${DELETE_RESPONSE_STATUS}" != "200" ]
then
	exit "Message could not be deleted. Status: ${DELETE_RESPONSE_STATUS}"
fi


