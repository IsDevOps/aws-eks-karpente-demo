# EKS Cluster with Karpenter and S3 State Storage

This Terraform configuration deploys an Amazon EKS cluster with Karpenter for autoscaling, supporting both x86 and arm64 (Graviton) instances. It also sets up S3 for Terraform state storage and uses AWS Secrets Manager for storing sensitive credentials.

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (version 1.0.0 or later)
3. kubectl installed
4. An existing VPC with private subnets tagged as `Tier = "Private"`

## Usage

1. Clone this repository:
   ```
   git clone https://github.com/your-repo/eks-karpenter-terraform.git
   cd eks-karpenter-terraform
   ```

2. Update the `backend.tf` file with your S3 bucket name and desired key.

3. Create a `terraform.tfvars` file with your specific values:
   ```hcl
   region             = "us-west-2"
   vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
   cluster_name       = "my-eks-cluster"
   state_bucket_name  = "your-terraform-state-bucket"
   db_username        = "your_db_username"
   db_password        = "your_db_password"
   ```

4. Initialize Terraform with the S3 backend:
   ```
   terraform init -backend-config="bucket=your-terraform-state-bucket" -backend-config="key=eks-cluster/terraform.tfstate" -backend-config="region=us-west-2"
   ```

5. Apply the Terraform configuration:
   ```
   terraform apply
   ```

6. After the deployment is complete, configure kubectl to use the new cluster:
   ```
   aws eks update-kubeconfig --region <your-region> --name <your-cluster-name>
   ```

## Accessing Secrets

To access the stored credentials:

1. Use the AWS CLI:
   ```
   aws secretsmanager get-secret-value --secret-id <secrets_manager_secret_name_from_output> --region <your-region>
   ```

2. In your application, use the AWS SDK to retrieve secrets at runtime.

## Deploying Pods on Specific Instance Types

To deploy a pod on a specific instance type (x86 or arm64), use node selectors in your Kubernetes manifests:

### Example: Deploying on x86 (amd64) instance

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x86-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: x86-app
  template:
    metadata:
      labels:
        app: x86-app
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      containers:
      - name: x86-app
        image: nginx:latest
```

### Example: Deploying on arm64 (Graviton) instance

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: arm64-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: arm64-app
  template:
    metadata:
      labels:
        app: arm64-app
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
      containers:
      - name: arm64-app
        image: nginx:latest
```

Apply these manifests using kubectl:

```
kubectl apply -f x86-deployment.yaml
kubectl apply -f arm64-deployment.yaml
```

Karpenter will automatically provision the appropriate instance types based on the node selectors in your deployments.

