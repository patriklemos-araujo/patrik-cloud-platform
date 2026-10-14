# Lab 07 — Amazon ECR + ECS Fargate + GitHub Actions CI/CD

## Objective

Build an end-to-end container deployment pipeline on AWS using:

- Docker
- Amazon ECR
- Amazon ECS
- AWS Fargate
- Application Load Balancer
- GitHub Actions
- GitHub OIDC
- AWS IAM
- Terraform
- CloudWatch Logs

The goal of this lab was to understand how an application moves from a Git commit to a running container in AWS without manually deploying the application.

---

# Architecture

Internet
   |
   v
Application Load Balancer
   |
   v
Target Group
   |
   v
ECS Service
   |
   v
ECS Fargate Task
   |
   v
Docker Container / NGINX

CI/CD:

Developer
   |
   | git push
   v
GitHub
   |
   v
GitHub Actions
   |
   | OIDC
   v
AWS STS
   |
   v
Temporary AWS Credentials
   |
   +----------------------+
   |                      |
   v                      v
Docker Build          Amazon ECS
   |                      |
   v                      |
Amazon ECR                |
   |                      |
   +------ Image SHA -----+
                          |
                          v
                 New Task Definition
                          |
                          v
                    ECS Service
                          |
                          v
                    Fargate Task

---

# Infrastructure

Terraform provisions the base AWS infrastructure.

Resources created:

- Amazon ECR Repository
- ECS Cluster
- ECS Task Definition
- ECS Service
- AWS Fargate configuration
- Application Load Balancer
- Target Group
- HTTP Listener
- VPC
- Internet Gateway
- Public Subnets in two Availability Zones
- Route Table
- Security Groups
- CloudWatch Log Group
- ECS Task Execution IAM Role
- GitHub Actions IAM Role
- IAM Policies

Region:

us-east-1

---

# Network Architecture

VPC:

10.30.0.0/16

Public Subnet A:

10.30.1.0/24
us-east-1a

Public Subnet B:

10.30.2.0/24
us-east-1b

Architecture:

Internet
   |
   v
Internet Gateway
   |
   v
Application Load Balancer
   |
   | HTTP :80
   v
ALB Security Group
   |
   v
ECS Security Group
   |
   | HTTP :80
   v
Fargate Task

The ECS Security Group accepts HTTP traffic only from the ALB Security Group.

The application container is therefore not directly exposed to inbound internet traffic through its Security Group.

For this lab, Fargate tasks used public IP addresses to avoid the cost of a NAT Gateway.

In a production architecture, the ECS tasks would normally run in private subnets.

---

# Application

The application is a simple HTML page served by NGINX.

Files:

app/
├── Dockerfile
└── index.html

Dockerfile:

FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

The Docker image packages the application and the NGINX runtime.

---

# Amazon ECR

Amazon Elastic Container Registry was used as the private container registry.

Repository:

patrik-cloud-platform-app

The first image was manually pushed with the tag:

v1

Later the CI/CD pipeline started using the Git commit SHA as the image tag.

Example:

patrik-cloud-platform-app:cb6411384b11982347a654385e913070674083c5

This provides traceability between:

Git Commit
   |
   v
Docker Image
   |
   v
ECR Tag
   |
   v
ECS Task Definition
   |
   v
Running Application

---

# Why use the Git SHA as an image tag?

Using the Git SHA allows us to identify exactly which code version is running.

Example:

Git commit:

cb6411384b11982347a654385e913070674083c5

ECR image:

patrik-cloud-platform-app:cb6411384b11982347a654385e913070674083c5

Task Definition:

patrik-cloud-platform-app:2

This improves:

- Traceability
- Troubleshooting
- Auditing
- Rollbacks
- Deployment history

---

# ECS Task Definition

The Task Definition describes how the container should run.

Configuration used:

CPU:

256

Memory:

512 MB

Network Mode:

awsvpc

Compatibility:

FARGATE

Container Port:

80

Logging:

awslogs

CloudWatch Log Group:

/ecs/patrik-cloud-platform-app

The Task Definition can be considered the runtime recipe for the container.

It defines:

- Docker image
- CPU
- Memory
- Network configuration
- Ports
- IAM roles
- Logging

---

# ECS Service

The ECS Service maintains the desired number of running tasks.

Configuration:

desired_count = 1

Conceptually:

Task Definition
=
How the container should run

Task
=
A running instance of the Task Definition

ECS Service
=
Maintains the desired number of Tasks

If the running task stops unexpectedly, ECS creates another task to maintain the desired state.

---

# AWS Fargate

AWS Fargate provides the compute capacity required to run the containers.

With Fargate, there is no need to manage:

- EC2 instances
- Operating systems
- AMIs
- Instance patching
- ECS worker capacity

Architecture:

ECS
   |
   | requests a task
   v
Fargate
   |
   | allocates CPU and RAM
   v
Container

---

# Application Load Balancer

The Application Load Balancer is the public entry point for the application.

Flow:

Internet
   |
   v
ALB
   |
   v
Target Group
   |
   v
Fargate Task

The target group uses:

target_type = ip

