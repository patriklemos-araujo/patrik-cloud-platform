# Lab 10 — Amazon EKS Provisioning with Terraform

## Overview

This lab demonstrates the complete lifecycle of an Amazon EKS environment provisioned through Terraform, including infrastructure deployment, IAM integration, Kubernetes networking, application validation, self-healing, and resource cleanup.

The environment was designed as a cost-conscious, single-node learning platform. It demonstrates infrastructure automation and operational validation rather than a production-ready high-availability architecture.

**Lab status:** Completed — infrastructure destroyed and primary resources audited.

## Objectives

- Provision an Amazon EKS cluster using Terraform.
- Reuse existing AWS networking and IAM resources through Terraform Data Sources.
- Configure an S3 remote backend with state locking.
- Manage EKS add-ons explicitly through Terraform.
- Implement EKS Pod Identity for the Amazon VPC CNI.
- Provision an EKS Managed Node Group.
- Validate Kubernetes DNS, Services, and application connectivity.
- Simulate Pod failure and observe automatic recovery.
- Destroy the environment and audit residual AWS resources.

## Architecture

```text
                        Terraform
                            |
                +-----------+-----------+
                |                       |
                v                       v
          S3 Remote State         AWS Provider
          State Locking                 |
                                        v
                               Amazon EKS Cluster
                               Kubernetes v1.36
                                        |
             +--------------------------+-----------------------+
             |                          |                       |
             v                          v                       v
         IAM Roles                 EKS Add-ons           Managed Node Group
         (existing)                - VPC CNI             - EC2 t3.medium
         - Cluster Role            - CoreDNS             - AL2023
         - Node Role               - kube-proxy          - 20 GiB EBS
         - VPC CNI Role            - Pod Identity        - Desired: 1
                                                               |
                                                               v
                                                       Kubernetes Workloads
                                                               |
                                                  +------------+------------+
                                                  |                         |
                                                  v                         v
                                             NGINX Deployment       nginx-service
                                             Pod IP: dynamic        ClusterIP: stable
```

### AWS Infrastructure

| Component | Configuration |
|---|---|
| Region | us-east-1 |
| VPC | Existing VPC, `10.40.0.0/16` |
| Subnets | Two existing public subnets across us-east-1a and us-east-1b |
| Kubernetes | Amazon EKS 1.36 |
| Worker capacity | One `t3.medium` EC2 instance |
| Operating system | Amazon Linux 2023 |
| Storage | 20 GiB EBS |
| Node scaling | Minimum 1, desired 1, maximum 2 |
| Node provisioning | EKS Managed Node Group |
| IAM | Existing dedicated cluster, worker, and VPC CNI roles |
| Terraform backend | Amazon S3 |
| State locking | S3 native lockfile |

The VPC, public subnets, route tables, Internet Gateway, and IAM roles were created in an earlier lab and reused through Terraform Data Sources.

This separation allows the EKS environment to be destroyed without destroying the shared foundational infrastructure.

## Terraform Project Structure

```text
terraform-labs/
└── 10-eks-terraform/
    ├── main.tf
    ├── .terraform.lock.hcl
    └── README.md
```

Terraform-generated working directories and state files are excluded from Git.

The dependency lock file is retained to help maintain predictable provider selection.

## Remote State Configuration

The Terraform backend uses an existing S3 bucket.

```hcl
backend "s3" {
  bucket       = "patrik-terraform-state-lab-910093226300"
  key          = "eks/lab-10/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

The S3 bucket has versioning enabled.

This configuration provides:

- Centralized Terraform state storage.
- State version history.
- State locking to reduce concurrent modification risks.
- Server-side encryption requested by the backend.

The backend was initialized using:

```powershell
terraform init -reconfigure
```

The project uses AWS provider version 6.x.

For future environments, Terraform version 1.10 or later is required for the S3 `use_lockfile` functionality.

## Infrastructure Provisioning

Terraform Data Sources reference existing infrastructure, including:

- Existing VPC and subnets.
- IAM cluster role.
- IAM worker node role.
- Dedicated IAM role for the VPC CNI.

The Terraform configuration manages six resources:

1. `aws_eks_cluster.main`
2. `aws_eks_node_group.main`
3. `aws_eks_addon.vpc_cni`
4. `aws_eks_addon.coredns`
5. `aws_eks_addon.kube_proxy`
6. `aws_eks_addon.pod_identity`

### Deployment

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -lock-timeout=60s
```

Provisioning result:

```text
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
```

The EKS control plane took approximately 11 minutes to create, while the Managed Node Group took approximately 1.5 minutes.

### Bootstrap Dependencies

The EKS cluster was configured with automatic bootstrap of self-managed add-ons disabled.

The add-ons were managed explicitly through Terraform.

The dependency graph ensured that the control plane was created first, followed by the required networking and identity components.

The Managed Node Group was provisioned after the dependencies required for node initialization.

CoreDNS was created after the Managed Node Group to avoid waiting for schedulable workloads before worker capacity was available.

