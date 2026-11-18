#!/bin/bash

# Broker tests for the messaging image. They run on the host and drive
# containers: the broker boots with the AIO journal, authentication holds,
# older Artemis clients still connect, a volume written by a published
# image is picked up by the image under test with its messages intact, and
# the runtime edits the volume-swap drain makes to two running brokers
# (AMQP on the acceptor, a federation block) reload without a restart.
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
# Health check: STOMP from bash on the loopback acceptor. First on purpose, while the health-check
# queue does not exist yet - the case where a subscription opened too early never gets the message.
check "the health check passes on a fresh broker" 'docker exec -e retry_count=0 "$B" artemis_health_check >/dev/null 2>&1'
# Before the wrong-password check, which warns on purpose. A check that closed its connection
# abruptly logged a reset (four WARN lines) on every run.
health_check_is_quiet() {
	local before
	before=$(docker logs "$B" 2>&1 | grep -c WARN)
	docker exec -e retry_count=0 "$B" artemis_health_check >/dev/null 2>&1 || return 1
	sleep 2
	[ "$(docker logs "$B" 2>&1 | grep -c WARN)" -eq "$before" ]
}
check "the health check leaves no warning in the broker log" 'health_check_is_quiet'
check "the health check fails on a wrong password" '! docker exec -e ARTEMIS_PASSWORD=wrong -e retry_count=0 "$B" artemis_health_check >/dev/null 2>&1'
check "the health check STOMP acceptor is loopback only" 'docker exec "$B" bash -c "exec 3<>/dev/tcp/127.0.0.1/61613 && exec 5<>/dev/tcp/\$(hostname -i)/61616 && ! exec 4<>/dev/tcp/\$(hostname -i)/61613" 2>/dev/null'
# Runs overlap in production (retries, checks the orchestrator gave up on): they must not take each
# other's messages.
concurrent_health_checks() {
	local i failed=0
	for i in 1 2 3 4 5 6; do docker exec -e retry_count=0 "$B" artemis_health_check >/dev/null 2>&1 & done
	for i in 1 2 3 4 5 6; do wait -n || failed=1; done
	[ "$failed" -eq 0 ]
}
check "six health checks at once all pass" 'concurrent_health_checks'
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

# Runtime drain: what messaging/drain_messaging_service (infrastructure-automation-platform) does to
# two running brokers after a volume swap. AMQP is added to the old broker's CORE acceptor and a
# federation block to the new broker, each by editing broker.xml and letting the configuration
# reload apply it, then the block is removed again. The playbook waits for the log lines checked
# here. Data on tmpfs: nothing here has to persist, and a full journal preallocated on disk only
# slows it down.
DRAIN_OPTIONS=(--tmpfs "$DATA:rw,size=600m" -e JOURNAL_TYPE=NIO -e JOURNAL_MIN_FILES_DISK_CAP=100
	-e JOURNAL_POOL_FILES_DISK_CAP=100 -e JOURNAL_COMPACT_MIN_FILES_DISK_CAP=100)
ETC=/var/lib/artemis/etc/broker.xml
logged_count() { docker logs "$1" 2>&1 | grep -cF -- "$2"; }
# Waits until the log of container $1 holds more than $3 lines with fixed string $2 (30s at most).
logged() {
	for _ in $(seq 30); do
		[ "$(logged_count "$1" "$2")" -gt "$3" ] && return 0
		sleep 1
	done
	return 1
}
OLD=$PREFIX-old; NEW=$PREFIX-new
start "$OLD" "$IMAGE" "${DRAIN_OPTIONS[@]}" && start "$NEW" "$IMAGE" "${DRAIN_OPTIONS[@]}"; R=$?
check "drain: both brokers start" '[ $R -eq 0 ]'
check "drain: 5 messages wait on the old broker" '[ "$(cli "$OLD" 127.0.0.1 producer "$SERVICE_USER" "--message-count 5")" = "Produced: 5 messages" ]'
# The playbook reads these counts by column position, logged in with the break-glass account.
QUEUE_STAT=$(docker exec "$OLD" sh -c 'cd /var/lib/artemis && bin/artemis queue stat --user "$ARTEMIS_BREAKGLASS_USERNAME" --password "$ARTEMIS_BREAKGLASS_PASSWORD" --url tcp://localhost:61616 --maxRows 100000 --maxColumnSize -1 2>/dev/null')
check "drain: queue stat keeps the layout the playbook reads" '[ "$(awk -F"|" "{ for (i = 2; i <= 5; i++) gsub(/ /, \"\", \$i) } \$2 == \"NAME\" { print \$2, \$3, \$4, \$5; exit }" <<< "$QUEUE_STAT")" = "NAME ADDRESS CONSUMER MESSAGE" ]'
check "drain: queue stat counts the 5 messages in its fourth column" '[ "$(awk -F"|" "{ gsub(/ /, \"\", \$2); gsub(/ /, \"\", \$5) } \$2 == \"broker-test\" { print \$5 }" <<< "$QUEUE_STAT")" = 5 ]'