This is required because Fargate tasks using awsvpc networking receive their own network interfaces and IP addresses.

---

# Health Checks

The Target Group performs health checks against:

/

Expected response:

HTTP 200

If a task becomes unhealthy, the ALB stops routing traffic to it.

Flow:

ALB
   |
   | GET /
   v
Fargate Task
   |
   | HTTP 200
   v
Healthy

---

# CloudWatch Logs

Container logs are sent to CloudWatch using the awslogs log driver.

Flow:

Application stdout/stderr
   |
   v
Docker
   |
   v
awslogs driver
   |
   v
CloudWatch Logs

Log Group:

/ecs/patrik-cloud-platform-app

Retention:

7 days

---

# GitHub Actions

The pipeline automatically builds and deploys the application.

Workflow:

.github/workflows/ecr-build-push.yml

Pipeline stages:

Checkout Repository
        |
        v
Configure AWS Credentials
        |
        v
Login to Amazon ECR
        |
        v
Docker Build
        |
        v
Docker Tag
        |
        v
Docker Push
        |
        v
Render ECS Task Definition
        |
        v
Register New Task Definition
        |
        v
Update ECS Service
        |
        v
Wait for ECS Service Stability

---

# GitHub OIDC Authentication

The GitHub Actions pipeline authenticates to AWS using OpenID Connect.

No permanent AWS access keys are stored in GitHub.

Authentication flow:

GitHub Actions
      |
      | requests OIDC token
      v
GitHub OIDC Provider
      |
      v
AWS STS
      |
      | AssumeRoleWithWebIdentity
      v
Temporary AWS Credentials
      |
      v
AWS APIs

This is more secure than storing:

AWS_ACCESS_KEY_ID

and:

AWS_SECRET_ACCESS_KEY

inside GitHub Secrets.

---

# OIDC Troubleshooting

The first pipeline execution failed with:

Not authorized to perform sts:AssumeRoleWithWebIdentity

The GitHub OIDC subject expected by the IAM trust policy did not match the token subject generated by the repository.

The initial subject used:

repo:patriklemos-araujo/patrik-cloud-platform:...

The repository was configured to use a customized subject containing the GitHub owner and repository IDs.

The working format was:

repo:patriklemos-araujo@273424479/patrik-cloud-platform@1340041154:...

The IAM trust relationship was updated and the pipeline successfully authenticated using OIDC.

This demonstrated an important troubleshooting principle:

When OIDC AssumeRole fails, verify:

- OIDC Provider
- audience claim
- subject claim
- IAM trust policy
- repository
- branch
- GitHub OIDC subject customization

---

# IAM Permissions

The GitHub Actions IAM role follows the principle of least privilege.

The role can authenticate to ECR and push images.

Important ECR actions included:

- ecr:GetAuthorizationToken
- ecr:BatchCheckLayerAvailability
- ecr:GetDownloadUrlForLayer
- ecr:BatchGetImage
- ecr:InitiateLayerUpload
- ecr:UploadLayerPart
- ecr:CompleteLayerUpload
- ecr:PutImage

For ECS deployment, the pipeline received permissions including:

- ecs:RegisterTaskDefinition
- ecs:DescribeTaskDefinition
- ecs:DescribeServices
- ecs:UpdateService

---

# iam:PassRole

The GitHub Actions role also requires:

iam:PassRole

Why?

The pipeline registers a new ECS Task Definition containing the ECS Task Execution Role.

AWS therefore verifies whether GitHub Actions has permission to pass this role to ECS.

Flow:

GitHub Actions Role
       |
       | RegisterTaskDefinition
       v
ECS
       |
       | needs execution role
       v
patrik-ecs-task-execution-role

The permission is restricted to:

ecs-tasks.amazonaws.com

This prevents the GitHub role from passing the role to unrelated AWS services.

---

# ECS Task Execution Role

The ECS Task Execution Role is used by the ECS platform.

It allows ECS to perform operations such as:

- Pulling images from ECR
- Sending logs to CloudWatch

This is different from a Task Role.

Execution Role:

Used by ECS/Fargate infrastructure.

Task Role:

Used by the application running inside the container.

This application did not require a Task Role because it did not directly access AWS APIs.

---

# Terraform vs GitHub Actions Responsibility

An important architectural decision in this lab was separating infrastructure management from application deployment.

Terraform manages:

- VPC
- Subnets
- Internet Gateway
- Security Groups
- ALB
- Target Group
- ECS Cluster
- ECS Service
- Base Task Definition
- IAM
- ECR
- CloudWatch

GitHub Actions manages:

- Docker builds
- Docker image publishing
- Application Task Definition revisions
- ECS application deployments

Without this separation, Terraform could attempt to roll back the Task Definition deployed by GitHub Actions.

To prevent this conflict, the ECS Service uses:

lifecycle {
  ignore_changes = [
    task_definition
  ]
}

This tells Terraform not to revert application Task Definition revisions created by the deployment pipeline.

---

# CI vs CD

Initially the pipeline implemented CI only.

Flow:

Git Push
   |
   v
GitHub Actions
   |
   v
Docker Build
   |
   v
ECR Push

