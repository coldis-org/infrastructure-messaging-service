# Bug candidates

Observed on 2026-11-03 while configuring the code review for this repository (AGENTS.md and
`src/agents/review/review.toml`). These are **candidates**: noticed while reading, not verified,
not triaged. Credentials are named by location only. Remove an entry once it is confirmed and
tracked elsewhere, or found not to be a bug.

- `artemis_init.sh` copies to `${EXTENSION_CONFIG_FILE}/connectors.xml` and `routers.xml`; `EXTENSION_CONFIG_FILE` is not defined anywhere (likely `EXTENSION_CONFIG_PATH`).
- `service/.gitignore` ignores `/Dockerfile`, which is tracked anyway.
- `pom.xml` (artifactId, `<scm>`) and `service.json` are copies of java-service's.
- Artemis runs as root (`#USER artemis` is commented out) and `artemis_init` runs `chown -R` on every boot.
