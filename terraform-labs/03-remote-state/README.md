# Terraform Remote State, CI and Drift Detection Lab

This lab demonstrates a production-oriented Terraform workflow using AWS,
GitHub Actions, OIDC authentication, remote state, state locking and
automated drift detection.

The goal is not only to provision infrastructure, but also to understand
how Terraform behaves in a collaborative CI/CD environment.

---

## Architecture

```text
Developer
   |
   | git push / pull request
   v
GitHub Repository
   |
   +----------------------------+
   |                            |
   v                            v
Terraform CI              Drift Detection
terraform-ci.yml          terraform-drift.yml
   |                            |
   v                            v
Validate                   Scheduled / Manual
   |                            |
   v                            v
Terraform Plan             Terraform Plan
   |                       -detailed-exitcode
   |                            |
   +------------+---------------+
                |
                v
           GitHub OIDC
                |
                v
             AWS STS
                |
                v
            IAM Role
                |
                v
             Terraform
             /       \
            /         \
           v           v
      S3 Backend    AWS SSM
      tfstate       Parameter
      .tflock
```

---

## Technologies

- Terraform
- AWS S3
- AWS IAM
- AWS STS
- AWS Systems Manager Parameter Store
- GitHub Actions
- GitHub OIDC

---

## Lab Structure

```text
03-remote-state/
├── bootstrap/
│   └── Terraform configuration responsible for creating the S3 backend
│
├── app/
│   └── Terraform configuration that uses the remote backend and manages
│       AWS resources
│
└── README.md
```

The backend infrastructure is separated from the application state because
Terraform cannot use an S3 backend before that backend exists.

---

## Main Learning Goals

This lab was designed to practice:

- Remote Terraform state
- State locking
- CI validation and planning
- GitHub OIDC federation
- AWS STS temporary credentials
- IAM least privilege
- Real AWS resources managed by Terraform
- Automated drift detection
- Human-controlled reconciliation
- Troubleshooting real CI/CD issues

---

## Remote State

Terraform state is stored remotely in Amazon S3.

The backend provides:

- Remote Terraform state
- S3 versioning
- Server-side encryption
- State locking using `use_lockfile`
- Protection against concurrent Terraform operations

Conceptually:

```text
Terraform Configuration
        |
        v
     Terraform
      /     \
     v       v
S3 State   AWS Resources
```

The Terraform state is Terraform's record of the infrastructure it manages.

It is not the infrastructure itself and it is not a complete inventory of the AWS account.

---

## State Locking

State locking prevents multiple Terraform operations from modifying the same state simultaneously.

A concurrency test was performed using two terminals.

Terminal 1 acquired the lock during a Terraform operation.

Terminal 2 attempted:

```bash
terraform plan -lock-timeout=5s
```

Terraform correctly prevented the second operation from modifying the same state.

The backend uses:

```text
terraform.tfstate
terraform.tfstate.tflock
```

This demonstrated why state locking is critical when Terraform is executed by multiple users or CI/CD pipelines.

---

## GitHub OIDC Authentication

No permanent AWS access keys are stored in GitHub.

GitHub Actions authenticates to AWS using OpenID Connect.

```text
GitHub Actions Runner
        |
        | OIDC Token
        v
GitHub OIDC Provider
        |
        v
AWS STS
AssumeRoleWithWebIdentity
        |
        v
IAM Role
        |
        v
Temporary AWS Credentials
        |
        v
Terraform
```

The IAM role used by this lab is:

```text
github-actions-terraform-ci
```

This approach provides short-lived AWS credentials instead of long-lived access keys.

The authentication flow is:

```text
GitHub Actions
      |
      v
OIDC
      |
      v
AWS STS
      |
      v
IAM Role
      |
      v
Temporary Credentials
```

This improves security because no permanent AWS credentials need to be stored in GitHub Secrets.

---

## GitHub Actions CI

The CI workflow separates static validation from AWS-dependent planning.

### Validate Job

```text
Checkout
   ↓
Setup Terraform
   ↓
terraform fmt
   ↓
terraform init -backend=false
   ↓
terraform validate
```

This job does not require AWS authentication.

Its purpose is to fail fast when the Terraform configuration contains formatting or validation issues.

### Plan Job

```text
Validate
   ↓
GitHub OIDC
   ↓
AWS STS
   ↓
IAM Role
   ↓
terraform init
   ↓
terraform plan
```

The Plan job only runs after Validate succeeds.

This separation ensures that AWS is not accessed when the Terraform configuration is already invalid.

---

## IAM Least Privilege

The GitHub Actions role follows the principle of least privilege.

Permissions are separated conceptually into two categories.

### Backend Permissions

