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
aws-auth-prep:
	export AWS_ACCOUNT_ID=`aws sts get-caller-identity --query Account --output text`; \
	envsubst < aws-auth.tmpl.yaml > aws-auth.yaml
aws-auth: aws-auth-prep
	kubectl patch configmap/aws-auth -n kube-system --type merge --patch-file aws-auth.yaml

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
	kubectl delete -f eks.k8s.yaml

worker-auth:
	kubectl apply -f worker-auth.yaml
	kubectl create clusterrolebinding service-reader-pod --clusterrole=service-reader --serviceaccount=default:default

redeploy:
	kubectl rollout restart deployment/silimate-platform-k8s-deployment

expose:
	kubectl apply -f load-balancer.yaml
unexpose:
	kubectl delete -f load-balancer.yaml

kill-workers:
	kubectl delete pods -l kubernetes_pod_operator=True


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
	aws rds create-db-subnet-group --db-subnet-group-name ${AWS_CLUSTER_NAME}-db-subnet-group --db-subnet-group-description "RDS-EKS DB subnet group" --subnet-ids $$EKS_SUBNET_∂DS; \
	aws ec2 create-security-group --group-name ${AWS_CLUSTER_NAME}-sec-group --description "RDS-EKS security group" --vpc-id "$$EKS_VPC_ID" --output text; \
	export EKS_SECURITY_GROUP_ID=`aws ec2 describe-security-groups --filters "Name=group-name,Values=${AWS_CLUSTER_NAME}-sec-group" --query 'SecurityGroups[0].GroupId' --output text`; \
	aws ec2 authorize-security-group-ingress --group-id $$EKS_SECURITY_GROUP_ID --protocol tcp --port 5432 --cidr $$EKS_CIDR_BLOCK; \
	\
	echo $$EKS_SECURITY_GROUP_ID; \
	aws rds create-db-cluster \
		--db-cluster-identifier ${AWS_DB_NAME} \
		--db-subnet-group-name rds-db-subnet-group \
		--database-name flow \
		--vpc-security-group-ids $$EKS_SECURITY_GROUP_ID \
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

create-nfs:
	echo TODO

create-efs-addon:
	export OIDC_PROVIDER=`aws eks describe-cluster --name ${AWS_CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5`; \
	export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}; \
	export AWS_REGION=${AWS_REGION}; \
	envsubst < aws-efs-csi-driver-trust-policy.tmpl.json > aws-efs-csi-driver-trust-policy.json; \
	aws iam create-role --role-name AmazonEKS_EFS_CSI_DriverRole_${AWS_CLUSTER_NAME} --assume-role-policy-document file://"aws-efs-csi-driver-trust-policy.json"; \
	aws iam attach-role-policy --role-name AmazonEKS_EFS_CSI_DriverRole_${AWS_CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy; \
	aws eks create-addon --cluster-name ${AWS_CLUSTER_NAME} --addon-name aws-efs-csi-driver --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EFS_CSI_DriverRole_${AWS_CLUSTER_NAME}
create-efs: create-efs-addon
	export EKS_VPC_ID=`aws eks describe-cluster --name=${AWS_CLUSTER_NAME} --query cluster.resourcesVpcConfig.vpcId --output text`; \
	export EKS_SUBNET_IDS=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[*].SubnetId' --output text`; \
	export EKS_CIDR_BLOCK=`aws ec2 describe-vpcs --vpc-ids $$EKS_VPC_ID --query "Vpcs[].CidrBlock" --output text`; \
	\
	echo $$EKS_VPC_ID; \
	echo $$EKS_SUBNET_IDS; \
	echo $$EKS_CIDR_BLOCK; \
	\
	aws ec2 create-security-group --group-name ${AWS_CLUSTER_NAME}-sec-group --description "EFS-EKS security group" --vpc-id "$$EKS_VPC_ID" --output text; \
	export EKS_SECURITY_GROUP_ID=`aws ec2 describe-security-groups --filters "Name=group-name,Values=${AWS_CLUSTER_NAME}-sec-group" --query 'SecurityGroups[0].GroupId' --output text`; \
	aws ec2 authorize-security-group-ingress --group-id $$EKS_SECURITY_GROUP_ID --protocol tcp --port 2049 --cidr $$EKS_CIDR_BLOCK; \
	\
	aws efs create-file-system --region ${AWS_REGION} --performance-mode generalPurpose --creation-token ${AWS_CLUSTER_NAME}-efs; \
	export EFS_ID=`aws efs describe-file-systems --query "FileSystems[?CreationToken=='${AWS_CLUSTER_NAME}-efs'].FileSystemId" --output text`; \
	echo $$EFS_ID; \
	\
	export EKS_SUBNET_ID=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[0].SubnetId' --output text`; \
	aws efs create-mount-target --file-system-id $$EFS_ID --subnet-id $$EKS_SUBNET_ID --security-groups $$EKS_SECURITY_GROUP_ID; \
	\
	export EKS_SUBNET_ID=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[1].SubnetId' --output text`; \
	aws efs create-mount-target --file-system-id $$EFS_ID --subnet-id $$EKS_SUBNET_ID --security-groups $$EKS_SECURITY_GROUP_ID; \
	\
	export EKS_SUBNET_ID=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[2].SubnetId' --output text`; \
	aws efs create-mount-target --file-system-id $$EFS_ID --subnet-id $$EKS_SUBNET_ID --security-groups $$EKS_SECURITY_GROUP_ID; \
