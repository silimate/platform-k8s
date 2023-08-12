# Local or EKS (cloud)
K8S_CONTEXT := eks

# AWS Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s-test
AWS_DB_NAME := silimate-platform-db-dev
AWS_ROOT_ARN := arn:aws:iam::${AWS_ACCOUNT_ID}:root
AWS_ADDON_NAME := efs-csi-driver

# Utilities
get-endpoint:
	kubectl get svc --field-selector metadata.name=silimate-platform-service 
get-pods:
	kubectl get pods
get-events:
	kubectl get events --sort-by=.lastTimestamp
watch:
	watch "make get-events | tail -n 15"
debug:
	kubectl run -it --rm --restart=Never alpine --image=alpine sh

# Start/stop k8s services
start-local:
	kubectl apply -f k8s.yaml
stop-local:
	kubectl delete -f k8s.yaml

start-eks-prep:
	export RDS_ENDPOINT=`aws rds describe-db-clusters --db-cluster-identifier ${AWS_DB_NAME} --query 'DBClusters[0].Endpoint' --output text`; \
	sed -E "s/image: (.*)/image: ${AWS_ECR_REPO}\/\1:latest/;s/imagePullPolicy: Never/imagePullPolicy: Always/;s/ localhost/ $$RDS_ENDPOINT/" k8s.yaml > eks.k8s.yaml
start-eks: start-eks-prep
	kubectl apply -f eks.k8s.yaml
stop-eks:
	kubectl delete -f eks.k8s.yamlkubectl create namespace

redeploy:
	kubectl rollout restart deployment/silimate-platform-k8s-deployment

expose:
	kubectl apply -f load-balancer.yaml
unexpose:
	kubectl delete -f load-balancer.yaml


# EKS K8s provisioning
create-cluster:
	eksctl create cluster --name ${AWS_CLUSTER_NAME} --region ${AWS_REGION} --version=1.27 --with-oidc
delete-cluster:
	eksctl delete cluster --name ${AWS_CLUSTER_NAME} --region ${AWS_REGION}


# EKS connect to RDS
create-local-db:
	kubectl apply -f postgres.yaml

create-rds-db:
	export EKS_VPC_ID=`aws eks describe-cluster --name=${AWS_CLUSTER_NAME} --query cluster.resourcesVpcConfig.vpcId --output text`; \
	export EKS_SUBNET_IDS=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[*].SubnetId' --output text`; \
	export EKS_CIDR_BLOCK=`aws ec2 describe-vpcs --vpc-ids $$EKS_VPC_ID --query "Vpcs[].CidrBlock" --output text`; \
	\
	echo $$EKS_VPC_ID; \
	echo $$EKS_SUBNET_IDS; \
	echo $$EKS_CIDR_BLOCK; \
	\
	aws rds create-db-subnet-group --db-subnet-group-name ${AWS_CLUSTER_NAME}-db-subnet-group --db-subnet-group-description "RDS-EKS DB subnet group" --subnet-ids $$EKS_SUBNET_IDS; \
	aws ec2 create-security-group --group-name ${AWS_CLUSTER_NAME}-sec-group --description "RDS-EKS security group" --vpc-id "$$EKS_VPC_ID" --output text; \
	export RDS_SECURITY_GROUP_ID=`aws ec2 describe-security-groups --filters "Name=group-name,Values=rds-sec-group" --query 'SecurityGroups[0].GroupId' --output text`; \
	aws ec2 authorize-security-group-ingress --group-id $$RDS_SECURITY_GROUP_ID --protocol tcp --port 5432 --cidr $$EKS_CIDR_BLOCK; \
	\
	echo $$RDS_SECURITY_GROUP_ID; \
	aws rds create-db-cluster \
		--db-cluster-identifier ${AWS_DB_NAME} \
		--db-subnet-group-name rds-db-subnet-group \
		--database-name flow \
		--vpc-security-group-ids $$RDS_SECURITY_GROUP_ID \
		--engine aurora-postgresql \
		--storage-type aurora-iopt1 \
		--master-username silimate \
		--master-user-password silimate \
		--engine-version 15.3 \
		--storage-encrypted \
		--region ${AWS_REGION}; \
	aws rds create-db-instance \
		--db-cluster-identifier ${AWS_DB_NAME} \
		--db-instance-identifier ${AWS_DB_NAME}-instance-1 \
		--engine aurora-postgresql \
		--enable-performance-insights \
		--monitoring-interval 60 \
		--monitoring-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role \
		--db-instance-class db.r5.large; \
	aws rds create-db-instance \
		--db-cluster-identifier ${AWS_DB_NAME} \
		--db-instance-identifier ${AWS_DB_NAME}-instance-2 \
		--engine aurora-postgresql \
		--enable-performance-insights \
		--monitoring-interval 60 \
		--monitoring-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role \
		--db-instance-class db.r5.large
