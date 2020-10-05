# From Java service.
FROM coldis/infrastructure-java-service

# Creates the user and group for Artemis.
RUN groupadd -r artemis && \
	useradd -r -g artemis artemis

# Installs necessary libs.
RUN apt-get update && \
	apt-get install -y --no-install-recommends libaio1 xmlstarlet curl jq && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*

# Installs Artemis.
ENV ACTIVEMQ_ARTEMIS_VERSION 2.15.0 
RUN apt-get update && \
	apt-get install -y --no-install-recommends wget gnupg2 && \
	cd /opt && \
	wget "https://www.apache.org/dist/activemq/activemq-artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz" && \
	wget "https://www.apache.org/dist/activemq/activemq-artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" && \
	wget "https://apache.org/dist/activemq/KEYS" && \
	gpg --no-tty --import "KEYS" && \
	gpg --no-tty "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" && \	
	tar xfz apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz && \
	ln -s apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION} apache-artemis && \
	chmod 755 apache-artemis && \
	rm -f apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz KEYS apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc && \
	apt-get remove -y wget gnupg2 && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*


# Creates broker instance.
RUN cd /var/lib && \
	/opt/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}/bin/artemis create artemis \
	--home /opt/apache-artemis \
	--user artemis \
	--password password \
	--role amq \
	--require-login \
	--cluster-user artemisCluster \
	--cluster-password password && ls -la artemis && ls artemis/bin

# Copies scripts and utilities.
RUN mkdir -p /opt/artemis-utils
COPY utils /opt/artemis-utils
COPY config /var/lib/artemis/etc
COPY script/artemis_init.sh /artemis_init
COPY script/artemis_health_check.sh /artemis_health_check
RUN mkdir -p /opt/jmx-exporter/etc/ \
		/var/lib/artemis/lock && \
	ln -s /opt/artemis-utils/jmx-exporter-config.yaml /opt/jmx-exporter/etc/jmx-exporter-config.yaml && \
	chown -R artemis.artemis \
		/artemis_init \
		/var/lib/artemis \
		/opt/artemis-utils \
		/opt/jmx-exporter && \
	chmod 755 -R /artemis_init

# Goes back to artemis user.
USER artemis

# Exposes ports. 
# Web Server
EXPOSE 8161
# CORE,MQTT,AMQP,HORNETQ,STOMP,OPENWIRE
EXPOSE 61616
# HORNETQ,STOMP
EXPOSE 5445
# AMQP
EXPOSE 5672
# MQTT
EXPOSE 1883
# STOMP
EXPOSE 61613

# Work directory.
WORKDIR /var/lib/artemis/bin

# Command.
ENTRYPOINT [ "/artemis_init" ]
CMD [ "./artemis", "run" ]

