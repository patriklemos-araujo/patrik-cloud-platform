# Lab 04 - AWS Networking with Terraform

This lab demonstrates a practical AWS networking setup using Terraform.

The goal was to understand the core networking components used in day-to-day DevOps and Cloud Engineering work, deploy a real EC2 workload, validate connectivity, perform controlled troubleshooting, and observe the instance using Amazon CloudWatch.

---

## Architecture

The lab uses the following architecture:

Internet
   |
   v
Internet Gateway
   |
   v
VPC 10.10.0.0/16
│
├── Public Subnet
│   10.10.1.0/24
│   us-east-1a
│   map_public_ip_on_launch = true
│      |
│      v
│   Public Route Table
│   ├── 10.10.0.0/16 -> local
│   └── 0.0.0.0/0 -> Internet Gateway
│      |
│      v
│   EC2 Spot t3.micro
│   Amazon Linux 2023
│   nginx installed using user_data
│   HTTP/80
│
└── Private Subnet
    10.10.2.0/24
    us-east-1b
    no public IP
       |
       v
    Private Route Table
    └── 10.10.0.0/16 -> local

The EC2 instance is monitored through Amazon CloudWatch.

---

## Technologies

- Terraform
- AWS VPC
- AWS Subnets
- Internet Gateway
- Route Tables
- Security Groups
- Amazon EC2
- EC2 Spot Instances
- Amazon Linux 2023
- Nginx
- Amazon CloudWatch
- AWS CLI

---

## Main Learning Goals

This lab was designed to practice:

- Creating a VPC using Infrastructure as Code
- Understanding public and private subnets
- Understanding route tables
- Understanding Internet Gateway connectivity
- Understanding Security Groups
- Deploying an EC2 instance
- Using Spot Instances for lower-cost labs
- Installing software using EC2 user data
- Validating application connectivity
- Performing controlled networking troubleshooting
- Reading CloudWatch metrics
- Creating a CloudWatch alarm
- Keeping cloud lab costs low
- Destroying temporary infrastructure after validation

---

## VPC

The VPC uses the following CIDR:

10.10.0.0/16

Terraform also enables:

enable_dns_support   = true
enable_dns_hostnames = true

The VPC contains one public subnet and one private subnet.

---

## Public Subnet

The public subnet uses:

10.10.1.0/24

Availability Zone:

us-east-1a

Public IP assignment is enabled:

map_public_ip_on_launch = true

A subnet is not public only because it has "public" in its name.

It becomes public because its route table contains a default route to an Internet Gateway.

0.0.0.0/0 -> Internet Gateway

For a workload to communicate directly with the Internet, it also needs a public IP and the required Security Group rules.

---

## Private Subnet

The private subnet uses:

10.10.2.0/24

Availability Zone:

us-east-1b

It does not automatically assign public IP addresses.

Its route table contains only the VPC local route:

10.10.0.0/16 -> local

There is no route such as:

0.0.0.0/0 -> Internet Gateway

Therefore the subnet does not have direct Internet connectivity.

No NAT Gateway was added in this lab in order to keep the environment simple and low-cost.

---

## Route Tables

### Public Route Table

10.10.0.0/16 -> local
0.0.0.0/0    -> Internet Gateway

The local route allows communication inside the VPC.

The default route sends Internet-bound traffic to the Internet Gateway.

### Private Route Table

10.10.0.0/16 -> local

No Internet default route exists.

The private route table is explicitly associated with the private subnet instead of depending implicitly on the VPC main route table.

---

## Security Group

A Security Group was created for the public web workload.

Inbound:

TCP 80
Source: 0.0.0.0/0

Outbound:

All traffic
Destination: 0.0.0.0/0

Security Groups are stateful.

This means that response traffic for an allowed inbound connection is automatically permitted.

A useful mental model is:

Route Table
= where traffic goes

Security Group
= which traffic is allowed

---

## EC2 Web Server

The lab deploys an Amazon Linux 2023 EC2 instance.

Instance type:

t3.micro

The instance is launched as a Spot Instance to reduce lab cost.

market_type = "spot"

Interruption behavior:

terminate

This is appropriate for this lab because the workload is:

- Stateless
- Temporary
- Reproducible using Terraform
- Safe to recreate

---

## Dynamic AMI Selection

Instead of hardcoding an AMI ID, Terraform uses an AWS data source to retrieve the latest compatible Amazon Linux 2023 AMI.

Conceptually:

Terraform
   |
   v
AWS AMI Catalog
   |
   v
Latest Amazon Linux 2023 AMI

This avoids storing an old AMI ID directly in the Terraform configuration.

---

## EC2 User Data

Nginx is installed automatically during instance initialization.

The user data performs:

Install nginx
Create HTML page
Enable nginx
Start nginx

The generated page contains:

Patrik Cloud Platform
Lab 04 - AWS Networking

This allows the workload to become functional automatically after Terraform creates the instance.

---

## HTTP Validation

After deployment, the instance received:

Private IP: 10.10.1.139
Public IP: 3.84.173.175
Lifecycle: spot
State: running

HTTP connectivity was validated using:

Invoke-WebRequest http://3.84.173.175

Result:

StatusCode: 200
StatusDescription: OK

The returned content was:

<h1>Patrik Cloud Platform</h1><p>Lab 04 - AWS Networking</p>

This confirmed that the complete network path was working:

Client
  |
  v
Internet
  |
  v
Internet Gateway
  |
  v
Public Route Table
  |
  v
Public Subnet
  |
  v
Security Group
  |
  v
EC2
  |
  v
Nginx

---

## Controlled Troubleshooting Scenario

A deliberate networking failure was introduced.

