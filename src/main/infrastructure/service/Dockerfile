# Builds the agent that makes etc/login.config reloadable at runtime. Compiled here because the
# runtime image ships a JRE: it has no javac and no jar.
FROM eclipse-temurin:26-jdk AS jaas-refresh-agent
COPY agent /agent
WORKDIR /agent
RUN javac JaasRefreshAgent.java \
	&& printf 'Premain-Class: JaasRefreshAgent\n' > manifest.mf \
	&& jar cfm jaas-refresh-agent.jar manifest.mf JaasRefreshAgent.class

# From Java service.
FROM coldis/infrastructure-java-service:11.2.0

# Make sure pipes are considered to determine success.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /opt/

# Variables.
# ARTEMIS_ADMIN_ROLE is the console/management role, held by LDAP-backed humans only.
# ARTEMIS_SERVICE_ROLE is given to the accounts artemis_add_user creates: produce/consume only.
#
# The break glass account ships with working defaults so that an emergency needs no preparation: with
# the directory unreachable it is the only way left to manage the broker, and enabling one at that
# point would require access nobody is meant to have. Understand what that means before deploying as
# is - it authenticates on the CORE acceptor (61616), not just from inside the container, so anyone
# who reaches that port with these credentials can invoke management, drop addresses and durable
# queues, and read every message in every queue. Override both values per environment.
ENV ARTEMIS_USERNAME=artemis\
	ARTEMIS_PASSWORD=artemis\
	ARTEMIS_ADMIN_ROLE=jms-administrators\
	ARTEMIS_SERVICE_ROLE=service\
	ARTEMIS_BREAKGLASS_ROLE=breakglass\
	ARTEMIS_BREAKGLASS_USERNAME=breakglass\
	ARTEMIS_BREAKGLASS_PASSWORD=breakglass\
	ARTEMIS_CONSOLE_ROLES=

# LDAP backs the console realm (see config/login.config). Empty on purpose: with no LDAP
# configured the console has no valid users at all, instead of falling back to system accounts.
ENV LDAP_HOST=\
	LDAP_URI=\
	LDAP_PORT=389\
	LDAP_USER=\
	LDAP_PASSWORD=\
	LDAP_USERS=\
	LDAP_GROUPS=\
	LDAP_DEBUG=false\
	LDAP_CONNECTION_TIMEOUT=5000\
	LDAP_READ_TIMEOUT=5000

# Configures users and basic libs.
# uid/gid 999 is what the Ubuntu image used: keeping it means existing volumes need no re-chown and
# anything else mounting them sees the same owner. Alpine ships gid 999 as 'ping', which is unused here.
RUN delgroup ping \
	&& addgroup -S -g 999 artemis \
	&& adduser -S -D -H -u 999 -G artemis -h /var/lib/artemis -s /sbin/nologin artemis \
	&& apk upgrade --no-cache \
	&& apk add --no-cache libaio curl jq gettext-envsubst moreutils
# Installs Artemis.
# downloads.apache.org only keeps the latest release, so a pinned version stops building there as soon
# as the next one comes out; archive.apache.org keeps every release but is throttled (~100KB/s, over
# 10 minutes for the tarball). Hence the fast one first and the archive as fallback.
ENV ACTIVEMQ_ARTEMIS_VERSION="2.57.0"
RUN apk add --no-cache --virtual .artemis-build gnupg \
	&& ARTEMIS_FILE="artemis/artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz" \
	&& for MIRROR in https://downloads.apache.org https://archive.apache.org/dist; \
	do \
		wget -q "${MIRROR}/${ARTEMIS_FILE}" && wget -q "${MIRROR}/${ARTEMIS_FILE}.asc" && break; \
		rm -f apache-artemis-*; \
	done \
	&& wget -q "https://downloads.apache.org/artemis/KEYS" \
	&& gpg --no-tty --import "KEYS" \
	&& gpg --no-tty --verify "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" \
	&& tar xfz apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz \
	&& mv apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION} artemis \
	&& chmod 755 artemis \
	&& rm -rf apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz KEYS apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc ~/.gnupg \
	&& apk del .artemis-build

# Creates broker instance.
RUN cd /var/lib \
	&& /opt/artemis/bin/artemis create artemis \
	--home /opt/artemis \
	--user "${ARTEMIS_USERNAME}" \
	--password "${ARTEMIS_PASSWORD}" \
	--http-host 0.0.0.0 --host 0.0.0.0 --relax-jolokia --require-login --verbose
COPY config /var/lib/artemis/etc
COPY --from=jaas-refresh-agent /agent/jaas-refresh-agent.jar /var/lib/artemis/etc/
RUN mkdir -p /var/lib/artemis/lock \
	&& mkdir -p /var/lib/artemis/data \
	&& chown -R artemis:artemis /var/lib/artemis

