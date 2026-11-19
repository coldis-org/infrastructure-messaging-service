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
# Account names other than the image's defaults and other than the role's, so that the lookups by
# ARTEMIS_USERNAME and by role are what finds them. Both brokers share them: the federation logs in to
# the old broker with the new broker's account. Passwords made per run, hex only, since the template
# below does not escape them for XML as the playbook does.
DRAIN_SERVICE_PASSWORD=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
DRAIN_OPERATOR_PASSWORD=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
DRAIN_OPTIONS+=(-e ARTEMIS_USERNAME=drain-service -e "ARTEMIS_PASSWORD=$DRAIN_SERVICE_PASSWORD"
	-e ARTEMIS_BREAKGLASS_USERNAME=drain-operator -e "ARTEMIS_BREAKGLASS_PASSWORD=$DRAIN_OPERATOR_PASSWORD")
ETC=/var/lib/artemis/etc/broker.xml
# The file the playbook waits on, not the console: a logging change that drops it must fail here.
logged_count() { docker exec "$1" cat /var/lib/artemis/log/artemis.log 2>/dev/null | grep -cF -- "$2"; }
# The accounts as the playbook finds them: the broker's own by ARTEMIS_USERNAME (or the file the boot
# sources), the break-glass one by its role. Each sets $user in the container's shell, and
# PASSWORD_OF_USER then sets $password from the users file, for the command that follows.
ACCOUNT='etc=/var/lib/artemis/etc; [ -f /local/application.env ] && . /local/application.env; user=${ARTEMIS_USERNAME:-artemis}'
BREAKGLASS='etc=/var/lib/artemis/etc; user=$(sed -n "s/^${ARTEMIS_BREAKGLASS_ROLE:-breakglass}=//p" "$etc/artemis-roles.properties" | head -n 1 | cut -d, -f1)'
PASSWORD_OF_USER='password=$(grep "^${user}=" "$etc/artemis-users.properties" | head -n 1 | cut -d= -f2-)'
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
found_user() { docker exec "$1" sh -c "$2; "'echo "$user"'; }
check "drain: the playbook's lookups find the broker's account and the break-glass one" '[ "$(found_user "$OLD" "$ACCOUNT")" = drain-service ] && [ "$(found_user "$OLD" "$BREAKGLASS")" = drain-operator ]'
# A read that does not end like this is taken as cut short; the version comes from the jar's name.
last_line() { docker exec "$1" sh -c "grep -v '^[[:space:]]*\$' $ETC | tail -n 1"; }
check "drain: broker.xml ends in </configuration>" '[ "$(last_line "$NEW")" = "</configuration>" ]'
check "drain: the Artemis version can be read from artemis-server-<version>.jar" 'docker exec "$NEW" ls /opt/artemis/lib | grep -qE "^artemis-server-[0-9]+\.[0-9]+\.[0-9]+\.jar$"'
check "drain: 5 messages wait on the old broker" '[ "$(cli "$OLD" 127.0.0.1 producer "$SERVICE_USER" "--message-count 5")" = "Produced: 5 messages" ]'
# The playbook reads these counts by column position, up to INTERNAL, logged in with the break-glass
# account it finds by role.
queue_stat() { docker exec "$1" sh -c "$BREAKGLASS; $PASSWORD_OF_USER; "'cd /var/lib/artemis && bin/artemis queue stat --user "$user" --password "$password" --url tcp://localhost:61616 --maxRows 100000 --maxColumnSize -1 2>/dev/null'; }
waiting_on() { queue_stat "$1" | awk -F"|" '{ gsub(/ /, "", $2); gsub(/ /, "", $5) } $2 == "broker-test" { print $5 }'; }
QUEUE_STAT=$(queue_stat "$OLD")
check "drain: queue stat keeps the layout the playbook reads" '[ "$(awk -F"|" "{ for (i = 2; i <= 11; i++) gsub(/ /, \"\", \$i) } \$2 == \"NAME\" { print \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11; exit }" <<< "$QUEUE_STAT")" = "NAME ADDRESS CONSUMER MESSAGE MESSAGES DELIVERING MESSAGES SCHEDULED ROUTING INTERNAL" ]'
check "drain: queue stat counts the 5 messages in its fourth column" '[ "$(waiting_on "$OLD")" = 5 ]'

