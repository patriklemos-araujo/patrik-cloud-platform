\# Lab 06 — S3 Storage, IAM, STS and Application Access



This lab demonstrates how to build and secure an Amazon S3 environment using Terraform, IAM least privilege, STS temporary credentials, S3 versioning, lifecycle rules, encryption, bucket policies, and application access with Python and boto3.



\---



\## Architecture



User admin

&#x20;  |

&#x20;  | sts:AssumeRole

&#x20;  v

IAM Role

patrik-s3-lab-role

&#x20;  |

&#x20;  | attached IAM Policy

&#x20;  v

Least Privilege

&#x20;  |

&#x20;  +--> ListBucket on lab/\*

&#x20;  +--> GetObject on lab/\*

&#x20;  +--> PutObject on lab/\*

&#x20;  |

&#x20;  v

S3 Bucket

patrik-cloud-platform-s3-lab-910093226300

&#x20;  |

&#x20;  +--> Public Access Block

&#x20;  +--> Versioning

&#x20;  +--> SSE-S3 AES256 encryption

&#x20;  +--> Lifecycle rules

&#x20;  +--> Bucket Policy

&#x20;  |      |

&#x20;  |      +--> Explicit Deny for insecure HTTP

&#x20;  |

&#x20;  v

Python application

&#x20;  |

&#x20;  | boto3

&#x20;  v

S3 object upload



\---



\## Technologies



\- Terraform

\- AWS S3

\- AWS IAM

\- AWS STS

\- AWS CLI

\- Python

\- boto3



\---



\## S3 Configuration



The bucket is managed by Terraform and includes:



\- Public Access Block

\- Versioning enabled

\- Server-side encryption using AES256

\- Lifecycle management for noncurrent object versions

\- Bucket policy enforcing HTTPS



The bucket intentionally uses:



force\_destroy = false



This makes cleanup safer and also demonstrates an important behavior of versioned S3 buckets: Terraform cannot destroy a bucket while object versions or delete markers still exist.



\---



\## Versioning



The same S3 key was uploaded more than once:



lab/test-object.txt



This created multiple object versions.



Example:



Version 2

└── latest



Version 1

└── noncurrent



An older version was successfully retrieved using its explicit version-id.



\---



\## Delete Markers



Deleting an object from a versioned bucket does not automatically remove all previous versions.



Instead:



aws s3 rm

&#x20;  |

&#x20;  v

Delete Marker



The historical object versions remain stored.



Removing the delete marker restored access to the previous current version.



\---



\## Server-Side Encryption



Objects are encrypted using:



SSE-S3

AES256



Validation with get-object and head-object returned:



ServerSideEncryption: AES256



\---



\## Lifecycle Management



Noncurrent versions under the lab/ prefix use the following lifecycle:



Noncurrent version

&#x20;  |

&#x20;  | 30 days

&#x20;  v

STANDARD\_IA

&#x20;  |

&#x20;  | 90 days

&#x20;  v

GLACIER

&#x20;  |

&#x20;  | 180 days

&#x20;  v

Expiration



This lab does not wait for lifecycle transitions to occur. The objective is to understand how lifecycle policies are configured and evaluated.



\---



\## IAM Least Privilege



A dedicated IAM policy was created with limited S3 permissions.



Allowed:



s3:ListBucket

s3:GetObject

s3:PutObject



Restricted to:



lab/\*



Not allowed:



s3:DeleteObject

s3:GetObjectVersion

s3:DeleteObjectVersion

s3:\*



\---



\## IAM Role and Trust Policy



The role:



patrik-s3-lab-role



can be assumed by the lab admin user through:



sts:AssumeRole



The trust relationship answers:



Who can assume this role?



The attached IAM policy answers:



What can this role do after being assumed?



\---



\## Temporary Credentials



The role was assumed using AWS STS.



The returned temporary credentials were exported into the PowerShell session:



AWS\_ACCESS\_KEY\_ID

AWS\_SECRET\_ACCESS\_KEY

AWS\_SESSION\_TOKEN



The active identity became:



arn:aws:sts::910093226300:assumed-role/patrik-s3-lab-role/...



No permanent access keys were created for the role.



\---



\## Least Privilege Tests



\### Allowed upload



Upload to:



lab/allowed.txt



Result:



ALLOW



\---



\### Upload outside allowed prefix



Upload to:



private/denied.txt



Result:



AccessDenied



Reason:



No identity-based policy allows s3:PutObject



\---



\### Delete inside allowed prefix



Delete:



