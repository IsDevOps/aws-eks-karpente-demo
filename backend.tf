terraform {
  backend "s3" {
    bucket         = "demo-bucket-test-090"
    key            = "eks-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock2"

  }
}
