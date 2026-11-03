# Bug candidates

Observed on 2026-11-03 while configuring the code review for this repository (AGENTS.md and
`src/agents/review/review.toml`). These are **candidates**: noticed while reading, not verified,
not triaged. Credentials are named by location only. Remove an entry once it is confirmed and
tracked elsewhere, or found not to be a bug.

- `artemis_init.sh` copies to `${EXTENSION_CONFIG_FILE}/connectors.xml` and `routers.xml`; `EXTENSION_CONFIG_FILE` is not defined anywhere (likely `EXTENSION_CONFIG_PATH`).
- The Dockerfile `EXPOSE`s 9404 for the JMX exporter while `config/artemis.profile` starts the exporter on 1234.
- The Dockerfile uses `apt-get`, `useradd`, `chown a.b` and `/usr/lib/x86_64-linux-gnu` on `coldis/infrastructure-java-service:11.0.1`; java-service has since moved to Alpine, so the next base bump breaks the build.
- `service/.gitignore` ignores `/Dockerfile`, which is tracked anyway.
- `pom.xml` (artifactId, `<scm>`) and `service.json` are copies of java-service's.
- Artemis runs as root (`#USER artemis` is commented out) and `artemis_init` runs `chown -R` on every boot.
