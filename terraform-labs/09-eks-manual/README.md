
# Lab 09 — Amazon EKS: Manual Provisioning and Kubernetes Operations

## Overview

This lab explores Amazon Elastic Kubernetes Service (EKS) through manual provisioning using the AWS Management Console and operational validation using AWS CLI and kubectl.

The goal was to understand how an EKS control plane, EC2 managed node groups, IAM, VPC networking, Kubernetes workloads, and service discovery work together before automating the infrastructure with Terraform.

## Architecture

```text
Developer Workstation
       |
       | kubectl + AWS IAM authentication
       v
Amazon EKS Control Plane (Kubernetes 1.36)
       |
       | Kubernetes API
       v
Managed Node Group
       |
       v
Amazon EC2 (t3.medium / Amazon Linux 2023)
       |
       +-- VPC CNI
       +-- kube-proxy
       +-- EKS Pod Identity Agent
       +-- CoreDNS Pods
       |
       +-- Namespace: lab-eks
               |
               +-- NGINX Deployment
               |       |
               |       +-- NGINX Pod
               |
               +-- nginx-service (ClusterIP)
                       |
                       +-- EndpointSlice
```

## AWS Infrastructure

- Region: us-east-1
- EKS cluster: patrik-eks-lab
- Kubernetes version: 1.36
- EKS Auto Mode: Disabled
- VPC CIDR: 10.40.0.0/16
- Public subnet in us-east-1a: 10.40.0.0/20
- Public subnet in us-east-1b: 10.40.16.0/20
- Public and private Kubernetes API endpoints
- Public API access restricted to the workstation's public IPv4 /32
- Managed node group with one t3.medium instance
- Desired capacity: 1
- Minimum capacity: 1
- Maximum capacity: 2
- On-Demand capacity
- 20 GiB node disk
- SSH access disabled

Public subnets were used to avoid NAT Gateway costs in this temporary learning environment.

For production environments, private worker subnets, controlled egress, and multiple worker nodes across Availability Zones should be evaluated.

## IAM and Security

Two separate IAM roles were used:

- patrik-eks-cluster-role — EKS control plane
- patrik-eks-node-role — EC2 worker nodes

Node role permissions included:

- AmazonEKSWorkerNodePolicy
- AmazonEC2ContainerRegistryPullOnly

EKS Pod Identity was configured for the Amazon VPC CNI add-on using a dedicated IAM role.

Cluster authentication used EKS API mode, with cluster administrator bootstrap access enabled.

Five EKS control plane log types were enabled:

- API server
- Audit
- Authenticator
- Controller manager
- Scheduler

## Kubernetes Add-ons

The following managed add-ons were installed:

- Amazon VPC CNI
- CoreDNS
- kube-proxy
- EKS Pod Identity Agent

All five observed system Pods were running successfully on the worker node, including two CoreDNS replicas.

## Workload Deployment

A dedicated namespace was created:

```powershell
kubectl create namespace lab-eks
```

NGINX was deployed with one replica:

```powershell
kubectl create deployment nginx `
  --image=nginx:stable `
  --replicas=1 `
  -n lab-eks
```

A ClusterIP Service was created:

```powershell
kubectl expose deployment nginx `
  --name=nginx-service `
  --port=80 `
  --target-port=80 `
  --type=ClusterIP `
  -n lab-eks
```

The following resources were validated:

- Deployment
- ReplicaSet
- Pod
- Service
- EndpointSlice

## VPC CNI Networking

The worker node received a private IP address from the AWS VPC.

The NGINX Pod also received a VPC IP address through the Amazon VPC CNI.

Observed example:

```text
Worker Node:    10.40.31.129
NGINX Pod:      10.40.17.189
Service IP:     172.20.205.245
```

The Pod IP belonged to the VPC CIDR, while the Service IP belonged to the Kubernetes Service CIDR (172.20.0.0/16).

This demonstrated the difference between pod networking and virtual Kubernetes Service addressing.

## Internal Service Connectivity

The NGINX Service was inspected:

```powershell
kubectl get svc,endpointslices -n lab-eks -o wide
```

HTTP connectivity was first verified through kubectl port-forward.

Then a temporary curl Pod tested DNS resolution and actual in-cluster Service access.

Result:

```text
HTTP Status: 200
```

This validated internal DNS, Service routing, and Pod networking.

## Self-Healing Test

The NGINX Pod was manually deleted while the Deployment maintained one desired replica.

The ReplicaSet automatically created a replacement Pod.

Observed:

```text
Original Pod IP:    10.40.17.189
Replacement Pod IP: 10.40.31.78
```

The Service ClusterIP remained unchanged:

```text
172.20.205.245
```

The EndpointSlice was automatically updated to point to the replacement Pod.

This demonstrated Kubernetes reconciliation and workload self-healing.

With only one replica, the deployment was not highly available and could experience brief downtime during Pod replacement.

## Troubleshooting Exercise — Service Selector Mismatch

A controlled networking incident was introduced by modifying the Service selector:

```powershell
kubectl patch service nginx-service `
  -n lab-eks `
  --type=merge `
  -p '{"spec":{"selector":{"app":"nginx-incorrect"}}}'
```

The NGINX Pod remained healthy, but the Service no longer selected it.

Diagnosis:

```powershell
kubectl describe service nginx-service -n lab-eks
```

The output showed an incorrect selector and no endpoints.

Root cause:

```text
Service selector: app=nginx-incorrect
Pod label:        app=nginx

Result: No matching endpoints
```

The selector was corrected:

```powershell
kubectl patch service nginx-service `
  -n lab-eks `
  --type=merge `
  -p '{"spec":{"selector":{"app":"nginx"}}}'
```

The EndpointSlice was automatically restored, and a new internal HTTP test returned:

```text
HTTP Status: 200
```

### Key SRE Lesson

A Pod showing Running or Ready does not automatically guarantee successful application connectivity.

Service selectors, EndpointSlices, DNS resolution, networking rules, and application responses must also be validated.

## Cleanup and Cost Control

The following resources were removed after validation:

- lab-eks namespace and workloads
- EKS Managed Node Group
- EKS Cluster
- EKS CloudWatch Log Group

Deletion was confirmed using AWS CLI waiters.

Additional regional checks confirmed no remaining:

- Active or stopped EC2 instances
- EBS volumes
- Auto Scaling Groups
- Amazon Managed Prometheus scrapers

The existing VPC, subnets, route tables, Internet Gateway, and reusable IAM roles were intentionally preserved for future labs.

These checks covered the principal resources used by this lab, not a complete AWS account-wide billing audit.

## Key Learnings

1. EKS separates the AWS-managed control plane from worker compute.
2. Managed Node Groups provide lifecycle management for EC2 Kubernetes workers.
3. Amazon VPC CNI integrates Pod IP addressing with AWS VPC networking.
4. ClusterIP Services provide stable internal virtual addresses.
5. EndpointSlices track available Service backends.
6. Kubernetes controllers reconcile actual state toward declared desired state.
7. Pod self-healing is not equivalent to application high availability.
8. Service selector misconfiguration can cause connectivity failures even when Pods are healthy.
9. AWS IAM and Kubernetes authorization serve distinct responsibilities.
10. Cost-aware cleanup is an essential part of cloud engineering workflows.

## Next Lab

Lab 10 — Amazon EKS with Terraform

The next lab will focus on reproducible EKS provisioning with Infrastructure as Code, validation, and automated cleanup.