An important operational distinction is that successful Terraform resource creation does not, by itself, prove that Kubernetes components are healthy.

## EKS Pod Identity and IAM Security

The Amazon VPC CNI uses a dedicated IAM role rather than depending on CNI permissions attached directly to the worker node role.

The role was associated with the `aws-node` ServiceAccount.

```hcl
pod_identity_association {
  service_account = "aws-node"
  role_arn        = data.aws_iam_role.vpc_cni.arn
}
```

The role's trust policy allowed the `pods.eks.amazonaws.com` service principal to perform:

- `sts:AssumeRole`
- `sts:TagSession`

The managed `AmazonEKS_CNI_Policy` was attached to the role.

This design illustrates the separation between:

- **IAM trust policies:** Who can assume a role.
- **IAM permissions policies:** Which AWS actions the role can perform.
- **EKS Pod Identity associations:** Which Kubernetes ServiceAccount is associated with a role.

The configuration was reviewed before provisioning. Actual cluster operations confirmed that the VPC CNI was running and assigning Pod IP addresses.

## Kubernetes Cluster Validation

After provisioning, kubeconfig was updated:

```powershell
aws eks update-kubeconfig `
  --region us-east-1 `
  --name patrik-eks-lab `
  --alias patrik-eks-terraform
```

Worker node health was verified using:

```powershell
kubectl get nodes -o wide
```

The cluster reported one Ready worker node.

```text
STATUS   VERSION
Ready    v1.36.4-eks-b9510e3
```

### Add-on Health

```powershell
kubectl get pods -n kube-system -o wide
```

Observed results:

| Component | Status |
|---|---|
| Amazon VPC CNI | 2/2 Running |
| CoreDNS replica 1 | 1/1 Running |
| CoreDNS replica 2 | 1/1 Running |
| EKS Pod Identity Agent | 1/1 Running |
| kube-proxy | 1/1 Running |

All five system Pods were running with zero container restarts at the time of validation.

Both CoreDNS replicas ran on the same worker node, so the configuration did not provide worker-level high availability.

## Kubernetes DNS Validation

The cluster DNS Service was inspected using:

```powershell
kubectl get service kube-dns -n kube-system
```

Observed DNS Service:

```text
NAME       TYPE        CLUSTER-IP
kube-dns   ClusterIP   172.20.0.10
```

A temporary BusyBox Pod was used to resolve the Kubernetes API Service:

```powershell
kubectl run dns-test `
  --image=busybox:1.36 `
  --restart=Never `
  --rm -it `
  -- nslookup kubernetes.default.svc.cluster.local
```

Observed result:

```text
Server: 172.20.0.10

Name:    kubernetes.default.svc.cluster.local
Address: 172.20.0.1
```

This verified successful DNS resolution from an application Pod.

## Application Deployment

An NGINX Deployment was created to validate application scheduling and networking.

```powershell
kubectl create deployment nginx-lab `
  --image=nginx:alpine `
  --replicas=1
```

The Pod successfully reached the Running state.

Initial Pod IP:

```text
10.40.9.252
```

A ClusterIP Service was created:

```powershell
kubectl expose deployment nginx-lab `
  --name=nginx-service `
  --port=80 `
  --target-port=80 `
  --type=ClusterIP
```

The Service received the following address:

```text
172.20.185.70
```

The EndpointSlice associated the Service with the NGINX Pod:

```text
Service ClusterIP: 172.20.185.70
Pod endpoint:      10.40.9.252
```

The Service was internal to the Kubernetes cluster. No public Application Load Balancer was provisioned.

## Internal HTTP Connectivity Test

A temporary Pod was used to call the NGINX Service through Kubernetes DNS.

```powershell
kubectl run http-test `
  --image=curlimages/curl:8.12.1 `
  --restart=Never `
  --command -- `
  curl -sS -o /dev/null -w "HTTP Status: %{http_code}\n" `
  http://nginx-service.default.svc.cluster.local:80
```

The result was retrieved using:

```powershell
kubectl logs http-test
```

Observed response:

```text
HTTP Status: 200
```

This validated an end-to-end request through Kubernetes DNS resolution, ClusterIP Service routing, EndpointSlice discovery, and application HTTP response.

## Self-Healing Experiment

To test Kubernetes reconciliation, the original NGINX Pod was deliberately deleted.

```powershell
kubectl delete pod nginx-lab-b7646975-rp7h2
```

The Deployment required one replica, so its ReplicaSet created a replacement Pod automatically.

### Before and After

| Property | Original Pod | Replacement Pod |
|---|---|---|
| Pod name | `nginx-lab-b7646975-rp7h2` | `nginx-lab-b7646975-k2xj5` |
| Pod IP | `10.40.9.252` | `10.40.12.252` |
| Final status | Deleted | Running |
| Ready | 1/1 before deletion | 1/1 |
| Worker | Same EC2 worker | Same EC2 worker |

The Service ClusterIP remained unchanged:

```text
172.20.185.70
```

The EndpointSlice was automatically updated:

```text
Old endpoint: 10.40.9.252
New endpoint: 10.40.12.252
```

