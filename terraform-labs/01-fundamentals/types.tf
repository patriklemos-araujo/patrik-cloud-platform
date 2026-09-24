variable "project_name" {
  type    = string
  default = "patrik-cloud-platform"
}

variable "replica_count" {
  type    = number
  default = 2
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "availability_zones" {
  type = list(string)

  default = [
    "us-east-1a",
    "us-east-1b"
  ]
}

variable "common_tags" {
  type = map(string)

  default = {
    Environment = "dev"
    Project     = "patrik-cloud-platform"
  }
}

variable "instance_config" {
  type = object({
    instance_type = string
    monitoring    = bool
  })

  default = {
    instance_type = "t3.micro"
    monitoring    = true
  }
}

variable "file_count" {
  type    = number
  default = 3
}

variable "environments" {
  type = set(string)

  default = [
    "dev",
    "prod"
  ]
}

variable "is_production" {
  type    = bool
  default = false
}