# Copies the scripts.
RUN mkdir -p /opt/artemis-script
COPY script /opt/artemis-script
RUN chmod -R 755 /opt/artemis-script \
	&& ln -s /opt/artemis-script/*.sh /usr/bin \
	&& for FILE in /usr/bin/artemis*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done

# Artemis user.
#USER artemis

# Variables.
ENV LOG_LEVEL=INFO\
	CRITICAL_ANALYZER_TIMEOUT=60000\
	CRITICAL_ANALYZER_POLICY=LOG\
	MAX_RAM_PERC=55\
	MIN_RAM_PROD_PERC=55\
	MAX_DIRECT_MEM_PERC=10\
	MALLOC_ARENA_MAX=2\
	MAX_GLOBAL_SIZE_MEM_PERC=30\
	QUEUE_MAX_SIZE_FULL_ABS=500\
	QUEUE_MAX_SIZE_FULL_MEM_PERC=10\
	QUEUE_MAX_SIZE_FULL_COUNT=200000\
	QUEUE_MAX_PREFECTH_WINDOW_SIZE_MULT=200\
	QUEUE_MAX_PREFECTH_SIZE_COUNT=100000\
	QUEUE_MAX_EXTRA_READ_SIZE_WINDOW_SIZE_MULT=1000\
	QUEUE_MAX_EXTRA_READ_SIZE_MEM_PERC=1\
	QUEUE_MAX_EXTRA_READ_SIZE_COUNT=100000\
	ASYNC_CONNECTION_EXECUTION_ENABLED=true\
	THREAD_POOL_PROC_PERC=700\
	THREAD_POOL_MIN=64\
	SCHEDULED_THREAD_POOL_PROC_PERC=300\
	SCHEDULED_THREAD_POOL_MIN=32\
	PAGE_SYNC_PER_SEC=200\
	PAGE_SIZE_PERC=10\
	PAGE_MAX_SIZE=50\
	IO_THREAD_POOL_PROC_PERC=300\
	IO_THREAD_POOL_MIN=16\
	READ_WHOLE_PAGE=false\
	JOURNAL_SYNC_TRANSACTIONAL=true\
	JOURNAL_SYNC_NON_TRANSACTIONAL=false\
	MESSAGE_EXPIRY_SCAN_PERIOD=-1\
	JOURNAL_TYPE=ASYNCIO\
	JOURNAL_MAX_IO=\
	JOURNAL_AIO_MEM_PERC=5\
	JOURNAL_BUFFER_MAX_SIZE=16\
	JOURNAL_FILE_SIZE_PERC=1\
	JOURNAL_FILE_MAX_SIZE=50\
	JOURNAL_MIN_FILES_PERC=20\
	JOURNAL_MIN_FILES_DISK_CAP=3000\
	JOURNAL_POOL_FILES_PERC=20\  
	JOURNAL_POOL_FILES_DISK_CAP=3000\
	JOURNAL_COMPACT_MIN_FILES=10\
	JOURNAL_COMPACT_MIN_FILES_DISK_CAP=3000\
	JOURNAL_COMPACT_PERC=50\
	JOURNAL_BUFFER_SIZE_PERC=3\
	JOURNAL_BUFFER_PER_SEC=400\
	JOURNAL_DATA_SYNC=false\
	LAST_VALUE_KEY=_AMQ_LVQ_NAME\
	TRANSACTION_TIMEOUT=20000\
	CONSUMER_WINDOW_SIZE=65536\
	SLOW_CONSUMER_THRESHOLD=1\
	SLOW_CONSUMER_THRESHOLD_MEASUREMENT_UNIT=MESSAGES_PER_HOUR\
	SLOW_CONSUMER_POLICY=KILL\
	SLOW_CONSUMER_CHECK_PERIOD=3600\
	MAX_EXPIRY_DELAY=345600000\
	CONN_USE_EPOLL=false\
	CONN_TCP_BUFFER_SIZE=-1\
	CONN_LOW_BUFFER_WATERMARK_PERC=\
	CONN_HIGH_BUFFER_WATERMARK_PERC=\
	CONN_LOW_BUFFER_WATERMARK=32768\
	CONN_HIGH_BUFFER_WATERMARK=1048576\
	CONN_TCP_NO_DELAY=true\
	CONN_BATCH_DELAY=0\
	CONN_DIRECT_DELIVER=false\
	CONN_HANDSHAKE_TIMEOUT=360\
	CONN_REMOTING_THREADS_PROC_PERC=1000\
	CONN_REMOTING_THREADS_MIN=64\
	CONN_CONNECTIONS_ALLOWED_MEM_PERC=10\
	FORCE_COMPACT=false\
	FORCE_RECOVER=false\
	ARTEMIS_DIR=/var/lib/artemis/etc

# Web Server
EXPOSE 8161 \
	# JMX Exporter (port set on the javaagent in config/artemis.profile)
	1234 \
	# Port for CORE,MQTT,AMQP,HORNETQ,STOMP,OPENWIRE
	61616 \
	# Port for HORNETQ,STOMP
	5445 \
	# Port for AMQP
	5672 \
	# Port for MQTT
	1883 \
	#Port for STOMP
	61613
	
# Workdir.
WORKDIR /var/lib/artemis

# Command.
ENTRYPOINT [ "artemis_init" ]
CMD [ "bin/artemis", "run" ]

