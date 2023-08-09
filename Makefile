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
start-local:
	kubectl apply -f k8s.yaml
	kubectl apply -f postgres.yaml
start-eks-dryrun:
	sed -E 's/image: (.*)/image: $(AWS_ECR_REPO)\/\1:latest/;s/imagePullPolicy: Never/imagePullPolicy: Always/' k8s.yaml > eks.k8s.yaml
start-eks: start-eks-dryrun
	kubectl apply -f eks.k8s.yaml
redeploy:
	kubectl rollout restart deployment/silimate-platform-k8s-deployment

# EKS K8s provisioning
create-cluster:
	eksctl create cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --version=1.27 --with-oidc
delete-cluster:
	eksctl delete cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION)

# EKS connect to RDS
install-rds-chart:
	aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws; \
	helm install --create-namespace -n ack-system oci://public.ecr.aws/aws-controllers-k8s/rds-chart --generate-name --set=aws.region=us-east-1
deploy-rds-db:
	export EKS_VPC_ID=`aws eks describe-cluster --name="${AWS_CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text`; \
	export EKS_SUBNET_IDS=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[*].SubnetId' --output text`; \
	export EKS_CIDR_RANGE=`aws ec2 describe-vpcs --vpc-ids $$EKS_VPC_ID --query "Vpcs[].CidrBlock" --output text`; \
	aws ec2 create-security-group --description "RDS ingress security group" --group-name silimate-platform-subnet-group --vpc-id "$$EKS_VPC_ID" --output text; \
	export RDS_SECURITY_GROUP_ID=`aws ec2 describe-security-groups --filters "Name=group-name,Values=silimate-platform-subnet-group" --query "SecurityGroups[0].GroupId" --output text`; \
	echo $$RDS_SECURITY_GROUP_ID; \
	aws ec2 authorize-security-group-ingress --group-id "$$RDS_SECURITY_GROUP_ID" --protocol tcp --port 5432 --cidr "$$EKS_CIDR_RANGE"; \
	kubectl create secret generic -n "default" silimate-platform-db-creds --from-literal=password="silimate"; \
	envsubst < rds.tmpl.yaml > rds.yaml; \
	kubectl apply -f rds.yaml