The Security Group rule was changed from:

TCP/80

to:

TCP/8080

Nginx continued listening on port 80.

The resulting architecture was inconsistent:

Nginx
TCP/80

Security Group
TCP/8080

The HTTP request then failed.

This demonstrated an important operational lesson:

A server can be healthy
while the application is still unreachable.

The troubleshooting process followed the traffic path instead of guessing.

1. EC2 running?
2. Public IP assigned?
3. Route Table correct?
4. Internet Gateway attached?
5. Security Group correct?
6. Application listening on the expected port?

The root cause was the Security Group rule.

After restoring TCP/80, the application returned:

HTTP 200 OK

---

## Security Group vs Network ACL

A short Network ACL experiment was also performed.

The main concepts were:

Security Group
- Stateful
- Applied to network interfaces/workloads
- Allow rules

Network ACL
- Stateless
- Applied to subnets
- Allow and deny rules
- Inbound and outbound traffic evaluated separately

The custom Network ACL was removed because the lab focus is on the networking controls more commonly used in day-to-day DevOps workflows.

---

## CloudWatch Metrics

The EC2 instance automatically publishes basic metrics to Amazon CloudWatch.

Metrics inspected during the lab included:

CPUUtilization
NetworkIn
NetworkOut

CPU utilization remained very low because the workload was almost idle.

Example:

CPUUtilization ≈ 0.15% - 0.18%

---

## Network Traffic Test

A small traffic test was performed using multiple HTTP requests.

Approximately 200 requests were generated.

CloudWatch showed an increase in:

NetworkIn
NetworkOut

Example observed values:

NetworkIn  ≈ 96 KB
NetworkOut ≈ 106 KB

This demonstrated how application activity becomes visible through infrastructure metrics.

---

## CloudWatch Alarm

A CloudWatch alarm was created using Terraform.

Alarm:

lab-web-ec2-high-cpu

Metric:

CPUUtilization

Threshold:

Average CPU > 70%

Evaluation:

2 periods
5 minutes each

Conceptually:

CPUUtilization
     |
     v
Average > 70%
     |
     v
2 consecutive periods
     |
     v
ALARM

The alarm state during validation was:

OK

---

## Cost Strategy

Keeping AWS cost low is an explicit requirement of this lab.

The following decisions helped reduce cost:

- Small EC2 instance
- Spot pricing
- No NAT Gateway
- No Load Balancer
- No database
- No long-running infrastructure
- CloudWatch used only for simple metrics and one alarm
- Infrastructure destroyed after validation

The intended lifecycle is:

Create
  |
  v
Validate
  |
  v
Troubleshoot
  |
  v
Observe
  |
  v
Document
  |
  v
Destroy

Only the Git repository and documentation should remain after the lab.

---

## Main Lessons

This lab reinforced several important concepts.

### Public vs Private Subnet

A subnet is public because of its routing configuration, not because of its name.

Public:
0.0.0.0/0 -> IGW

Private:
no direct Internet route

### Routing vs Security

Route Table
= where traffic goes

Security Group
= whether traffic is allowed

### Infrastructure Can Be Healthy but Unreachable

EC2 running
+
Nginx running
+
Wrong Security Group
=
Application unavailable

### Infrastructure as Code Enables Safe Reproduction

The whole environment can be:

created
tested
broken
fixed
destroyed
recreated

using Terraform.

### Observability Completes the Deployment Flow

Provisioning infrastructure is only part of the job.

A more complete workflow is:

Infrastructure as Code
        |
        v
Deployment
        |
        v
Validation
        |
        v
Troubleshooting
        |
        v
Observability

---

## DevOps Workflow Practiced

This lab represents the beginning of the end-to-end workflow that will be expanded in future labs:

Code
  |
  v
Git
  |
  v
Infrastructure as Code
  |
  v
AWS
  |
  v
Deploy
  |
  v
Validate
  |
  v
Observe
  |
  v
Troubleshoot
  |
  v
Destroy

Future labs will extend this flow with:

- GitHub Actions
- Automated CI
- Deployment pipelines
- S3
- Application Load Balancer
- Auto Scaling
- RDS
- Lambda
- API Gateway
- SQS / SNS
- Amazon ECR
- ECS Fargate
- EKS
- Helm
- ArgoCD
- Prometheus
- Grafana

---

## Cleanup

After the lab is completed and documented, all infrastructure should be destroyed.

terraform destroy

Before confirming the destroy plan, verify that all temporary lab resources are included.

After destruction:

terraform plan

should no longer propose managing active infrastructure from the previous session.

The AWS account should also be checked to ensure no billable lab resources remain.

---

## Final Architecture Summary

                     Internet
                         |
                         v
                 Internet Gateway
                         |
                         v
                 VPC 10.10.0.0/16
                  /             \
                 /               \
                v                 v
       Public Subnet        Private Subnet
       10.10.1.0/24        10.10.2.0/24
       us-east-1a          us-east-1b
            |                   |
            v                   v
     Public Route Table   Private Route Table
     0.0.0.0/0 -> IGW    local route only
            |
            v
       Security Group
       TCP/80
            |
            v
      EC2 Spot t3.micro
      Amazon Linux 2023
            |
            v
          Nginx
            |
            v
       HTTP 200 OK

            |
            +--------------------+
                                 |
                                 v
                         Amazon CloudWatch
                         CPUUtilization
                         NetworkIn
                         NetworkOut
                         High CPU Alarm

---

## Result

The lab successfully demonstrated:

Terraform
   +
AWS Networking
   +
EC2 Deployment
   +
Troubleshooting
   +
CloudWatch Observability

The environment can now be safely destroyed and recreated from code whenever needed.