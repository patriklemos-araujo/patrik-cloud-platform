# CLAUDE.md — Project Context & Engineering Rules

Context file for AI-assisted work (Claude Code) on this repository.
These rules are non-negotiable unless explicitly overridden by the repository owner in the current session.

## What this project is

A hands-on platform engineering lab, built from scratch, phase by phase:

- **Phase 1 — Containerization:** Python app, multi-stage Dockerfile, non-root user, small images, Compose for local app + db.
- **Phase 2 — Kubernetes:** kind/k3d local first (pods, deployments, services, ingress, probes, HPA, RBAC), then ephemeral EKS via Terraform with IRSA.
- **Phase 3 — CI/CD & GitOps:** GitHub Actions (build → test → scan → push to ECR), Argo CD pull-based deploys, own Helm chart.
- **Phase 4 — Observability:** kube-prometheus-stack, OpenTelemetry, SLI/SLO with error budget and multi-window burn-rate alerts.
- **Phase 5 — Cloud-native security:** tfsec/trivy in pipeline, External Secrets, network policies, Pod Security Standards, controls mapped to SOC 2 CC6 and ISO 27001 Annex A.

The repository grows one phase at a time. Do not scaffold future phases ahead of time.

## Learning method (important)

This is a learning-by-building project. The owner writes and runs the code himself to be able to defend every line in interviews.

- Explain concepts first; provide commands/code for the owner to execute — do not batch-execute multi-step workflows on his behalf.
- Do not generate large boilerplate dumps. Build incrementally, one concept at a time.
- When asked to review output, confirm understanding before advancing.
- A reference solution exists outside this repo (`_reference/`, not committed). Never copy from it; it is only for after-the-fact comparison.

## Hard rules — Infrastructure as Code

- **Never run `terraform apply` without a reviewed `terraform plan`.**
- **Never run `terraform destroy` or delete cloud resources without explicit confirmation in the current session.**
- **OIDC only.** No static cloud credentials — never suggest `AWS_SECRET_ACCESS_KEY` in repo/CI secrets.
- Pin versions everywhere: base images, providers, modules, actions. Never `:latest`.
- Remote state with locking once Terraform is introduced; state files never committed.

## Hard rules — Cost guardrails

- Local-first: kind/k3d for daily work. Zero-cost is the default.
- AWS resources are **ephemeral**: create → validate → destroy in the same session (`make lab-down`). EKS control plane, NAT Gateways, and orphaned EIPs are the known cost traps.
- AWS Budget alert at US$20 must exist before the first `apply`.
- When proposing any AWS resource, state its cost implication.

## Hard rules — Privacy & security hygiene

- **No employer data. Ever.** No account IDs, ARNs, client names, internal code, or real findings. Everything is rebuilt from scratch.
- No secrets, tokens, `.env` files, or credentials in the repo — enforce via `.gitignore`/`.dockerignore`.
- Containers run as non-root; document security decisions.
- This is a public repository: everything committed is visible to recruiters and the internet.

## Conventions

- Code, comments, commit messages, README, and docs: **English**.
- Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`), small and frequent — no bulk dumps.
- Each phase produces: working code + a short ADR in `docs/decisions/` for significant choices.
- Makefile targets as the operational interface: `lab-up`, `lab-down`, `cost`.

## Repository structure (grows over time)

```
patrik-cloud-platform/
├── README.md            # EN, recruiter-facing
├── CLAUDE.md            # this file
├── Makefile             # lab-up / lab-down / cost
├── app/                 # Phase 1: Python app + Dockerfile + compose
├── 01-eks-platform/     # Phase 2: VPC, EKS, IRSA, ALB Ingress, HPA
├── 02-cicd-gitops/      # Phase 3: Actions (OIDC), Helm, Argo CD
├── 03-observability/    # Phase 4: prometheus-stack, dashboards, OTel
├── 04-wa-auditor/       # Python Well-Architected auditor CLI
├── 05-security/         # Phase 5: tfsec, trivy, policies
└── docs/
    ├── decisions/       # ADRs
    ├── slo.md           # SLI/SLO, error budget, postmortem
    └── compliance-map.md
```
