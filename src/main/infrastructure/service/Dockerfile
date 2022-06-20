# From Java service.
FROM coldis/infrastructure-java-service:3.0

# Make sure pipes are considered to determine success.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /opt/

# Variables.
ENV ARTEMIS_USERNAME=artemis \
	ARTEMIS_PASSWORD=artemis \
	EXTRA_ARGS="--http-host 0.0.0.0 --host 0.0.0.0 --relax-jolokia --require-login --verbose"

# Configures users and basic libs.
RUN groupadd -r artemis \
	&& useradd -r -g artemis artemis \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 update \
	&& apt-get -qq -o=Dpkg::Use-Pty=0 install -y libaio1 curl jq \
	&& rm -rf /var/lib/apt/lists/*

# Installs Artemis.
ENV ACTIVEMQ_ARTEMIS_VERSION 2.23.0
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
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt/lists/* 
	
# Creates broker instance.
RUN cd /var/lib \
	&& /opt/artemis/bin/artemis create artemis \
	--home /opt/artemis \
	--user "${ARTEMIS_USERNAME}" \
	--password "${ARTEMIS_PASSWORD}" \
	--role "technology-messaging-service-admin" \
	--cluster-user "${ARTEMIS_USERNAME}-cluster" \
	--cluster-password "${ARTEMIS_PASSWORD}" \
	${EXTRA_ARGS}
COPY config /var/lib/artemis/etc
RUN mkdir -p /var/lib/artemis/lock \
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
	
USER artemis

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