Used by Terraform to access the remote state:

- `s3:ListBucket`
- `s3:GetObject`
- lock file operations

### Infrastructure Permissions

Used during Terraform refresh and plan operations:

- `ssm:GetParameter`
- `ssm:ListTagsForResource`
- `ssm:DescribeParameters`

An important lesson from this lab is:

> Backend access does not automatically provide access to the infrastructure managed by Terraform.

Terraform may successfully initialize the S3 backend while still failing during `terraform plan` if the provider cannot read the managed resources.

---

## Managed AWS Resource

The lab manages an AWS Systems Manager Parameter:

```text
/patrik-cloud-platform/remote-state-lab/message
```

The resource is managed through Terraform using:

```hcl
resource "aws_ssm_parameter" "remote_state_lab"
```

This replaced an earlier `local_file` resource.

The local resource exposed an important CI/CD problem:

GitHub-hosted runners are ephemeral and do not contain files created on a developer workstation.

Remote Terraform state does not make a local resource remote.

The resource is tagged with metadata such as:

- Environment
- Project
- ManagedBy
- Repository

---

## Drift Detection

A dedicated GitHub Actions workflow periodically checks whether the real infrastructure still matches the Terraform configuration.

The workflow executes:

```bash
terraform plan -detailed-exitcode
```

Terraform uses the following exit codes:

```text
0 = No differences
1 = Terraform error
2 = Changes detected
```

The workflow interprets those values and reports differences when changes are detected.

Conceptually:

```text
terraform plan -detailed-exitcode
              |
      +-------+-------+
      |       |       |
      v       v       v
      0       1       2
      |       |       |
      v       v       v
  Healthy   Error   Drift
```

The workflow can be triggered:

- Manually
- On a schedule

---

## Drift Test

A controlled drift experiment was performed.

Initial Terraform configuration:

```text
Terraform CI remote state lab
```

The SSM Parameter was manually changed outside Terraform to:

```text
manual drift test
```

The real AWS resource was then different from the Terraform desired state.

```text
Terraform Desired State
        ≠
AWS Real State
```

The drift detection workflow then executed:

```bash
terraform plan -detailed-exitcode
```

Terraform detected:

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

The workflow correctly classified the result as drift.

---

## Drift Reconciliation

After investigating the detected drift, the infrastructure was reconciled using Terraform.

First:

```bash
terraform plan
```

Terraform confirmed that only the existing SSM Parameter needed an in-place update.

Then:

```bash
terraform apply
```

Terraform updated the existing resource.

Result:

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

A final validation returned:

```text
No changes. Your infrastructure matches the configuration.
```

The environment was once again aligned:

```text
Terraform Code
      =
Terraform State
      =
AWS Infrastructure
```

---

## Drift Management Strategy

This lab intentionally does not perform automatic remediation.

The preferred workflow is:

```text
Detect Drift
     |
     v
Alert
     |
     v
Investigate
     |
     v
Human Decision
   /       \
  v         v
Update     Reconcile
Code       Infrastructure
```

Automatically applying Terraform after detecting drift could revert a legitimate emergency change or apply an unexpected configuration.

The strategy followed in this lab is:

> Detect automatically. Investigate deliberately. Reconcile safely.

---

## Troubleshooting Lessons

Several real issues were investigated during this lab.

### 1. Git Configuration and AWS Infrastructure Were Inconsistent

The Terraform state and AWS contained the SSM Parameter, while the default Git branch still contained the old `local_file` configuration.

Terraform correctly proposed:

```text
- destroy SSM Parameter
+ create local_file
```

This demonstrated that Git, Terraform state and the real infrastructure must remain aligned.

The missing commits were recovered into a new branch and merged through a Pull Request.

---

### 2. Remote State Does Not Make a Resource Remote

The original lab used:

```hcl
resource "local_file" "remote_state_lab"
```

The Terraform state was remote, but the resource itself was still local to the machine running Terraform.

A GitHub-hosted runner therefore planned to recreate the local file because the file did not exist on the ephemeral runner.

This exposed an important distinction:

```text
Remote State
!=
Remote Resource
```

The resource was replaced with an AWS SSM Parameter.

---

### 3. Backend Access Was Not Enough

Terraform could access the remote S3 state, but the AWS provider could not refresh the SSM resource.

The pipeline initially failed with IAM `AccessDenied` errors.

Additional read-only permissions were required:

```text
ssm:GetParameter
ssm:ListTagsForResource
ssm:DescribeParameters
```

This demonstrated the difference between:

```text
Backend Permissions
and
Managed Resource Permissions
```

---

### 4. Pull Request OIDC Authentication Failed

