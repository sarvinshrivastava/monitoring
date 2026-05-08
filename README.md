# Monitoring Stack

VPS monitoring stack — Grafana + Prometheus + Uptime Kuma.

## Services

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | https://monitoring.vps.sarvinshrivastava.space | Dashboards + alerting |
| Uptime Kuma | https://status.vps.sarvinshrivastava.space | Public status page |
| Prometheus | internal only (port 9090) | Metrics scraping |

## Grafana Dashboards to Import

After logging in to Grafana, import these dashboards by ID:

- **Node Exporter Full** — ID `1860` (system metrics: CPU, memory, disk, network)
- **Docker Container Stats** — ID `11600` (per-container resource usage)

## Stack

- **Prometheus** — scrapes node-exporter (host metrics) and cAdvisor (container metrics)
- **node-exporter** — exposes host OS metrics
- **cAdvisor** — exposes Docker container metrics
- **Grafana** — visualises Prometheus data; Prometheus datasource auto-provisioned
- **Uptime Kuma** — uptime monitoring with status page

## Secrets (managed via secrets-manager)

| Secret key | Purpose |
|------------|---------|
| `MONITORING_GRAFANA_USER` | Grafana admin username |
| `MONITORING_GRAFANA_PASSWORD` | Grafana admin password |
| `MONITORING_APP_PORT` | Host port for Grafana (3100) |
| `MONITORING_UPTIME_PORT` | Host port for Uptime Kuma (3101) |
