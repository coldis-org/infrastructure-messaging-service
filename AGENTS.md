# AGENTS.md

ActiveMQ Artemis broker image of the coldis platform (GitHub
`coldis-org/infrastructure-messaging-service`): Artemis 2.55.0 on top of
`coldis/infrastructure-java-service`, with boot scripts that size the broker from the container's
limits, LDAP-backed console authentication, a break-glass account and a Prometheus JMX exporter.
No application code; `pom.xml` (parent `org.coldis:configuration`) carries no build of its own.

Image layering: `os` -> `java-service` -> **messaging-service**
(`FROM coldis/infrastructure-java-service:11.0.1`).

## Layout

All under `src/main/infrastructure/service/`.

| Path | Holds |
|------|-------|
| `Dockerfile` | Builds the JAAS refresh agent (JDK stage), installs Artemis, creates the broker instance, all tunables as `ENV` |
| `config/` | Copied to `/var/lib/artemis/etc`: `broker.xml`, `addresses.xml`, `queues.xml`, `connectors.xml`, `routers.xml`, `management.xml`, `login.config`, `artemis.profile`, exporter `config.yml` and jar |
| `script/artemis_init.sh` | Entrypoint: `os_limits`, users/connectors/routers, sizing, `envsubst` of the config, `java_tune_opts`, `exec` |
| `script/artemis_*.sh` | Users, connectors, routers, LDAP endpoint (`artemis_update_conn`), break glass, health check |
| `agent/JaasRefreshAgent.java` | Java agent that makes `etc/login.config` reloadable at runtime |
| `legacy/` | Old exporter jars, repository-only (not copied into the image); see its README |
| `utils/` | `merge.xslt`, `enable-jmx.xml`; not copied into the image |
| `service.json` | Marathon-style app definition (still the `infrastructure-java-service` one) |

## Commands

No build script or CI. The image builds from its folder:

```bash
docker build -t coldis/infrastructure-messaging-service:<tag> src/main/infrastructure/service
```

## Gotchas

- **Config is rendered at boot.** `artemis_init` runs `envsubst` with every environment variable
  over `broker.xml`, `management.xml` and `login.config`, so any `$NAME` in them that matches an
  environment variable is replaced. Sizes (thread pools, journal, paging, global max size) are
  computed there from `AVAILABLE_CPUS` / `AVAILABLE_MEMORY` and the `*_PERC` defaults.
- **JAAS only expands system properties**, never environment variables: LDAP settings reach
  `login.config` through that `envsubst`, and `JAAS_VALUE` strips one layer of quotes and escapes
  the rest. One stray `"` makes the whole file unparseable and takes down the `activemq` realm
  (messaging and the health check), not only the console.
- **The broker and break-glass accounts ship with working default credentials**
  (`ARTEMIS_USERNAME/PASSWORD`, `ARTEMIS_BREAKGLASS_USERNAME/PASSWORD` in the Dockerfile). The
  break-glass one authenticates on the CORE acceptor (61616) with full management rights; override
  both per environment.
- **With no LDAP configured the console has no valid users** — on purpose, rather than falling back
  to system accounts.
- **`-Dcom.sun.management.jmxremote` in `artemis.profile` is load-bearing for metrics**: without it
  the Prometheus agent scrapes zero Artemis beans, silently.
- **The exporter 1.x validates counters**: metrics in `config/config.yml` are `GAUGE`, because
  Artemis reports `-1` for unlimited and a negative counter fails the whole scrape
  (`legacy/README.md`).
- **`libaio.so.1` is a symlink** to `libaio.so.1t64`; without it `ASYNCIO` silently falls back to
  NIO.
- **Debian userland assumed.** The Dockerfile uses `apt-get` and
  `/usr/lib/x86_64-linux-gnu`; the current `java-service` Dockerfile is Alpine, so raising the
  `FROM` tag to an Alpine release needs this Dockerfile reworked.

## Conventions

- Scripts live in `script/` as `artemis_*.sh`, `#!/bin/sh`, are copied to `/opt/artemis-script` and
  linked into `/usr/bin` without the `.sh` suffix (`artemis_init.sh` -> `/usr/bin/artemis_init`).
- Tunables are environment variables with a default in the Dockerfile `ENV` block, consumed by
  `artemis_init` and substituted into the XML config with `envsubst`.
- Runtime changes (LDAP endpoint, users) go through scripts driven by the orchestrator template and
  `/local/application.env`; `artemis_init` sources that file at boot too.

## Workspace

This repository expects `supersim-infrastructure-code-reviewer` checked out next to it
(`../supersim-infrastructure-code-reviewer`; clone it there from the internal Git host if it's
missing). The review-gate summary and the local review both live in it.

## Review

The gates are those of `src/agents/review/review.toml`, read from master, so a branch can't weaken
its own review: `security`, `platform-image`, `platform-runtime`, `platform-config` and the
`shellcheck` rule (severity `warning`, HIGH on failure). What each gate stops:
`../supersim-infrastructure-code-reviewer/local-review/GATES.md`. No gate reviews the Java agent
(`agent/JaasRefreshAgent.java`) beyond `security`. The PR description must name every base image,
Artemis version, default, port, credential variable, journal or data path changed.

Before pushing, run the local review: follow
`../supersim-infrastructure-code-reviewer/local-review/REVIEW.md`. It ends with
`local-check attest`. Push only when the developer asks.
