# From Java service.
FROM coldis/infrastructure-java-service:9.0.0

# Make sure pipes are considered to determine success.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /opt/

# Variables.
ENV ARTEMIS_USERNAME=artemis\
	ARTEMIS_PASSWORD=artemis\
	ARTEMIS_ADMIN_ROLE=admin

# Configures users and basic libs.
RUN groupadd -r artemis \
	&& useradd -r -g artemis artemis \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 update -y \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 full-upgrade -y \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 autoremove -y \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 install -y libaio1 curl jq \
	&& rm -rf /var/lib/apt-get/lists/*
# Installs Artemis.
ENV ACTIVEMQ_ARTEMIS_VERSION="2.41.0"
RUN apt-get update \
	&& apt-get install -y --no-install-recommends wget gnupg2 \
	&& wget "https://www.apache.org/dist/activemq/activemq-artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz" \
	&& wget "https://www.apache.org/dist/activemq/activemq-artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" \
	&& wget "https://apache.org/dist/activemq/KEYS" \
	&& gpg --no-tty --import "KEYS" \
	&& gpg --no-tty "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" \
	&& tar xfz apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz \
	&& mv apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION} artemis \
	&& chmod 755 artemis \
	&& rm -f apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz KEYS apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc \
	&& apt-get remove -y wget gnupg2 \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 autoremove -y \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt-get/lists/* 

# Installs basic libs.
RUN  apt-get update \
	&& apt-get install -y --no-install-recommends gettext-base moreutils \
	&& apt-get remove -y wget gnupg2 \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 autoremove -y \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt-get/lists/* 

# Creates broker instance.
RUN cd /var/lib \
	&& /opt/artemis/bin/artemis create artemis \
	--home /opt/artemis \
	--user "${ARTEMIS_USERNAME}" \
	--password "${ARTEMIS_PASSWORD}" \
	--http-host 0.0.0.0 --host 0.0.0.0 --relax-jolokia --require-login --verbose
COPY config /var/lib/artemis/etc
RUN mkdir -p /var/lib/artemis/lock \
	&& mkdir -p /var/lib/artemis/data \
	&& chown -R artemis.artemis /var/lib/artemis \
	&& usermod -d /var/lib/artemis artemis

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
	MAX_GLOBAL_SIZE_MEM_PERC=30\
	QUEUE_MAX_SIZE_FULL_ABS=500\
	QUEUE_MAX_SIZE_FULL_MEM_PERC=5\
	QUEUE_MAX_SIZE_FULL_COUNT=1000000\
	QUEUE_MAX_PREFECTH_WINDOW_SIZE_MULT=200\
	QUEUE_MAX_PREFECTH_SIZE_COUNT=2000000\
	QUEUE_MAX_EXTRA_READ_SIZE_WINDOW_SIZE_MULT=800\
	QUEUE_MAX_EXTRA_READ_SIZE_COUNT=8000000\
	ASYNC_CONNECTION_EXECUTION_ENABLED=true\
	THREAD_POOL_PROC_PERC=500\
	THREAD_POOL_MIN=64\
	SCHEDULED_THREAD_POOL_PROC_PERC=500\
	SCHEDULED_THREAD_POOL_MIN=32\
	PAGE_SYNC_PER_SEC=200\
	PAGE_SIZE_PERC=10\
	PAGE_MAX_SIZE=50\
	IO_THREAD_POOL_PROC_PERC=300\
	IO_THREAD_POOL_MIN=16\
	READ_WHOLE_PAGE=false\
	JOURNAL_SYNC_TRANSACTIONAL=true\
	JOURNAL_SYNC_NON_TRANSACTIONAL=false\
	JOURNAL_TYPE=NIO\
	JOURNAL_MAX_IO=1\
	JOURNAL_FILE_SIZE_PERC=1\
	JOURNAL_FILE_MAX_SIZE=50\
	JOURNAL_MIN_FILES_PERC=20\
	JOURNAL_MIN_FILES_DISK_CAP=3000\
	JOURNAL_POOL_FILES_PERC=20\  
	JOURNAL_POOL_FILES_DISK_CAP=3000\
	JOURNAL_COMPACT_MIN_FILES_PERC=20\
	JOURNAL_COMPACT_MIN_FILES_DISK_CAP=3000\
	JOURNAL_COMPACT_PERC=60\
	JOURNAL_BUFFER_SIZE_PERC=3\
	JOURNAL_BUFFER_PER_SEC=400\
	JOURNAL_DATA_SYNC=false\
	LAST_VALUE_KEY=_AMQ_LVQ_NAME\
	CONSUMER_WINDOW_SIZE=1048576\
	SLOW_CONSUMER_THRESHOLD=1\
	SLOW_CONSUMER_THRESHOLD_MEASUREMENT_UNIT=MESSAGES_PER_MINUTE\
	SLOW_CONSUMER_POLICY=KILL\
	SLOW_CONSUMER_CHECK_PERIOD=1200\
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
	CONN_CONNECTIONS_ALLOWED_MEM_PERC=100\
	FORCE_COMPACT=false\
	FORCE_RECOVER=false\
	ARTEMIS_DIR=/var/lib/artemis/etc

# Web Server
EXPOSE 8161 \
	# JMX Exporter
	9404 \
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

