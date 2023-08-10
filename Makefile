# Local or EKS (cloud)
K8S_CONTEXT := eks

# AWS Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s-test
AWS_DB_NAME := silimate-platform-db
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
debug:
	kubectl run alpine --image=alpine -i --tty

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
rds: install-rds-chart create-rds-db deploy-rds-db
install-rds-chart:
	aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws; \
	helm install --create-namespace -n ack-system oci://public.ecr.aws/aws-controllers-k8s/rds-chart --generate-name --set=aws.region=us-east-1
create-rds-db:
	aws rds create-db-cluster \
		--db-cluster-identifier $(AWS_DB_NAME) \
    --engine aurora-postgresql \
    --storage-type aurora-iopt1 \
    --master-username silimate \
		--master-user-password silimate \
		--engine-version 15.3 \
		--region $(AWS_REGION); \
	aws rds create-db-instance \
		--db-cluster-identifier $(AWS_DB_NAME) \
		--db-instance-identifier $(AWS_DB_NAME)-instance-1 \
		--engine aurora-postgresql \
		--db-instance-class db.r5.large;
deploy-rds-db:
	export EKS_VPC_ID=`aws eks describe-cluster --name=$(AWS_CLUSTER_NAME) --query cluster.resourcesVpcConfig.vpcId --output text`; \
	export EKS_SECURITY_GROUP_IDS=`aws eks describe-cluster --name=$(AWS_CLUSTER_NAME) --query cluster.resourcesVpcConfig.securityGroupIds --output text`; \
	export EKS_SUBNET_IDS=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[*].SubnetId' --output text`; \
	export RDS_SECURITY_GROUP_IDS=`aws rds describe-db-clusters --query "DBClusters[?DBClusterIdentifier=='$(AWS_DB_NAME)'].VpcSecurityGroups[*].VpcSecurityGroupId" --output text`; \
	export RDS_ENDPOINT=`aws rds describe-db-clusters --query "DBClusters[?DBClusterIdentifier=='$(AWS_DB_NAME)'].Endpoint" --output text`; \
	aws ec2 authorize-security-group-ingress \
		--group-id $$EKS_SECURITY_GROUP_IDS \
		--protocol tcp \
		--port 5432 \
		--cidr 0.0.0.0/0; \
	aws ec2 authorize-security-group-ingress \
		--group-id $$RDS_SECURITY_GROUP_IDS \
		--protocol tcp \
		--port 5432 \
		--cidr 0.0.0.0/0; \
	envsubst < rds.tmpl.yaml > rds.yaml
	kubectl apply -f rds.yaml
