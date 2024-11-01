# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = var.dynamodb_table_name
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# Secrets Manager for storing credentials
resource "aws_secretsmanager_secret" "cluster_credentials" {
  name = "${var.cluster_name}-credentials"
}

resource "aws_secretsmanager_secret_version" "cluster_credentials" {
  secret_id = aws_secretsmanager_secret.cluster_credentials.id
  secret_string = jsonencode({
    db_username = var.db_username
    db_password = var.db_password
  })
}

# Fetch existing VPC
data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# EKS Cluster Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">= 19.0"  # Ensure this version is correct

  cluster_name          = var.cluster_name
  cluster_version       = "1.27"
  vpc_id                = data.aws_vpc.existing.id
  subnet_ids            = data.aws_subnets.private.ids

  eks_managed_node_groups = {
    initial = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
    }
  }
}

# Karpenter Module with IRSA
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = ">= 19.0"

  cluster_name             = module.eks.cluster_name
  irsa_oidc_provider_arn   = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  depends_on = [module.eks]
}

# Karpenter Provisioner for Instance Configuration
resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]
      limits:
        resources:
          cpu: 1000
      provider:
        instanceTypes:
          - t3.medium
          - t3.large
          - c6g.medium
          - c6g.large
        tags:
          karpenter.sh/discovery: ${var.cluster_name}
  YAML

  depends_on = [module.karpenter]
}
