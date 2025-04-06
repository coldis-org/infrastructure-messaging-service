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
ENV ACTIVEMQ_ARTEMIS_VERSION="2.40.0"
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

# Variables.
ENV LOG_LEVEL=INFO\
	MAX_GLOBAL_SIZE_MEM_PERC=25\
	MAX_QUEUE_SIZE_MEM_PERC=8\
	MAX_QUEUE_SIZE_COUNT=5000000\
	PREFECTH_QUEUE_SIZE_MEM_PERC=3\
	PREFECTH_QUEUE_SIZE_COUNT=100000\
	ASYNC_CONNECTION_EXECUTION_ENABLED=true\
	THREAD_POOL_PROC_PERC=4000\
	THREAD_POOL_MIN=32\
	SCHEDULED_THREAD_POOL_PROC_PERC=300\
	SCHEDULED_THREAD_POOL_MIN=16\
	PAGE_SYNC_PER_SEC=500\
	PAGE_SIZE_PERC=10\
	PAGE_MAX_SIZE=30\
	PAGE_MAX_IO_CONCURRENCY=30\
	READ_WHOLE_PAGE=false\
	JOURNAL_TYPE=NIO\
	JOURNAL_MAX_IO=1\
	JOURNAL_FILE_SIZE_PERC=1\
	JOURNAL_FILE_MAX_SIZE=100\
	JOURNAL_MIN_FILES_PERC=10\
	JOURNAL_MIN_FILES_DISK_CAP=1000\
	JOURNAL_POOL_FILES_PERC=20\
	JOURNAL_POOL_FILES_DISK_CAP=20000\
	JOURNAL_COMPACT_MIN_FILES_PERC=30\
	JOURNAL_COMPACT_MIN_FILES_DISK_CAP=30000\
	JOURNAL_COMPACT_PERC=50\
	JOURNAL_BUFFER_SIZE_PERC=3\
	JOURNAL_BUFFER_PER_SEC=500\
	JOURNAL_DATA_SYNC=false\
	LAST_VALUE_KEY=_AMQ_LVQ_NAME\
	CONSUMER_WINDOW_SIZE=262144\
	CONN_USE_EPOLL=false\
	CONN_TCP_BUFFER_SIZE=262144\
	CONN_LOW_BUFFER_WATERMARK_PERC=100\
	CONN_HIGH_BUFFER_WATERMARK_PERC=400\
	CONN_TCP_NO_DELAY=true\
	CONN_BATCH_DELAY=3\
	CONN_DIRECT_DELIVER=false\
	CONN_HANDSHAKE_TIMEOUT=360\
	CONN_REMOTING_THREADS_PROC_PERC=3000\
	CONN_REMOTING_THREADS_MIN=36\
	CONN_CONNECTIONS_ALLOWED_MEM_PERC=700\
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

