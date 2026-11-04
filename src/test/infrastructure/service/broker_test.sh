#!/bin/bash

# Broker tests for the messaging image. They run on the host and drive
# containers: the broker boots with the AIO journal, authentication holds,
# older Artemis clients still connect, and a volume written by a published
# image is picked up by the image under test with its messages intact.
#
#   docker build -t messaging-test src/main/infrastructure/service
#   bash src/test/infrastructure/service/broker_test.sh messaging-test
#
# Published images used as older clients and as upgrade sources (pulled from
# Docker Hub; override with space-separated lists):
#   CLIENT_IMAGES   default: coldis/infrastructure-messaging-service:2.31 (client 2.43)
#                            coldis/infrastructure-messaging-service:2.35.0 (client 2.53)
#   UPGRADE_IMAGES  default: coldis/infrastructure-messaging-service:2.55.2
#                            coldis/infrastructure-messaging-service:2.35.0
# Needs docker; creates and removes its containers, volumes and network.
# Exits non-zero when any test fails.

# Variables used only inside the strings check evaluates look unused to shellcheck.
# shellcheck disable=SC2034
IMAGE=${1:?usage: broker_test.sh <image>}
CLIENT_IMAGES=${CLIENT_IMAGES-coldis/infrastructure-messaging-service:2.31 coldis/infrastructure-messaging-service:2.35.0}
UPGRADE_IMAGES=${UPGRADE_IMAGES-coldis/infrastructure-messaging-service:2.55.2 coldis/infrastructure-messaging-service:2.35.0}
PREFIX=broker-test-$$
NET=$PREFIX-net
DATA=/var/lib/artemis/data
pass=0; fail=0

check() { if eval "$2"; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1"; fi; }
cleanup() {
	docker ps -aq --filter "name=^$PREFIX-" | xargs -r docker rm -f >/dev/null 2>&1
	docker volume ls -q --filter "name=^$PREFIX-" | xargs -r docker volume rm -f >/dev/null 2>&1
	# Endpoints detach asynchronously after docker rm: retry for a few seconds.
	for _ in 1 2 3 4 5; do
		docker network inspect "$NET" >/dev/null 2>&1 || break
		docker network rm "$NET" >/dev/null 2>&1 && break
		sleep 1
	done
}
trap cleanup EXIT
# Starts a broker container and waits until it is active; fails if it exits or 180s pass.
start() { # name image [docker run args...]
	local name=$1 image=$2; shift 2
	docker run -d --name "$name" --network "$NET" "$@" "$image" >/dev/null || return 1
	for _ in $(seq 90); do
		sleep 2
		docker logs "$name" 2>&1 | grep -q "AMQ221007" && return 0
		[ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || return 1
	done
	return 1
}
# Runs the artemis CLI of container $1 against broker $2 (a container name, or
# 127.0.0.1 for the container itself); prints the result line.
cli() { # container broker command credentials extra
	docker exec "$1" sh -c "cd /var/lib/artemis && timeout 90 /opt/artemis/bin/artemis $3 --url tcp://$2:61616 $4 --destination queue://broker-test --silent $5" 2>&1 \
		| grep -oE "AMQ[0-9]+[^.]*|(Produced|Consumed): [0-9]+ messages" | head -1
}
SERVICE_USER='--user "$ARTEMIS_USERNAME" --password "$ARTEMIS_PASSWORD"'

cleanup
docker network create "$NET" >/dev/null || exit 2
echo "== $IMAGE"

# Boot, journal, authentication.
B=$PREFIX-broker
start "$B" "$IMAGE"; R=$?
check "the broker starts" '[ $R -eq 0 ]'
check "the journal is AIO (native libaio loads)" 'docker logs "$B" 2>&1 | grep -q "AMQ221012: Using AIO Journal"'
check "no credentials are rejected" '[[ "$(cli "$B" 127.0.0.1 producer "" "--message-count 1")" == AMQ229031* ]]'
check "a wrong password is rejected" '[[ "$(cli "$B" 127.0.0.1 producer "--user \"\$ARTEMIS_USERNAME\" --password wrong" "--message-count 1")" == AMQ229031* ]]'
check "the service user produces" '[ "$(cli "$B" 127.0.0.1 producer "$SERVICE_USER" "--message-count 3")" = "Produced: 3 messages" ]'
check "the service user consumes" '[ "$(cli "$B" 127.0.0.1 consumer "$SERVICE_USER" "--message-count 3 --receive-timeout 20000")" = "Consumed: 3 messages" ]'

# Older clients against this broker.
index=0
for client_image in $CLIENT_IMAGES
do
	index=$((index+1)); C=$PREFIX-c$index   # short: container names are DNS labels (63 chars at most)
	if ! start "$C" "$client_image"; then fail=$((fail+1)); echo "FAIL: client image $client_image did not start"; continue; fi
	version=$(docker exec "$C" sh -c 'ls /opt/artemis/lib' | grep -oE "artemis-core-client-[0-9.]+[0-9]" | head -1)
	check "client $version produces" '[ "$(cli "$C" "$B" producer "--user artemis --password artemis" "--message-count 2")" = "Produced: 2 messages" ]'
	check "client $version consumes" '[ "$(cli "$C" "$B" consumer "--user artemis --password artemis" "--message-count 2 --receive-timeout 20000")" = "Consumed: 2 messages" ]'
	check "client $version without credentials is rejected" '[[ "$(cli "$C" "$B" producer "" "--message-count 1")" == AMQ229031* ]]'
	docker rm -f "$C" >/dev/null
done
docker rm -f "$B" >/dev/null

# Upgrade: a published image writes persistent messages, this image picks the volume up.
index=0
for old_image in $UPGRADE_IMAGES
do
	index=$((index+1)); V=$PREFIX-v$index; O=$PREFIX-o$index; N=$PREFIX-n$index
	if ! start "$O" "$old_image" -v "$V:$DATA"; then fail=$((fail+1)); echo "FAIL: $old_image did not start"; continue; fi
	check "upgrade from $old_image: 5 persistent messages written" '[ "$(cli "$O" 127.0.0.1 producer "$SERVICE_USER" "--message-count 5")" = "Produced: 5 messages" ]'
	docker stop -t 30 "$O" >/dev/null; docker rm -f "$O" >/dev/null
	start "$N" "$IMAGE" -v "$V:$DATA"; R=$?
	check "upgrade from $old_image: this image starts on the volume" '[ $R -eq 0 ]'
	check "upgrade from $old_image: the journal is AIO" 'docker logs "$N" 2>&1 | grep -q "AMQ221012: Using AIO Journal"'
	check "upgrade from $old_image: the 5 messages are delivered" '[ "$(cli "$N" 127.0.0.1 consumer "$SERVICE_USER" "--message-count 5 --receive-timeout 20000")" = "Consumed: 5 messages" ]'
	docker rm -f "$N" >/dev/null
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