reloads=$(logged_count "$OLD" AMQ221087)
docker exec "$OLD" sed -i '/<acceptor name="artemis">/s/protocols=CORE;/protocols=CORE,AMQP;/' "$ETC"
check "drain: the old broker reloads its configuration" 'logged "$OLD" AMQ221087 "$reloads"'
check "drain: its CORE acceptor restarts accepting AMQP" 'logged "$OLD" "61616 for protocols [CORE,AMQP]" 0'

reloads=$(logged_count "$NEW" AMQ221087)
docker exec -i "$NEW" sh -c 'cat > /tmp/drain.xml' <<EOF
		<!-- drain-federation:begin -->
		<broker-connections>
			<amqp-connection uri="tcp://$OLD:61616" name="drain-federation" user="artemis" password="artemis" retry-interval="5000" reconnect-attempts="360">
				<federation>
					<local-queue-policy name="drain-federation-queues">
						<include address-match="#" queue-match="#"/>
						<exclude address-match="activemq.#" queue-match="#"/>
						<exclude address-match="health-check" queue-match="#"/>
					</local-queue-policy>
					<property key="amqpCredits" value="10"/>
					<property key="amqpLowCredits" value="3"/>
				</federation>
			</amqp-connection>
		</broker-connections>
		<!-- drain-federation:end -->
EOF
docker exec "$NEW" sh -c "awk '/<acceptors>/ { while ((getline line < \"/tmp/drain.xml\") > 0) print line } { print }' $ETC > /tmp/broker.xml && cat /tmp/broker.xml > $ETC"
check "drain: the new broker reloads its configuration" 'logged "$NEW" AMQ221087 "$reloads"'
check "drain: the federation connects to the old broker" 'logged "$NEW" "Connected on Server AMQP Connection drain-federation on" 0'
check "drain: the new broker delivers the old broker's 5 messages" '[ "$(cli "$NEW" 127.0.0.1 consumer "$SERVICE_USER" "--message-count 5 --receive-timeout 30000")" = "Consumed: 5 messages" ]'

reloads=$(logged_count "$NEW" AMQ221087)
docker exec "$NEW" sh -c "awk '/drain-federation:begin/ { skip = 1 } !skip { print } /drain-federation:end/ { skip = 0 }' $ETC > /tmp/broker.xml && cat /tmp/broker.xml > $ETC"
check "drain: removing the block reloads the new broker" 'logged "$NEW" AMQ221087 "$reloads"'
cli "$OLD" 127.0.0.1 producer "$SERVICE_USER" "--message-count 2" >/dev/null
check "drain: once removed, the new broker pulls nothing" '[ "$(cli "$NEW" 127.0.0.1 consumer "$SERVICE_USER" "--message-count 2 --receive-timeout 10000")" != "Consumed: 2 messages" ]'

# What `adjust` does: the block, removed above, added again with another window, reconnects.
reloads=$(logged_count "$NEW" AMQ221087)
connections=$(logged_count "$NEW" "Connected on Server AMQP Connection drain-federation on")
docker exec "$NEW" sed -i -e 's/key="amqpCredits" value="10"/key="amqpCredits" value="1000"/' -e 's/key="amqpLowCredits" value="3"/key="amqpLowCredits" value="300"/' /tmp/drain.xml
docker exec "$NEW" sh -c "awk '/<acceptors>/ { while ((getline line < \"/tmp/drain.xml\") > 0) print line } { print }' $ETC > /tmp/broker.xml && cat /tmp/broker.xml > $ETC"
check "drain: adding it again reloads the new broker" 'logged "$NEW" AMQ221087 "$reloads"'
check "drain: the federation added again connects again" 'logged "$NEW" "Connected on Server AMQP Connection drain-federation on" "$connections"'
check "drain: and pulls the 2 left on the old broker" '[ "$(cli "$NEW" 127.0.0.1 consumer "$SERVICE_USER" "--message-count 2 --receive-timeout 30000")" = "Consumed: 2 messages" ]'
check "drain: neither broker restarted" '[ "$(logged_count "$OLD" AMQ221007)$(logged_count "$NEW" AMQ221007)" = 11 ]'
docker rm -f "$OLD" "$NEW" >/dev/null

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