After completing the deployment stage, the pipeline became CI/CD.

Flow:

Git Push
   |
   v
GitHub Actions
   |
   v
Docker Build
   |
   v
ECR Push
   |
   v
New Task Definition
   |
   v
ECS Service Update
   |
   v
Fargate Deployment

---

# End-to-End Deployment Test

The application HTML was modified.

After running:

git add

git commit

git push

no manual AWS deployment command was executed.

GitHub Actions automatically:

1. Checked out the new commit.
2. Authenticated to AWS through OIDC.
3. Built the Docker image.
4. Tagged the image with the Git SHA.
5. Pushed the image to ECR.
6. Rendered the ECS Task Definition.
7. Registered a new Task Definition revision.
8. Updated the ECS Service.
9. Started a new Fargate Task.
10. Waited for the ECS Service to stabilize.

The ECS Service moved to:

patrik-cloud-platform-app:3

Validation showed:

runningCount = 1

pendingCount = 0

rolloutState = COMPLETED

---

# Application Validation

The application was tested through the ALB.

Response:

HTTP 200 OK

The new HTML contained:

Deployed automatically with GitHub Actions

This confirmed the complete deployment path:

Code Change
     |
     v
Git Commit
     |
     v
Git Push
     |
     v
GitHub Actions
     |
     v
Docker Image
     |
     v
Amazon ECR
     |
     v
Task Definition
     |
     v
ECS Service
     |
     v
Fargate
     |
     v
ALB
     |
     v
User

---

# Troubleshooting Strategy

A useful troubleshooting model for this architecture is:

Pipeline authentication problem?

Check:

GitHub Actions
OIDC
IAM Trust Policy
STS

---

Image problem?

Check:

Docker build
ECR login
ECR push
image tag

---

Task does not start?

Check:

Task Definition
ECR image
Execution Role
CPU
Memory
Networking
ECS Service Events

---

Task starts but Target Group is unhealthy?

Check:

Application port
Security Groups
Target Group
Health Check path
Container status

---

Target is healthy but application is unavailable?

Check:

ALB
Listener
Route Table
Security Groups

---

Application error?

Check:

CloudWatch Logs

---

# Production Improvements

The lab intentionally uses a simplified and cost-conscious architecture.

A production architecture could evolve toward:

Internet
   |
   v
Route 53
   |
   v
AWS WAF
   |
   v
HTTPS ALB
   |
   v
Private Subnets
   |
   v
ECS Fargate
   |
   +----------------+
   |                |
Secrets Manager   RDS / AWS Services

Possible improvements:

- HTTPS with ACM
- Route 53
- AWS WAF
- Private ECS subnets
- Auto Scaling
- CloudWatch alarms
- Secrets Manager
- SSM Parameter Store
- ECR image retention policies
- Immutable image tags
- Blue/Green deployment
- Canary deployment
- Multiple ECS tasks
- Deployment rollback strategies
- VPC endpoints
- Remote Terraform state

---

# Cost Management

This lab intentionally avoided a NAT Gateway because it would add unnecessary cost.

The main billable resources during the lab were:

- Application Load Balancer
- ECS Fargate Task

After completing the lab, all application images were removed from ECR and Terraform destroyed the infrastructure.

Terraform result:

Destroy complete! Resources: 23 destroyed.

Final validation:

terraform state list

Result:

empty

ECS clusters:

[]

Application Load Balancers:

[]

ECR repositories:

[]

This confirmed that the billable Lab 07 infrastructure had been removed.

---

# Key Lessons

This lab demonstrated how multiple DevOps and AWS components work together.

Main concepts practiced:

- Infrastructure as Code
- Containers
- Container Registry
- Container Orchestration
- Serverless Containers
- Load Balancing
- IAM Least Privilege
- OIDC Federation
- Temporary Credentials
- CI/CD
- Git-based Traceability
- ECS Task Definition revisions
- Health Checks
- CloudWatch Logging
- Terraform lifecycle management
- Troubleshooting
- Cost-aware cloud architecture

---

# Interview Summary

A concise explanation of the architecture:

"When an application change is pushed to GitHub, GitHub Actions starts the CI/CD pipeline. The workflow authenticates to AWS using OIDC, avoiding permanent AWS access keys. It builds the Docker image, tags it using the Git commit SHA and pushes it to Amazon ECR.

The pipeline then renders and registers a new ECS Task Definition revision containing the new image and updates the ECS Service. AWS Fargate starts the new container without requiring EC2 instance management.

The application is exposed through an Application Load Balancer. The Target Group performs health checks against the Fargate task and sends traffic only to healthy targets.

Container logs are sent to CloudWatch Logs.

Terraform manages the base infrastructure while GitHub Actions manages application deployment revisions."

---

# Lab Status

Completed.

Final result:

Git Push
   |
   v
GitHub Actions
   |
   v
OIDC Authentication
   |
   v
Docker Build
   |
   v
Amazon ECR
   |
   v
ECS Task Definition
   |
   v
ECS Service
   |
   v
AWS Fargate
   |
   v
Application Load Balancer
   |
   v
HTTP 200 OK

CI/CD deployment successfully validated end-to-end.