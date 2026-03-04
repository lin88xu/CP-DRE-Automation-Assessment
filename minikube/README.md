# Minikube Deployment

This directory contains the Kubernetes manifests used by the Ansible `minikube`
runtime path.

What it deploys:

- a `httpbin` upstream deployment and service
- a DB-less Kong deployment backed by a ConfigMap
- a NodePort service for Kong proxy, Admin API, and Manager
- a Prometheus deployment and NodePort service that scrapes Kong metrics
- a Grafana deployment and NodePort service preloaded with the official Kong dashboard
- a HorizontalPodAutoscaler for Kong based on CPU and memory utilization
- PersistentVolumeClaims for Prometheus and Grafana so observability data survives pod recreation

The Ansible Minikube role installs Minikube and `kubectl`, starts a local
cluster with the Docker driver, enables the `metrics-server` and `ingress`
addons plus the default storage add-ons, and applies these manifests.

Default access ports after deployment:

- Kong Proxy: `30080`
- Kong Admin API: `30081`
- Kong Manager UI: `30082`
- Prometheus: `30090`
- Grafana: `30030`

These defaults can be overridden from Ansible group variables.

Default Grafana credentials:

- Username: `admin`
- Password: `admin`
