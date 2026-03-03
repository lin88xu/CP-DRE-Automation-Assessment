# Prometheus And Grafana

This directory contains a local observability stack for the Kong assessment.

## Included

- `docker-compose.yml`: Prometheus and Grafana services
- `prometheus/prometheus.yml`: scrape configuration
- `prometheus/rules/kong-alerts.yml`: starter alert rules
- `grafana/provisioning/...`: datasource and dashboard provisioning
- `../kong/kong/plugins/prometheus/grafana/kong-official.json`: official Kong Grafana dashboard mounted into Grafana

## Default Access

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`
- Grafana login: `admin` / `admin`

## Expected Kong Dependency

The stack expects Kong metrics to be available on:

- `http://host.docker.internal:8001/metrics`

This repository enables the Kong `prometheus` plugin in the declarative config so the Admin API can expose those metrics.

Kong does not emit separate metric names for "RPS per route" or "RPS per service". Those views come from the `service` and `route` labels on the shared request and latency metrics, and they only show data after traffic passes through Kong.

## Start

```bash
cd promethusGrafana
docker-compose up -d
```

## Stop

```bash
cd promethusGrafana
docker-compose down
```
