# Local or EKS (cloud)
K8S_CONTEXT := eks

# Build environment (dev, test, prod)
BUILD_ENV := test

# AWS Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s-$(BUILD_ENV)
AWS_DB_NAME := silimate-platform-db-$(BUILD_ENV)
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
deploy-rds-db: create-rds-db connect-rds-db
create-rds-db:
	aws rds create-db-cluster \
		--db-cluster-identifier $(AWS_DB_NAME) \
    --engine aurora-postgresql \
    --storage-type aurora-iopt1 \
    --master-username silimate \
		--master-user-password silimate \
		--engine-version 15.3 \
		--storage-encrypted \
		--region $(AWS_REGION); \
	aws rds create-db-instance \
		--db-cluster-identifier $(AWS_DB_NAME) \
		--db-instance-identifier $(AWS_DB_NAME)-instance-1 \
		--engine aurora-postgresql \
		--enable-performance-insights \
		--monitoring-interval 60 \
		--monitoring-role arn:aws:iam::$(AWS_ACCOUNT_ID):role/rds-monitoring-role \
		--db-instance-class db.r5.large; \
	aws rds create-db-instance \
		--db-cluster-identifier $(AWS_DB_NAME) \
		--db-instance-identifier $(AWS_DB_NAME)-instance-2 \
		--engine aurora-postgresql \
		--enable-performance-insights \
		--monitoring-interval 60 \
		--monitoring-role arn:aws:iam::$(AWS_ACCOUNT_ID):role/rds-monitoring-role \
		--db-instance-class db.r5.large;
connect-rds-db:
	export EKS_VPC_ID=`aws eks describe-cluster --name=$(AWS_CLUSTER_NAME) --query cluster.resourcesVpcConfig.vpcId --output text`; \
	export RDS_VPC_ID=`aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier=='$(AWS_DB_NAME)-instance-1'].DBSubnetGroup.VpcId" --output text`; \
	export RDS_ENDPOINT=`aws rds describe-db-clusters --query "DBClusters[?DBClusterIdentifier=='$(AWS_DB_NAME)'].Endpoint" --output text`; \
	aws ec2 create-vpc-peering-connection --vpc-id $$EKS_VPC_ID --peer-vpc-id $$RDS_VPC_ID; \
	export VPC_PEER_CONN_ID=`aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$$EKS_VPC_ID" "Name=accepter-vpc-info.vpc-id,Values=$$RDS_VPC_ID" --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text`; \
	aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $$VPC_PEER_CONN_ID; \
	aws ec2 modify-vpc-peering-connection-options --vpc-peering-connection-id $$VPC_PEER_CONN_ID --requester-peering-connection-options AllowDnsResolutionFromRemoteVpc=true; \
	envsubst < rds.tmpl.yaml > rds.yaml
	kubectl apply -f rds.yaml
