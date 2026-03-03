# Ansible Deployment

This directory provides the configuration-management layer for the assessment.

## What It Does

- Installs Docker and Docker Compose on the target host
- Deploys the Kong stack to `/opt/kong`
- Deploys the Prometheus and Grafana stack to `/opt/observability`

## Layout

```text
anisible/
├── ansible.cfg
├── group_vars/
│   └── all.yml
├── inventories/
│   ├── aws/
│   ├── azure/
│   └── local/
├── playbooks/
│   └── site.yml
└── roles/
    ├── docker/
    ├── kong/
    └── observability/
```

## Run Locally

```bash
cd anisible
ansible-playbook -i inventories/local/hosts.yml playbooks/site.yml
```

## Run Against AWS Or Azure

1. Copy the relevant inventory example and replace the placeholder host.
2. Ensure SSH access works with the provisioned VM.
3. Run:

```bash
cd anisible
ansible-playbook -i inventories/aws/hosts.yml playbooks/site.yml
```

or

```bash
cd anisible
ansible-playbook -i inventories/azure/hosts.yml playbooks/site.yml
```

## Assumptions

- Debian or Ubuntu based target hosts
- Passwordless sudo or equivalent privilege escalation
- Terraform has already provisioned the host for AWS or Azure

