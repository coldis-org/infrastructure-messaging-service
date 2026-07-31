# Legacy Prometheus JMX exporter agents

Kept as a record of which exporter versions this broker ran in the past. Nothing here is loaded, and
nothing here reaches the image: the Dockerfile only copies `config/` and `script/`, so this directory
is repository-only.

The agent in use lives in `config/` and is wired in `config/artemis.profile`.

| Version | Note |
|---|---|
| 0.20.0 | In use until the upgrade to 1.6.0. |
| 1.2.0 | Vendored but never wired in; the profile kept pointing at 0.20.0. |

Moving to the 1.x line required changing `type: COUNTER` to `GAUGE` in `config/config.yml`. Several
Artemis attributes are legitimately negative (`-1` meaning unlimited or disabled), and 1.x validates
counters: a single negative value fails the *whole* scrape with HTTP 500 rather than dropping that
series. Declaring them as counters would also make 1.x append a `_total` suffix to every name.

The upgrade left the 120 `artemis_*` series untouched except `artemis_auto_created`, which became
`artemis_auto` because `_created` is a reserved OpenMetrics suffix. The built-in JVM series were
renamed by the 1.x client, for instance `jvm_memory_bytes_used` to `jvm_memory_used_bytes`.