reloads=$(logged_count "$OLD" AMQ221087)
docker exec "$OLD" sed -i '/<acceptor name="artemis">/s/protocols=CORE;/protocols=CORE,AMQP;/' "$ETC"
check "drain: the old broker reloads its configuration" 'logged "$OLD" AMQ221087 "$reloads"'
check "drain: its CORE acceptor restarts accepting AMQP" 'logged "$OLD" "61616 for protocols [CORE,AMQP]" 0'

reloads=$(logged_count "$NEW" AMQ221087)
# A template: $OLD and the account are filled in inside the container, by envsubst.
docker exec -i "$NEW" sh -c 'cat > /tmp/drain.template' <<'EOF'
		<!-- drain-federation:begin -->
		<broker-connections>
			<amqp-connection uri="tcp://$OLD:61616" name="drain-federation" user="$DRAIN_USER" password="$DRAIN_PASSWORD" retry-interval="5000" reconnect-attempts="360">
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
# The broker's own account, filled in inside the container as the playbook takes it: never typed here.
docker exec -e OLD="$OLD" "$NEW" sh -c "$ACCOUNT; $PASSWORD_OF_USER; "'DRAIN_USER=$user DRAIN_PASSWORD=$password envsubst "\$OLD \$DRAIN_USER \$DRAIN_PASSWORD" < /tmp/drain.template > /tmp/drain.xml'
docker exec "$NEW" sh -c "awk '/<acceptors>/ { while ((getline line < \"/tmp/drain.xml\") > 0) print line } { print }' $ETC > /tmp/broker.xml && cat /tmp/broker.xml > $ETC"
check "drain: the new broker reloads its configuration" 'logged "$NEW" AMQ221087 "$reloads"'
check "drain: the federation connects to the old broker" 'logged "$NEW" "Connected on Server AMQP Connection drain-federation on" 0'
check "drain: the new broker delivers the old broker's 5 messages" '[ "$(cli "$NEW" 127.0.0.1 consumer "$SERVICE_USER" "--message-count 5 --receive-timeout 30000")" = "Consumed: 5 messages" ]'

reloads=$(logged_count "$NEW" AMQ221087)
docker exec "$NEW" sh -c "awk '/drain-federation:begin/ { skip = 1 } !skip { print } /drain-federation:end/ { skip = 0 }' $ETC > /tmp/broker.xml && cat /tmp/broker.xml > $ETC"
check "drain: removing the block reloads the new broker" 'logged "$NEW" AMQ221087 "$reloads"'
cli "$OLD" 127.0.0.1 producer "$SERVICE_USER" "--message-count 2" >/dev/null
# A consumer on the new broker is the demand the federation pulls for. It subscribes and, with the
# block gone, gets nothing for 15s (the CLI waits for its count, so `timeout` ends it), while the
# old broker keeps both messages.
PULLED=$(docker exec "$NEW" sh -c "cd /var/lib/artemis && timeout 15 /opt/artemis/bin/artemis consumer --url tcp://127.0.0.1:61616 $SERVICE_USER --destination queue://broker-test --message-count 2 --receive-timeout 10000" 2>&1)
check "drain: once removed, a consumer on the new broker subscribes and gets nothing" '[[ "$PULLED" == *"Consumer ActiveMQQueue[broker-test]"* && "$PULLED" != *"Consumed:"* && "$PULLED" != *eceived* ]]'
check "drain: and the old broker still holds both messages" '[ "$(waiting_on "$OLD")" = 2 ]'

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
