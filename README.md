# CP DRE Automation Assessment

This repository is a **sample implementation blueprint** for a production-minded service used in a DevSecOps / DRE-style technical assessment.

## Purpose

The goal is to demonstrate how to design, build, deploy, and operate a small web service with strong operational thinking across:

- Infrastructure automation
- GitOps-style delivery
- Observability (logs + metrics)
- Resiliency and recovery

The implementation is intentionally tool-agnostic while aligning with common free-tier/local tooling (e.g., Docker, Minikube, Terraform, Ansible, GitLab CI/GitHub Actions equivalents).

## Assignment-Aligned Scope

This repository should contain artifacts for:

1. **Infrastructure as Code (IaC)**
   - Reproducible environment provisioning from scratch
   - Separation of infrastructure, application, and configuration concerns
   - Terraform (or equivalent)

2. **Configuration Management**
   - Repeatable host or service configuration
   - Ansible (or equivalent)

3. **CI/CD + GitOps Flow**
   - Change lifecycle: `Git -> CI/CD -> environment`
   - Pipeline stages for validate, plan, deploy
   - Safe change practices (e.g., approvals, protected environments, rollback path)

4. **Observability**
   - Meaningful logs and metrics exposed by the service
   - Clear definition of which operational signals matter and why
   - Operator playbook for detection and investigation

5. **Resiliency & Recovery**
   - Failure-aware design
   - Demonstration of at least two failure classes (e.g., app crash, dependency outage, misconfiguration, resource exhaustion)
   - Expected behavior, mitigation, and recovery steps

## Suggested Architecture Overview

A practical reference architecture for this assessment:

- **Application:** small HTTP API service (containerized)
- **Infra Layer:** Terraform provisions local/cloud resources
- **Config Layer:** Ansible applies runtime/system configuration
- **Delivery Layer:** CI pipeline runs lint/test/validate/plan/deploy
- **Runtime Platform:** Docker Compose, Minikube, or lightweight Kubernetes
- **Observability Stack:**
  - Metrics: Prometheus-compatible endpoint + dashboards/alerts
  - Logs: structured application logs + central collection

## Repository Structure (Proposed)

```text
.
├── app/                 # Web service source code
├── infra/               # Terraform modules/stacks
├── config/              # Ansible playbooks/roles
├── ops/                 # Runbooks, failure scenarios, recovery notes
├── ci/                  # Pipeline templates/scripts
└── README.md
```

## Observability Approach

Minimum recommended operational signals:

- **Golden signals** (latency, traffic, errors, saturation)
- **Application health metrics** (uptime, dependency check status)
- **Structured logs** with request IDs and error context
- **Deployment events** tied to release version and commit SHA

Operator workflow should include:

1. Detect issue via alert threshold / SLO burn rate
2. Correlate metrics spike with recent deployment
3. Pivot to logs using trace/request identifiers
4. Apply rollback or mitigation runbook

## Resiliency Design

Example scenarios to validate:

1. **Application failure**
   - Simulate crash/panic
   - Verify restart policy and alerting
2. **Dependency failure**
   - Simulate downstream timeout/unreachable dependency
   - Verify graceful degradation and retry/circuit-breaker strategy
3. **Misconfiguration**
   - Introduce invalid env var or missing secret
   - Verify startup validation and fail-fast behavior
4. **Resource exhaustion**
   - Simulate memory/disk pressure
   - Verify throttling, alerting, and controlled recovery

## CI/CD & Safe Change Practices

Recommended pipeline stages:

1. **Validate**: lint, unit tests, IaC format/validate checks
2. **Plan**: Terraform plan and deployment diff preview
3. **Deploy**: controlled promotion to target environment
4. **Post-deploy checks**: smoke tests + health verification

Safety controls:

- Branch protection and merge request reviews
- Environment-scoped variables/secrets
- Manual approval gate for production
- Rollback strategy (previous artifact / infrastructure state)

## Tradeoffs & Assumptions

- **Cost constraint:** solution should run on local environment or free tier
- **Depth over breadth:** emphasize operational clarity over full-scale completeness
- **Determinism:** reproducible setup and clear runbooks are prioritized

## Bonus Considerations

- SLIs/SLOs and error budgets
- Backup/restore procedures
- Security hygiene (least privilege, secrets handling)
- Post-incident review template and improvement backlog

## Demo Expectations

During walkthrough/interview, be prepared to show:

- Provisioning from scratch
- CI/CD pipeline flow from commit to deployment
- Failure injection and observed system behavior
- Recovery or rollback execution
- Key architecture and tradeoff decisions
