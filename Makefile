# Local or EKS (cloud)
K8S_CONTEXT := eks

# AWS Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s-dev
AWS_ROOT_ARN := arn:aws:iam::$(AWS_ACCOUNT_ID):root
AWS_ADDON_NAME := efs-csi-driver

# Utilities
get-endpoint:
	kubectl get svc -o wide
get-pods:
	kubectl get pods
get-events:
	kubectl get events --sort-by=.lastTimestamp
watch:
	watch "make get-events | tail -n 15"

# Start/stop k8s services
start:
	kubectl apply -f $(K8S_CONTEXT).k8s.yaml
stop:
	kubectl delete -f $(K8S_CONTEXT).k8s.yaml
redeploy:
	kubectl rollout restart deployment/silimate-platform-k8s-deployment

# EKS K8s provisioning
create-cluster:
	eksctl create cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --version=1.27 --with-oidc
delete-cluster:
	eksctl delete cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION)

# EKS connect to RDS
install-rds:
	aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws; \
	helm install --create-namespace -n ack-system oci://public.ecr.aws/aws-controllers-k8s/rds-chart --generate-name --set=aws.region=us-east-1
install-vpc:
	export EKS_VPC_ID=`aws eks describe-cluster --name="${AWS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text`; \
	export EKS_SUBNET_IDS=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[*].SubnetId' --output text`; \
	echo $$EKS_SUBNET_IDS; \
	envsubst < db-subnet-groups.tmpl.yaml > db-subnet-groups.yaml