A second HTTP test was executed after the replacement Pod became Ready.

Observed result:

```text
HTTP Status: 200
```

### Lessons Learned

- Kubernetes controllers continuously reconcile actual state with desired state.
- Deleting a Pod managed by a Deployment does not permanently remove the application.
- Replacement Pods may receive different IP addresses.
- Services provide stable virtual addresses despite changing Pod endpoints.
- EndpointSlices reflect the current backend destinations.
- Self-healing does not guarantee zero downtime.

This experiment did not measure recovery time or request failures during the transition.

A production platform would require additional availability engineering, including multiple worker nodes, Availability Zones, application replicas, readiness probes, and workload placement policies.

## Infrastructure Cleanup

Temporary Kubernetes resources were removed after validation:

```powershell
kubectl delete pod http-test
kubectl delete pod http-recovery-test
kubectl delete deployment nginx-lab
kubectl delete service nginx-service
```

The default namespace was verified to contain no remaining test workloads.

Terraform destruction was reviewed before execution:

```powershell
terraform plan -destroy
```

Expected and observed plan:

```text
Plan: 0 to add, 0 to change, 6 to destroy.
```

The environment was destroyed using:

```powershell
terraform destroy -lock-timeout=60s
```

Final result:

```text
Destroy complete! Resources: 6 destroyed.
```

The shared VPC, public subnets, routing infrastructure, Internet Gateway, and IAM roles were intentionally preserved.

## Post-Destroy AWS Audit

A manual audit was performed after the Terraform destroy operation.

| AWS Resource | Audit Result |
|---|---|
| EKS clusters | None remaining in us-east-1 |
| Non-terminated EC2 instances | None |
| EBS volumes | None |
| Auto Scaling Groups | None |
| EKS CloudWatch Log Group | Residual group identified and deleted |
| Terraform managed resources | State listing returned no resources |

The residual CloudWatch Log Group was:

```text
/aws/eks/patrik-eks-lab/cluster
```

It had no retention period configured and was manually deleted after confirming that the laboratory evidence had been collected.

The S3 state bucket and its version history were preserved.

This audit illustrates why deleting Terraform-managed resources does not automatically guarantee that every related cloud resource has been removed.

## Cost Optimization and FinOps

The lab was intentionally designed to limit infrastructure costs:

- One on-demand `t3.medium` worker.
- Two existing public subnets.
- No NAT Gateway.
- No Application Load Balancer.
- No additional database service.
- Existing VPC and IAM resources reused.
- Cleanup performed after validation.

The approximate baseline was US$0.15 per hour while the cluster and single worker were active, excluding variable charges.

Actual AWS billing was not independently reconciled as part of this lab.

CloudWatch Logs, EBS, public IPv4 addresses, network traffic, and other usage can contribute additional charges.

Cost optimization includes not only resource selection but also lifecycle controls, identifying residual resources, and validating cleanup.

## Production Considerations

This environment was designed for learning and must not be treated as a production-ready Kubernetes platform.

For workloads supporting financial systems or critical business services, the architecture should be extended with:

- Private worker subnets across multiple Availability Zones.
- High availability across multiple worker nodes.
- Application replicas and topology-aware scheduling.
- Restricted Kubernetes API access.
- Controlled ingress and load balancing.
- Automated CI/CD and deployment approvals.
- Container image and dependency scanning.
- Secrets management and workload-level IAM isolation.
- Metrics, logs, distributed tracing, and actionable alerts.
- Defined availability objectives, recovery objectives, and incident response procedures.
- Backup and disaster recovery validation.
- Cost allocation, logging retention, and security governance.

### Key Reliability Distinctions

**Self-healing:** Kubernetes automatically replaces failed or deleted Pods.

**High availability:** The application remains available despite selected infrastructure or application failures.

**Disaster recovery:** The organization can restore services following significant disruptions within defined RTO and RPO targets.

These capabilities require different architectural decisions and testing strategies.

## Key Takeaways

This lab provided hands-on practice in:

1. Provisioning and destroying EKS infrastructure with Terraform.
2. Managing Terraform state remotely with S3.
3. Reusing infrastructure through Data Sources.
4. Managing EKS add-ons and their dependencies.
5. Separating Kubernetes service identities from worker IAM roles.
6. Understanding VPC CNI Pod networking.
7. Validating DNS and application connectivity.
8. Inspecting Kubernetes EndpointSlices.
9. Demonstrating Deployment self-healing.
10. Performing post-destroy AWS resource audits.

## Next Steps

The next planned lab will extend this foundation by deploying an application with Helm and integrating Kubernetes ingress with the AWS Load Balancer Controller.

Additional work will address automated deployment workflows, observability, security, and reliability engineering.

These exercises support the broader goal of developing practical Senior Cloud, DevOps, and Platform Engineering competencies.

---

**Project:** Patrik Cloud Platform  
**Lab:** 10 — Amazon EKS with Terraform  
**Status:** Completed and cleaned up  
**Platform:** AWS / EKS / Terraform / Kubernetes  
