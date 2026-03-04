# Minikube Deployment

This directory contains the Kubernetes manifests used by the Ansible `minikube`
runtime path.

What it deploys:

- a `httpbin` upstream deployment and service
- a PostgreSQL deployment and PVC for Kong state
- a Kong deployment backed by PostgreSQL, plus a bootstrap job that imports the repo-managed config into the database
- a cluster-internal Kong service plus a dedicated NodePort service for the Kong proxy only
- a Prometheus deployment and cluster-internal service that scrapes Kong metrics
- a Grafana deployment and cluster-internal service preloaded with the official Kong dashboard
- a HorizontalPodAutoscaler for Kong based on CPU and memory utilization
- PersistentVolumeClaim for Kong Postgres, Prometheus, and Grafana so state survives pod recreation

The Ansible Minikube role installs Minikube and `kubectl`, starts a local
cluster with the Docker driver, enables the `metrics-server` and `ingress`
addons plus the default storage add-ons, and applies these manifests.

Default access ports after deployment:

- Kong Proxy: `30080`
- Kong Admin API: `kubectl port-forward svc/kong 8001:8001`
- Kong Manager UI: `kubectl port-forward svc/kong 8002:8002`
- Prometheus: `kubectl port-forward svc/prometheus 9090:9090`
- Grafana: `kubectl port-forward svc/grafana 3000:3000`

These defaults can be overridden from Ansible group variables.

Grafana credentials:

- Username defaults to `grafana-admin`
- Password is generated during deployment unless `GRAFANA_ADMIN_PASSWORD` is set
