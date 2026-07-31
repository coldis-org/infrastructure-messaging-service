# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

ARTEMIS_HOME='/opt/artemis'
ARTEMIS_INSTANCE='/var/lib/artemis'
ARTEMIS_DATA_DIR='/var/lib/artemis/data'
ARTEMIS_ETC_DIR='/var/lib/artemis/etc'
ARTEMIS_OOME_DUMP='/var/lib/artemis/log/oom_dump.hprof'

# The logging config will need an URI
# this will be encoded in case you use spaces or special characters
# on your directory structure
ARTEMIS_INSTANCE_URI='file:/var/lib/artemis/'
ARTEMIS_INSTANCE_ETC_URI='file:/var/lib/artemis/etc/'

# Roles allowed to log into the console at all - bin/artemis turns this into -Dhawtio.roles.
# Comma-separated list; '*' or empty disables the check, so never leave it blank. Defaults to
# ARTEMIS_ADMIN_ROLE. This is the ONLY effective role check on the console today, so treat every
# role listed here as a full administrator - see the note on management.xml below.
HAWTIO_ROLES=${ARTEMIS_CONSOLE_ROLES:-${ARTEMIS_ADMIN_ROLE}}

# On '-Dcom.sun.management.jmxremote' below: it is load bearing for metrics, despite the name. It
# makes the JVM create the Platform MBeanServer during startup, before the broker can install the
# interceptor that enforces management.xml. Without it the Prometheus javaagent scrapes zero Artemis
# beans - silently, with jmx_scrape_error still 0. It opens no socket by itself: remote JMX needs an
# explicit port, which is deliberately not set. Keeping it means management.xml is never enforced, so
# the console cannot be tiered and only the HAWTIO_ROLES gate above applies. That is the intended
# trade: read only access to broker state is Grafana's job, off these very metrics, and the console
# stays an administrator only tool. Do not remove this flag to "fix" management.xml without moving
# metrics to Artemis' native Prometheus plugin first.
if [ -z "$JAVA_ARGS" ]; then
    JAVA_ARGS=" \
    -XX:AutoBoxCacheMax=20000 \
    -XX:+PrintClassHistogram \
    -XX:+UseStringDeduplication \
    --add-opens java.base/jdk.internal.misc=ALL-UNNAMED \
    --add-opens=java.base/java.nio=ALL-UNNAMED \
    -Dhawtio.disableProxy=true \
    -Dhawtio.offline=true \
    -Dhawtio.realm=console \
    -Dhawtio.rolePrincipalClasses=org.apache.activemq.artemis.spi.core.security.jaas.RolePrincipal \
    -Dhawtio.http.strictTransportSecurity=max-age=31536000;includeSubDomains;preload \
    -Djolokia.policyLocation=${ARTEMIS_INSTANCE_ETC_URI}jolokia-access.xml \
    -Dlog4j2.disableJmx=true \
    -XshowSettings:vm \
    -Dcom.sun.management.jmxremote \
    -XX:MaxDirectMemorySize=${MAX_DIRECT_MEMORY}m \
    -javaagent:${ARTEMIS_ETC_DIR}/jmx_prometheus_javaagent-0.20.0.jar=1234:${ARTEMIS_ETC_DIR}/config.yml"
fi

# Java Opts.S
JAVA_ARGS="$JAVA_ARGS $JAVA_OPTS"
