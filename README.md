# Silimate Platform K8s
Kubernetes configuration/provisioning for deployments, including Postgres database Docker

## Common Setup
1. Install AWS CLI v2
2. Log into AWS with `aws configure`
3. Install `kubectl`

## AWS EKS Deployment Standard Operating Procedure
1. Install `eksctl`
2. Deploy AWS ECR secrets with `make create-ecr-secret`
3. Set `K8S_ENV` in `Makefile` to {`dev`, `prod`, `test`}
4. Create cluster with `make create-cluster`
5. Set up AWS authorization with `make aws-auth`
6. Create EFS addon with `make create-efs`
7. (Optional) Make sure `KUBE_CONFIG_DATA` secret is updated in all [GitHub Actions for Continuous Deployment (CD)](https://github.com/kodermax/kubectl-aws-eks)
8. Follow "Common SOP" below

## On-premise Deployment Standard Operating Procedure
1. Install Docker engine
2. Start Kubernetes with `kubeadm` or `minikube`
3. Create AWS account and log in: [register AWS account ID with Silimate](https://repost.aws/knowledge-center/secondary-account-access-ecr)
4. Create local PVC with `make create-local-pvc`
5. Follow "Common SOP" below

## Common Standard Operating Procedure
1. Deploy secrets with `make create-secrets`
2. Deploy the config file with `make create-config`
3. (If not using RDS) Deploy PostgreSQL database `make start-db`
4. Deploy Silimate platform with `make start`
5. Create worker auth with `make worker-auth`
6. Expose service to HTTP(S) traffic with `make expose`

## CNAME
1. Use `make get-endpoint` to get endpoint URL
2. Go to Google Domains and add it as a CNAME
