import java.io.File;
import java.lang.instrument.Instrumentation;
import java.lang.management.ManagementFactory;
import java.util.Set;

import javax.management.MBeanServer;
import javax.management.ObjectName;
import javax.security.auth.login.Configuration;

/**
 * Makes etc/login.config reloadable while the broker runs.
 *
 * JAAS parses that file once, when the JVM starts, and keeps it in a cached singleton. Nothing in
 * Artemis re-reads it: reloadConfigurationFile, restartEmbeddedWebServer, clearAuthenticationCache
 * and clearAuthorizationCache were all measured leaving the stale configuration in place. So a
 * directory that moves to a new address and port could only be picked up by restarting the task.
 *
 * Invalidating that cache takes two steps, and measurement showed both are required: Configuration
 * .refresh() re-parses the file, and restarting the embedded web server makes Hawtio resolve the
 * realm again - refresh() alone left the console authenticating against the previous endpoint.
 *
 * Both run in-process on purpose. Driving the restart from outside means calling it over Jolokia,
 * which needs a console login, which is exactly what is broken when the directory address is stale:
 * measured, the call came back 403 and never executed, leaving the console permanently down. Nothing
 * here authenticates, so there is no such circularity.
 *
 * Restarting the web server drops in-flight console sessions and Jolokia requests for a moment. The
 * messaging protocols, the health check (which runs over CORE) and the Prometheus javaagent (its own
 * HTTP server) are all untouched.
 *
 * Deliberately outside the authentication path: it only drops a cache and restarts a listener, and
 * never inspects or handles credentials. Any failure is logged and swallowed, because a broker that
 * stops taking messages is far worse than a console that keeps using the previous address.
 */
public final class JaasRefreshAgent {

	private static final String DEFAULT_FILE = "/var/lib/artemis/etc/login.config";

	private static final long DEFAULT_PERIOD_SECONDS = 10L;

	private static final long RESTART_TIMEOUT_MILLIS = 30000L;

	private JaasRefreshAgent() {
	}

	public static void premain(final String agentArgs, final Instrumentation instrumentation) {
		final File file = new File(agentArgs == null || agentArgs.isBlank() ? DEFAULT_FILE : agentArgs.trim());
		final long period = Long.getLong("jaas.refresh.period", DEFAULT_PERIOD_SECONDS) * 1000L;

		final Thread watcher = new Thread(() -> watch(file, period), "jaas-refresh");
		watcher.setDaemon(true);
		watcher.start();

		log("watching " + file + " every " + (period / 1000L) + "s");
	}

	private static void watch(final File file, final long period) {
		long known = file.lastModified();
		while (true) {
			try {
				Thread.sleep(period);
				final long current = file.lastModified();
				// Zero means the file is gone; waiting for it to come back beats refreshing against
				// nothing, which would leave every login failing.
				if (current != 0L && current != known) {
					known = current;
					Configuration.getConfiguration().refresh();
					restartWebServer();
					log("reloaded " + file);
				}
			}
			catch (final InterruptedException exception) {
				Thread.currentThread().interrupt();
				return;
			}
			catch (final Throwable throwable) {
				log("could not reload " + file + ": " + throwable);
			}
		}
	}

	/**
	 * Hawtio caches the realm configuration, so refreshing JAAS is not enough on its own. Note this
	 * relies on the MBean access guard staying uninstalled, which is what artemis.profile's
	 * '-Dcom.sun.management.jmxremote' already causes for the Prometheus javaagent's sake.
	 */
	private static void restartWebServer() throws Exception {
		final MBeanServer server = ManagementFactory.getPlatformMBeanServer();
		final Set<ObjectName> brokers = server.queryNames(new ObjectName("org.apache.activemq.artemis:broker=*"), null);

		if (brokers.isEmpty()) {
			// Still starting up: whatever comes next reads the file anyway.
			log("no broker MBean yet, refreshed the configuration only");
			return;
		}

		for (final ObjectName broker : brokers) {
			server.invoke(broker, "restartEmbeddedWebServer", new Object[] { RESTART_TIMEOUT_MILLIS },
					new String[] { "long" });
			return;
		}
	}

	private static void log(final String message) {
		System.out.println("JaasRefreshAgent: " + message);
	}

}