lab/allowed.txt



Result:



AccessDenied



Reason:



s3:DeleteObject is not allowed



\---



\## ListBucket and Prefix Conditions



Listing:



s3://bucket/lab/



worked.



Listing:



s3://bucket/



failed.



This demonstrates that:



s3:ListBucket



operates on the bucket ARN, while the s3:prefix condition limits what can be listed.



\---



\## IAM Policy vs Bucket Policy



\### Identity-based policy



Attached to:



IAM user / role



Defines what the identity can perform.



\### Resource-based policy



Attached directly to:



S3 bucket



Defines how that resource can be accessed.



\---



\## Explicit Deny



A bucket policy was created to deny all S3 operations when HTTPS is not used.



Condition:



aws:SecureTransport = false



Policy behavior:



IAM Allow

&#x20;  +

Bucket Policy Explicit Deny

&#x20;  =

DENY



This demonstrates one of the most important IAM rules:



Explicit Deny wins over Allow



\---



\## HTTPS vs HTTP Test



HTTPS upload:



ALLOW



HTTP upload using an explicit HTTP endpoint:



DENY



AWS returned:



with an explicit deny in a resource-based policy



\---



\## GetObject vs GetObjectVersion



The role has:



s3:GetObject



but not:



s3:GetObjectVersion



Result:



Current object

→ ALLOW



Historical version

→ AccessDenied



This is an important distinction when working with versioned S3 buckets.



\---



\## Application Access with boto3



A simple Python application uploads an object using boto3:



app.py

&#x20;  |

&#x20;  v

boto3

&#x20;  |

&#x20;  v

AWS credential provider chain

&#x20;  |

&#x20;  v

temporary STS credentials

&#x20;  |

&#x20;  v

S3



No AWS credentials are hardcoded in the application.



The application uploads:



lab/app-test.txt



\---



\## Credential Provider Concept



The boto3 SDK automatically discovers credentials from supported providers.



In this lab:



Environment variables



were used.



In real AWS workloads, the same application pattern can use:



EC2

→ Instance Role



ECS

→ Task Role



Lambda

→ Execution Role



EKS

→ Pod / workload IAM integration



This avoids embedding AWS secrets directly in application code.



\---



\## Troubleshooting Story



During the lab, Terraform was executed while temporary credentials from the restricted role were still exported in the PowerShell session.



Terraform therefore inherited the restricted identity.



The result was multiple errors such as:



AccessDenied

s3:GetBucketVersioning



AccessDenied

s3:GetBucketPublicAccessBlock



AccessDenied

iam:GetRole



AccessDenied

iam:GetPolicy



The lesson:



Shell credentials

&#x20;  |

&#x20;  +--> AWS CLI

&#x20;  +--> Terraform

&#x20;  +--> boto3

&#x20;  +--> SDKs



Different tools can consume the same credential chain.



Before running Terraform administration commands, the restricted credentials were removed from the shell.



\---



\## Security Lessons



This lab reinforces several security principles:



Least Privilege

Temporary Credentials

No Hardcoded Secrets

Encryption at Rest

Encryption in Transit

Private Buckets

Explicit Deny

Scoped Resource ARNs

Role-based Access



\---



\## Cost Considerations



This lab uses low-cost AWS services, but S3 is not completely free.



Potential costs include:



\- Stored object versions

\- S3 requests

\- Lifecycle transition requests

\- STANDARD\_IA storage

\- Glacier storage

\- Minimum storage duration charges



IAM and STS do not introduce direct resource charges in this lab.



\---



\## Cleanup Warning



Because versioning is enabled:



aws s3 rm --recursive



is not sufficient to fully empty the bucket.



It creates delete markers but historical versions may remain.



Before running:



terraform destroy



all of the following must be removed:



Current object versions

Noncurrent object versions

Delete markers



Because:



force\_destroy = false



Terraform will refuse to delete the S3 bucket while versioned objects still exist.



\---



\## Key Takeaways



\- S3 object versioning changes deletion behavior.

\- Delete markers are not the same as permanent deletion.

\- GetObject and GetObjectVersion are different IAM permissions.

\- ListBucket uses the bucket ARN.

\- Object operations use object ARNs.

\- Identity policies and resource policies participate in AWS authorization.

\- Explicit Deny overrides Allow.

\- STS provides temporary credentials.

\- SDKs should use the AWS credential provider chain instead of hardcoded keys.

\- Terraform and AWS CLI may inherit the same shell credentials.

\- Versioned S3 buckets require special attention during cleanup.

