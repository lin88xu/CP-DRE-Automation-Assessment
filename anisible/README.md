# Ansible Deployment

This directory provides the configuration-management layer for the assessment.

## What It Does

- Installs Docker and Docker Compose on the target host
- Deploys the Kong stack to `/opt/kong`
- Deploys the Prometheus and Grafana stack to `/opt/observability`

## Prerequisites

To run these playbooks locally, ensure the control machine has:

- `python3`
- `pip`
- `ansible` / `ansible-playbook`
- `terraform` for the local handoff flow
- `docker` and `docker compose`
- `sudo` access for `become`

Recommended checks:

```bash
ansible-playbook --version
terraform version
docker version
docker compose version
```

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
cd terraform/environments/local
terraform init
terraform apply
```

```bash
cd <repo-root>/anisible

ANSIBLE_CONFIG=<repo-root>/anisible/ansible.cfg \
ansible-playbook \
  -K \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/site.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
```

Replace `<repo-root>` with the directory where you cloned this repository. If the repository is being run from WSL under `/mnt/c/...`, Ansible may ignore `ansible.cfg` because the path is considered world-writable. In that case, either set `ANSIBLE_CONFIG` as shown above or use:

```bash
cd <repo-root>/anisible

ANSIBLE_ROLES_PATH=<repo-root>/anisible/roles \
ansible-playbook \
  -K \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/site.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
```

For local runs, `-K` prompts for the sudo password required by `become`.

## Tear Down Local Deployment

```bash
cd <repo-root>/anisible

ANSIBLE_CONFIG=<repo-root>/anisible/ansible.cfg \
ansible-playbook \
  -K \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/teardown.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
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
- Terraform has already provisioned the target host or generated the local handoff files
