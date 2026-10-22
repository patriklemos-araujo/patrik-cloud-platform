\# Lab 11 — Amazon EKS, Helm \& Application Load Balancer



\## Overview



This lab demonstrates how to deploy a containerized application on Amazon EKS and expose it through an internet-facing AWS Application Load Balancer (ALB), using the AWS Load Balancer Controller installed with Helm.



The infrastructure was managed with Terraform, while the controller obtained AWS permissions through EKS Pod Identity instead of static access keys.



The deployment was successfully validated with an external HTTP `200 OK` response and a healthy ALB target.



All lab-specific resources were subsequently cleaned up to minimize ongoing AWS costs.



\## Architecture



```text

&#x20;                  Internet

&#x20;                     |

&#x20;                     v

&#x20;         Application Load Balancer

&#x20;              HTTP Listener :80

&#x20;                     |

&#x20;                     v

&#x20;             AWS Target Group

&#x20;                Target Type: IP

&#x20;                Health: healthy

&#x20;                     |

&#x20;                     v

&#x20;              Kubernetes Pod

&#x20;                 NGINX :80

&#x20;                     |

&#x20;              Kubernetes Service

&#x20;                ClusterIP :80



&#x20;   +--------------------------------------+

&#x20;   |              Amazon EKS              |

&#x20;   |                                      |

&#x20;   |  AWS Load Balancer Controller        |

&#x20;   |           (Helm)                     |

&#x20;   |               |                      |

&#x20;   |         EKS Pod Identity             |

&#x20;   |               |                      |

&#x20;   |            IAM Role                  |

&#x20;   +--------------------------------------+



&#x20;          Terraform-managed resources

```



The AWS Load Balancer Controller watches Kubernetes Ingress resources and reconciles the corresponding AWS load balancing infrastructure.



With `target-type: ip`, the ALB forwards requests directly to the application's Pod IP addresses.



\## Technology Stack



| Component | Technology |

|---|---|

| Cloud platform | Amazon Web Services |

| Container orchestration | Amazon EKS |

| Infrastructure as Code | Terraform |

| Kubernetes version | 1.36 |

| Compute | EKS Managed Node Group — `t3.medium` |

| Package management | Helm |

| Ingress integration | AWS Load Balancer Controller |

| Authentication | EKS Pod Identity |

| Authorization | AWS IAM |

| Load balancing | AWS Application Load Balancer |

| Application | NGINX Alpine |

| Region | `us-east-1` |



\## Repository Files



```text

11-eks-helm-alb/

├── main.tf

├── .terraform.lock.hcl

├── iam\_policy.json

├── values-alb-controller.yaml

├── ingress-nginx.yaml

└── README.md

```



The `.terraform/` directory and generated Helm templates in `rendered/` are local artifacts and should not be committed.



\## Infrastructure Provisioning



The Terraform configuration provisions:



\- Amazon EKS cluster

\- EKS Managed Node Group

\- Amazon VPC CNI, CoreDNS, kube-proxy and EKS Pod Identity Agent add-ons

\- IAM policy and role for AWS Load Balancer Controller

\- IAM role policy attachment

\- EKS Pod Identity association for the controller



The lab reuses an existing VPC, public subnets and shared EKS IAM roles.



These shared resources are read through Terraform data sources and must not be destroyed as part of this lab.



\### Terraform commands



```bash

terraform init

terraform validate

terraform plan

terraform apply

```



Before running these commands, verify the configured AWS account, region, Terraform backend, network IDs and existing IAM roles.



\## AWS Load Balancer Controller



The AWS Load Balancer Controller was installed through the official EKS Helm chart.



Chart version: `1.14.1`

Controller version: `v2.14.1`



The configuration is stored in `values-alb-controller.yaml`.



\### Helm installation



```bash

helm repo add eks https://aws.github.io/eks-charts

helm repo update



helm upgrade --install aws-load-balancer-controller \\

&#x20; eks/aws-load-balancer-controller \\

&#x20; --version 1.14.1 \\

&#x20; --namespace kube-system \\

&#x20; --values values-alb-controller.yaml \\

&#x20; --wait \\

&#x20; --timeout 5m

```



\### AWS authentication with EKS Pod Identity



The controller runs under the Kubernetes ServiceAccount:



`kube-system/aws-load-balancer-controller`



Terraform creates an EKS Pod Identity association connecting this ServiceAccount to an IAM role.



The trust policy allows the service principal `pods.eks.amazonaws.com` to assume the role.



This approach avoids embedding long-lived AWS credentials in Kubernetes manifests or container images.



The IAM permissions follow the AWS Load Balancer Controller policy for the selected controller version.



\## NGINX Deployment



The test application was deployed with the following commands:



```bash

kubectl create deployment nginx-lab11 \\

&#x20; --image=nginx:alpine \\

&#x20; --replicas=1



kubectl expose deployment nginx-lab11 \\

&#x20; --name=nginx-service \\

&#x20; --port=80 \\

&#x20; --target-port=80 \\

&#x20; --type=ClusterIP

```



The Service exposes port 80 internally to the cluster.



