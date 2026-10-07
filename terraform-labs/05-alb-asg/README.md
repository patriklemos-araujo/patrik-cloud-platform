# Lab 05 - AWS Application Load Balancer and Auto Scaling

This lab demonstrates how to build a highly available web application architecture on AWS using Terraform, Application Load Balancer, Auto Scaling Group, Spot EC2 instances, CloudWatch metrics, alarms, and target tracking scaling policies.

## Architecture

Internet
   |
   v
Application Load Balancer
   |
   v
Target Group
   |
   +-------------------+
   |                   |
   v                   v
EC2 Spot            EC2 Spot
us-east-1a          us-east-1b
   |
   +------ Auto Scaling Group ------+

The Auto Scaling Group can scale from 2 to 3 instances based on application load.

## AWS Services Used

- Amazon VPC
- Public Subnets
- Internet Gateway
- Route Tables
- Security Groups
- Application Load Balancer
- Target Groups
- EC2 Spot Instances
- Launch Templates
- Auto Scaling Group
- CloudWatch Metrics
- CloudWatch Alarms
- Target Tracking Scaling Policy

## Network Design

The VPC uses:

- VPC CIDR: 10.20.0.0/16
- Public Subnet A: 10.20.1.0/24
- Public Subnet B: 10.20.2.0/24
- Availability Zones:
  - us-east-1a
  - us-east-1b

Both public subnets use a route table with:

0.0.0.0/0 -> Internet Gateway

The Application Load Balancer is deployed across both Availability Zones.

## Security Groups

Two Security Groups are used.

### ALB Security Group

Allows HTTP traffic from the Internet:

Internet
   |
TCP/80
   |
   v
Application Load Balancer

### Web Security Group

The EC2 instances do not accept HTTP traffic directly from the Internet.

They only accept traffic from the ALB Security Group:

ALB Security Group
        |
     TCP/80
        |
        v
Web Security Group
        |
        v
EC2 Instances

This reduces the public attack surface.

## Launch Template

The Launch Template defines:

- Amazon Linux 2023
- t3.micro
- Spot Instances
- Web Security Group
- IMDSv2 required
- Nginx installation using User Data

The generated web page exposes:

- EC2 Instance ID
- Availability Zone

This makes it possible to visually confirm traffic distribution through the ALB.

## IMDSv2

The Launch Template requires Instance Metadata Service v2:

http_tokens = required

The User Data script requests a metadata token before accessing the EC2 metadata endpoint.

This avoids using the older tokenless IMDSv1 flow.

## Application Load Balancer

The ALB listens on:

HTTP :80

The listener forwards traffic to the web Target Group.

The Target Group performs HTTP health checks against:

/

Healthy targets receive traffic from the ALB.

## Load Balancing Validation

Multiple HTTP requests were sent to the ALB DNS endpoint.

Responses were distributed between instances running in different Availability Zones.

Example:

Instance: i-xxxxxxxxxxxxxxxxx
AZ: us-east-1a

and:

Instance: i-yyyyyyyyyyyyyyyyy
AZ: us-east-1b

This confirmed traffic distribution across multiple healthy targets.

## Failure Injection - Target Deregistration

One EC2 instance was manually deregistered from the Target Group.

The target entered:

draining

The remaining healthy target continued serving all incoming requests.

This demonstrated that removing one backend did not make the application unavailable.

## Auto Scaling Self-Healing

An EC2 instance managed by the Auto Scaling Group was manually terminated.

The sequence observed was:

EC2 terminated
      |
      v
Auto Scaling detects unhealthy capacity
      |
      v
Launch Template creates replacement
      |
      v
New EC2 starts
      |
      v
Target Group health check
      |
      v
Target becomes healthy

The Auto Scaling Group automatically restored the desired capacity without manual provisioning.

This demonstrated self-healing behavior.

## CloudWatch HealthyHostCount

The HealthyHostCount metric showed the failure and recovery.

Observed pattern:

2 healthy
   |
   v
1 healthy
   |
   v
2 healthy

This matched the lifecycle of the failure injection and automatic replacement.

## CloudWatch Alarm

A CloudWatch alarm was created for:

