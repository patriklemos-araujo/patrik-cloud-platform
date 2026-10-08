terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.8.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "lab" {
  bucket = "patrik-cloud-platform-s3-lab-910093226300"

  tags = {
    Name        = "patrik-cloud-platform-s3-lab"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "lab" {
  bucket = aws_s3_bucket.lab.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lab" {
  bucket = aws_s3_bucket.lab.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lab" {
  bucket = aws_s3_bucket.lab.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lab" {
  bucket = aws_s3_bucket.lab.id

  rule {
    id     = "manage-noncurrent-versions"
    status = "Enabled"

    filter {
      prefix = "lab/"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.lab
  ]
}

data "aws_iam_policy_document" "s3_lab" {
  statement {
    sid = "ListLabPrefix"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.lab.arn
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"

      values = [
        "lab/*"
      ]
    }
  }

  statement {
    sid = "ReadWriteLabObjects"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.lab.arn}/lab/*"
    ]
  }
}

resource "aws_iam_policy" "s3_lab" {
  name        = "patrik-s3-lab-least-privilege"
  description = "Least privilege access to the Lab 06 S3 prefix"

  policy = data.aws_iam_policy_document.s3_lab.json

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "s3_lab_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type = "AWS"

      identifiers = [
        "arn:aws:iam::910093226300:user/admin"
      ]
    }
  }
}

resource "aws_iam_role" "s3_lab" {
  name = "patrik-s3-lab-role"

  assume_role_policy = data.aws_iam_policy_document.s3_lab_assume_role.json

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "s3_lab" {
  role       = aws_iam_role.s3_lab.name
  policy_arn = aws_iam_policy.s3_lab.arn
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:*"
    ]

    resources = [
      aws_s3_bucket.lab.arn,
      "${aws_s3_bucket.lab.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "lab" {
  bucket = aws_s3_bucket.lab.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}