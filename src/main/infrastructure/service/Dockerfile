# From Java service.
FROM coldis/infrastructure-java-service:7.0.1

# Make sure pipes are considered to determine success.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /opt/

# Variables.
ENV ARTEMIS_USERNAME=artemis\
	ARTEMIS_PASSWORD=artemis

# Configures users and basic libs.
RUN groupadd -r artemis \
	&& useradd -r -g artemis artemis \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 update -y \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 full-upgrade -y \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 autoremove -y \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 install -y libaio1 curl jq \
	&& rm -rf /var/lib/apt-get/lists/*
# Installs Artemis.
ENV ACTIVEMQ_ARTEMIS_VERSION="2.36.0" \
	CREATE_ARGS="--http-host 0.0.0.0 --host 0.0.0.0 --relax-jolokia --require-login --verbose --no-autotune"
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
	--role "technology-messaging-service-admin" \
	--cluster-user "${ARTEMIS_USERNAME}-cluster" \
	--cluster-password "${ARTEMIS_PASSWORD}" \
	${CREATE_ARGS}
COPY config /var/lib/artemis/etc
RUN mkdir -p /var/lib/artemis/lock \
	&& mkdir -p /var/lib/artemis/data \
	&& chown -R artemis.artemis /var/lib/artemis

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
ENV MAX_GLOBAL_SIZE_MEM_PERC=10\
	MAX_QUEUE_SIZE_MEM_PERC=1\
	MAX_QUEUE_SIZE_COUNT=-1\
	PREFECTH_QUEUE_SIZE_MEM_PERC=1\
	PREFECTH_QUEUE_SIZE_COUNT=-1\
	ASYNC_CONNECTION_EXECUTION_ENABLED=true\
	THREAD_POOL_PROC_PERC=-1\
	SCHEDULED_THREAD_POOL_PROC_PERC=300\
	PAGE_SYNC_PER_SEC=200\
	PAGE_SIZE_PERC=1\
	PAGE_MAX_SIZE=200\
	PAGE_MAX_IO_CONCURRENCY=10\
	READ_WHOLE_PAGE=true\
	JOURNAL_TYPE=NIO\
	JOURNAL_MAX_IO=1\
	JOURNAL_FILE_SIZE_PERC=1\
	JOURNAL_FILE_MAX_SIZE=200\
	JOURNAL_MIN_FILES_PERC=5\
	JOURNAL_MIN_FILES_CAP=200\
	JOURNAL_POOL_FILES_PERC=10\
	JOURNAL_POOL_FILES_CAP=500\
	JOURNAL_COMPACT_MIN_FILES_PERC=30\
	JOURNAL_COMPACT_MIN_FILES_CAP=500\
	JOURNAL_COMPACT_PERC=80\
	JOURNAL_BUFFER_SIZE_PERC=3\
	JOURNAL_BUFFER_PER_SEC=200\
	JOURNAL_DATA_SYNC=true\
	LAST_VALUE_KEY=_AMQ_LVQ_NAME\
	CONSUMER_WINDOW_SIZE=524288\
	CONN_USE_EPOLL=false\
	CONN_TCP_BUFFER_SIZE=262144\
	CONN_LOW_BUFFER_WATERMARK_PERC=100\
	CONN_HIGH_BUFFER_WATERMARK_PERC=150\
	CONN_TCP_NO_DELAY=true\
	CONN_BATCH_DELAY=5\
	CONN_DIRECT_DELIVER=false\
	CONN_HANDSHAKE_TIMEOUT=360\
	CONN_REMOTING_THREADS_PROC_PERC=500\
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
CMD [ "./bin/artemis", "run" ]