HealthyHostCount < 2

The alarm lifecycle was observed as:

INSUFFICIENT_DATA
        |
        v
       OK
        |
        v
      ALARM
        |
        v
       OK

The alarm history confirmed that the environment degraded and later recovered.

## Self-Healing vs Auto Scaling

This lab demonstrated the difference between two behaviors.

### Self-Healing

Desired capacity = 2

2 instances
   |
one fails
   |
   v
1 instance
   |
replacement
   |
   v
2 instances

The number of desired instances does not change.

### Elastic Scaling

2 instances
   |
load increases
   |
   v
3 instances

The desired capacity changes according to workload demand.

## Target Tracking Policy

The Auto Scaling Group uses a Target Tracking Scaling Policy based on:

ALBRequestCountPerTarget

Target value:

20 requests per target

The low value was intentionally chosen for the lab so scaling could be triggered using a small test workload.

In production, the value should be defined using performance testing, latency targets, throughput, and service-level objectives.

## Scale Out Test

A sustained load was generated against the ALB.

The Target Tracking high alarm required:

Threshold: 20
Evaluation periods: 3
Period: 60 seconds

After sustained load, the alarm triggered the scaling policy.

Observed event:

desired capacity 2 -> 3

A third EC2 Spot instance was automatically launched.

After startup and health checks, all three targets became healthy.

Target Group
├── EC2 healthy
├── EC2 healthy
└── EC2 healthy

## Scale In Test

The Target Tracking low alarm was configured automatically by AWS with:

Threshold: 14
Evaluation periods: 15
Period: 60 seconds

After the traffic stopped and the low-load condition persisted, the scaling policy reduced capacity.

Observed sequence:

desired capacity 3 -> 2

For a short period:

Desired capacity: 2
Actual instances: 3

This showed the termination lifecycle while one instance was being safely removed.

The environment later stabilized at:

Min:     2
Desired: 2
Max:     3

with two healthy instances.

## Key Lessons

- ALB distributes traffic across healthy targets.
- Multi-AZ architecture improves availability.
- Security Groups can reference other Security Groups.
- EC2 instances can remain inaccessible directly from the Internet while still receiving traffic from an ALB.
- Target Groups control backend health and routing.
- Deregistration draining allows safer target removal.
- Auto Scaling Groups provide self-healing.
- Self-healing and elasticity are different concepts.
- Target Tracking policies rely on CloudWatch alarms.
- Short traffic bursts do not necessarily trigger scaling.
- Sustained load is more relevant for scaling decisions.
- Scale-out is intentionally faster than scale-in.
- Conservative scale-in behavior helps prevent scaling flapping.
- CPU is not always the best scaling metric.
- Application-level demand metrics can be more representative of workload pressure.
- Observability is essential to validate availability and scaling behavior.

## Cost Strategy

This lab intentionally uses:

- t3.micro
- Spot Instances
- Maximum of 3 EC2 instances
- Short-lived infrastructure

The Application Load Balancer and public IPv4 addresses generate cost while active.

The entire environment should be destroyed after validation.

## Cleanup

Destroy the infrastructure:

terraform destroy

Then verify that Terraform no longer tracks resources:

terraform state list

Because the Terraform configuration still declares the infrastructure, running terraform plan after destruction will propose recreating the resources.

This is expected:

Terraform code = desired state
Terraform state = current Terraform-managed mapping
AWS = real infrastructure

After terraform destroy:

Code still exists
State is empty
AWS resources are removed

Therefore a new terraform plan will propose creating the environment again.

## Final Architecture

                         Internet
                            |
                            v
                  Application Load Balancer
                   us-east-1a / us-east-1b
                            |
                            v
                       Listener :80
                            |
                            v
                       Target Group
                      /      |      \
                     /       |       \
                    v        v        v
                 EC2      EC2      EC2
                 Spot     Spot     Spot
                     \      |      /
                      \     |     /
                       Auto Scaling
                         Group
                     min     = 2
                     desired = 2
                     max     = 3
                            |
                            v
                       CloudWatch
                  Metrics + Alarms

## Repository

This lab is part of the patrik-cloud-platform study repository.