An Ingress resource, defined in `ingress-nginx.yaml`, instructs the AWS Load Balancer Controller to provision an internet-facing ALB.



Important Ingress settings:



\- `ingressClassName: alb`

\- `alb.ingress.kubernetes.io/scheme: internet-facing`

\- `alb.ingress.kubernetes.io/target-type: ip`

\- `alb.ingress.kubernetes.io/healthcheck-path: /`

\- HTTP listener on port 80



Apply the Ingress:



```bash

kubectl apply -f ingress-nginx.yaml

```



Retrieve the ALB endpoint:



```bash

kubectl get ingress nginx-ingress

```



\## Validation Results



The following tests were performed successfully:



| Validation | Result |

|---|---|

| EKS worker node | Ready |

| AWS Load Balancer Controller | Running |

| Helm release | Deployed |

| NGINX Pod | Running |

| Kubernetes Service endpoints | Populated |

| ALB creation | Successful |

| ALB target type | `ip` |

| Target Group health | `healthy` |

| External HTTP request | `200 OK` |



The observed target IP was `10.40.20.204`, with traffic forwarded to port `80`.



The ALB DNS name was generated automatically by AWS. Because the infrastructure was deleted after testing, the original endpoint is no longer expected to be accessible.



\### HTTP validation



```bash

curl -I http://<ALB\_DNS\_NAME>/

```



Expected result:



```text

HTTP/1.1 200 OK

```



\### Target health validation



```bash

aws elbv2 describe-target-health \\

&#x20; --target-group-arn <TARGET\_GROUP\_ARN> \\

&#x20; --region us-east-1

```



The registered target was confirmed as `healthy`.



\## Security and Architecture Decisions



\### 1. EKS Pod Identity



Used to provide temporary AWS credentials to the load balancer controller without distributing static access keys.



\### 2. Cluster access restrictions



The EKS API endpoint was configured with public and private access, while public access was restricted to a specific `/32` CIDR during the lab.



\### 3. Reusing existing networking



The lab reused an existing VPC and public subnets to avoid unnecessary infrastructure duplication.



\### 4. IP-based targeting



With `target-type: ip`, the ALB sends traffic directly to Pod IPs instead of using instance targets through Kubernetes NodePorts.



\### 5. Version pinning



The Helm chart version was explicitly pinned to support reproducibility and reduce unexpected changes.



\## FinOps and Cleanup



The infrastructure included billable AWS resources, including the EKS control plane, EC2 worker, EBS storage and Application Load Balancer.



Cleanup was performed in dependency order to allow the AWS Load Balancer Controller to remove its AWS-managed resources before the EKS cluster was destroyed.



\### Cleanup sequence



```bash

kubectl delete -f ingress-nginx.yaml

```



Confirm that the ALB and Target Group have been removed.



```bash

kubectl delete deployment/nginx-lab11 \\

&#x20; service/nginx-service \\

&#x20; --ignore-not-found

```



Uninstall the controller:



```bash

helm uninstall aws-load-balancer-controller \\

&#x20; --namespace kube-system

```



Review the Terraform destroy plan:



```bash

terraform plan -destroy

```



Destroy the lab infrastructure:



```bash

terraform destroy

```



Terraform completed successfully with:



```text

Destroy complete! Resources: 10 destroyed.

```



\### Post-destroy audit



The following checks were completed:



\- EKS cluster was absent

\- Worker EC2 instance was `terminated`

\- ALB and Target Group were absent

\- No detached EBS volumes were returned by the regional query

\- Residual EKS CloudWatch Log Group was identified and deleted

\- Temporary subnet discovery tags were removed from both shared public subnets



The Terraform backend bucket, existing VPC, shared subnets and shared IAM roles were intentionally preserved.



\## Lessons Learned



1\. Terraform state does not automatically include resources dynamically created by Kubernetes controllers.

2\. Kubernetes Ingress deletion should precede EKS and controller deletion so that AWS load balancing resources are cleaned up properly.

3\. EKS Pod Identity provides a practical alternative to static credentials for AWS-aware controllers.

4\. Helm values should explicitly configure cluster-specific information such as cluster name, region and VPC ID.

5\. Post-destroy audits are essential to identify resources outside Terraform state.

6\. Shared networking components require special care during cleanup.



\## Production Considerations



This was a cost-conscious learning environment, not a production reference architecture.



For production workloads, improvements would include:



\- Multiple worker nodes distributed across Availability Zones

\- Private subnets for workload compute

\- HTTPS with ACM certificates

\- DNS integration with Amazon Route 53

\- Stronger resource requests, limits and autoscaling policies

\- Centralized logging, monitoring and alerting

\- More restrictive IAM policies and network access controls

\- Automated deployment and teardown pipelines

\- Defined recovery and availability requirements



\## Outcome



Successfully provisioned an EKS environment using Terraform, installed AWS Load Balancer Controller through Helm, configured AWS access with EKS Pod Identity, published NGINX through an Application Load Balancer, confirmed healthy targets and HTTP 200 responses, and safely destroyed the lab infrastructure.



The project demonstrates practical experience with Kubernetes, AWS networking, IAM, Helm, Terraform, troubleshooting and FinOps.