GitHub OIDC subjects differ between branch workflows and Pull Request workflows.

The initial IAM trust policy allowed the main branch but rejected Pull Request execution.

The trust policy was updated to explicitly trust the required GitHub repository contexts.

A broad wildcard was intentionally avoided.

This preserved a stricter trust boundary.

---

### 5. Terraform Detailed Exit Code Was Not Preserved

The first drift test successfully detected a Terraform change, but the workflow incorrectly classified the result as no drift.

The Terraform wrapper installed by `setup-terraform` affected the behavior of:

```bash
terraform plan -detailed-exitcode
```

The workflow was updated with:

```yaml
terraform_wrapper: false
```

After the change, Terraform correctly returned exit code `2` when differences were detected.

---

### 6. Re-running a Workflow Uses the Original Commit

During testing, a GitHub Actions workflow was re-run after the `main` branch had already been corrected.

The re-run still executed the original commit associated with the previous workflow run.

This caused Terraform to continue seeing the old `local_file` configuration.

A new workflow run from the current `main` branch correctly used the updated Terraform configuration.

This reinforced an important CI/CD concept:

> A workflow run is associated with a specific version of the repository.

---

## Key Lessons

This lab demonstrated that a reliable Terraform workflow requires more than writing `.tf` files.

Important concepts include:

- Infrastructure as Code
- Remote state
- State locking
- Terraform desired state
- Terraform state
- Real infrastructure
- Least privilege IAM
- Temporary AWS credentials
- OIDC federation
- AWS STS
- Pull Request validation
- Terraform planning
- Drift detection
- Human-controlled remediation
- Git as the source of truth
- Ephemeral CI runners
- Troubleshooting IAM permissions
- Troubleshooting CI/CD behavior

---

## Current Result

The environment is currently aligned.

```text
Terraform Code
      =
Remote State
      =
AWS Infrastructure
```

Terraform currently reports:

```text
No changes.
```

The current workflow architecture provides:

```text
Developer
   |
   v
Pull Request
   |
   v
Terraform Validate
   |
   v
Terraform Plan
   |
   v
GitHub OIDC
   |
   v
AWS STS
   |
   v
IAM Role
   |
   v
Temporary Credentials
   |
   v
Terraform
   |
   +------ S3 Remote State
   |
   +------ AWS SSM Parameter
```

In parallel:

```text
Scheduled / Manual
        |
        v
Drift Detection
        |
        v
terraform plan -detailed-exitcode
        |
   +----+----+
   |    |    |
   0    1    2
   |    |    |
Healthy Error Drift
```

---

## Next Steps

Future improvements for this project include:

- Terraform import
- moved blocks and refactoring
- Advanced Terraform state operations
- Saved Terraform plans
- `-replace`
- refresh-only workflows
- Provider aliases
- Terraform version constraints
- Sensitive values
- Terraform workspaces
- HCP Terraform / Terraform Cloud
- Reusable AWS modules
- Multiple environments
- CI and CD role separation
- Controlled Terraform apply
- GitHub approval gates
- Infrastructure security scanning
- AWS networking
- Amazon ECR
- Amazon EKS
- Helm
- GitOps with ArgoCD
- Prometheus and Grafana observability
- Production-oriented AWS architecture

---

## Future AWS Validation Labs

After the main DevOps pipeline is complete, additional AWS labs can be created to validate knowledge across multiple services.

Possible labs include:

```text
aws-validation-labs/
├── 01-vpc-networking/
├── 02-iam/
├── 03-s3/
├── 04-ec2/
├── 05-alb-asg/
├── 06-rds/
├── 07-lambda-api-gateway/
├── 08-sqs-sns/
├── 09-eventbridge/
├── 10-cloudwatch/
├── 11-ecr/
├── 12-ecs-fargate/
└── 13-eks/
```

Each lab should follow the same lifecycle:

```text
Architecture
     ↓
Terraform Code
     ↓
terraform plan
     ↓
terraform apply
     ↓
AWS Validation
     ↓
Break / Troubleshoot
     ↓
Documentation
     ↓
terraform destroy
```

The goal is to validate real AWS knowledge without leaving unnecessary resources running.

A lab should only be considered complete after:

- The architecture has been understood
- The resource has been provisioned
- The behavior has been validated
- At least one troubleshooting scenario has been explored
- The findings have been documented
- The lab infrastructure has been destroyed when no longer required

---

## Learning Approach

This repository follows a practical learning methodology:

```text
Understand
   ↓
Build
   ↓
Test
   ↓
Break
   ↓
Troubleshoot
   ↓
Document
   ↓
Destroy
   ↓
Rebuild
```

The objective is to understand not only how the tools work, but also why production environments are designed this way.