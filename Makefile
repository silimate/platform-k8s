# Local or EKS (cloud)
K8S_CONTEXT := eks
K8S_ENV := dev

# AWS Configuration
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text)
AWS_REGION := us-west-1
AWS_ECR_REPO := ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s-${K8S_ENV}
AWS_ROOT_ARN := arn:aws:iam::${AWS_ACCOUNT_ID}:root

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
aws-auth:
	export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}; \
	envsubst < aws/aws-auth.tmpl.yaml > aws/aws-auth.yaml
	kubectl patch configmap/aws-auth -n kube-system --type merge --patch-file aws/aws-auth.yaml

local: worker-auth create-secrets create-config create-local-pvc start-db start expose

worker-auth:
	kubectl apply -f worker-auth.yaml
	kubectl create clusterrolebinding service-reader-pod --clusterrole=service-reader --serviceaccount=default:default

create-secrets:
	kubectl apply -f config/secrets.$(K8S_CONTEXT)-$(K8S_ENV).yaml
delete-secrets:
	kubectl delete -f config/secrets.$(K8S_CONTEXT)-$(K8S_ENV).yaml

create-ecr-secret:
	kubectl create secret docker-registry aws-ecr-secret \
		--docker-server=$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com \
		--docker-username=AWS \
		--docker-password=`aws ecr get-login-password --region $(AWS_REGION)`
delete-ecr-secret:
	kubectl delete secrets aws-ecr-secret

create-config:
	kubectl apply -f config/$(K8S_CONTEXT)-$(K8S_ENV).yaml
delete-config:
	kubectl delete -f config/$(K8S_CONTEXT)-$(K8S_ENV).yaml

start-db:
	kubectl apply -f postgres.yaml
stop-db:
	kubectl delete -f postgres.yaml
redeploy-db:
	kubectl rollout restart deployment/postgres

start:
	kubectl apply -f k8s.yaml
stop:
	kubectl delete -f k8s.yaml
redeploy:
	kubectl rollout restart deployment/silimate-platform-k8s-deployment

expose:
	kubectl apply -f load-balancer.yaml
unexpose:
	kubectl delete -f load-balancer.yaml

kill-workers:
	kubectl delete pods -l kubernetes_pod_operator=True


# Local PVC
create-local-pvc:
	kubectl apply -f local-pvc.yaml
delete-local-pvc:
	kubectl delete -f local-pvc.yaml


# EKS K8s provisioning
create-cluster:
	eksctl create cluster --name ${AWS_CLUSTER_NAME} --region ${AWS_REGION} --version=1.27 --with-oidc
delete-cluster:
	eksctl delete cluster --name ${AWS_CLUSTER_NAME} --region ${AWS_REGION}


# EKS connect to FS (local NFS or EFS)
create-efs:
	echo Creating role and policies...; \
	export OIDC_PROVIDER=`aws eks describe-cluster --name ${AWS_CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5`; \
	export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}; \
	export AWS_REGION=${AWS_REGION}; \
	envsubst < aws/aws-efs-csi-driver-trust-policy.tmpl.json > aws/aws-efs-csi-driver-trust-policy.json; \
	aws iam create-role --role-name AmazonEKS_EFS_CSI_DriverRole_${AWS_CLUSTER_NAME} --assume-role-policy-document file://"aws/aws-efs-csi-driver-trust-policy.json"; \
	aws iam attach-role-policy --role-name AmazonEKS_EFS_CSI_DriverRole_${AWS_CLUSTER_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy; \
	\
	echo Creating EFS addon for EKS...; \
	aws eks create-addon --cluster-name ${AWS_CLUSTER_NAME} --addon-name aws-efs-csi-driver --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EFS_CSI_DriverRole_${AWS_CLUSTER_NAME}; \
	\
	echo Getting cluster info...; \
	export EKS_VPC_ID=`aws eks describe-cluster --name=${AWS_CLUSTER_NAME} --query cluster.resourcesVpcConfig.vpcId --output text`; \
	export EKS_SUBNET_IDS=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[*].SubnetId' --output text`; \
	export EKS_CIDR_BLOCK=`aws ec2 describe-vpcs --vpc-ids $$EKS_VPC_ID --query "Vpcs[].CidrBlock" --output text`; \
	\
	echo EKS VPC ID: $$EKS_VPC_ID; \
	echo EKS subnet IDs: $$EKS_SUBNET_IDS; \
	echo EKS CIDR block: $$EKS_CIDR_BLOCK; \
	\
	echo Creating security group and authorizations...; \
	aws ec2 create-security-group --group-name ${AWS_CLUSTER_NAME}-sec-group --description "EFS-EKS security group" --vpc-id "$$EKS_VPC_ID" --output text; \
	export EKS_SECURITY_GROUP_ID=`aws ec2 describe-security-groups --filters "Name=group-name,Values=${AWS_CLUSTER_NAME}-sec-group" --query 'SecurityGroups[0].GroupId' --output text`; \
	echo EKS security group ID: $$EKS_SECURITY_GROUP_ID; \
	aws ec2 authorize-security-group-ingress --group-id $$EKS_SECURITY_GROUP_ID --protocol tcp --port 2049 --cidr $$EKS_CIDR_BLOCK; \
	\
	echo Creating EFS file system...; \
	aws efs create-file-system --region ${AWS_REGION} --performance-mode generalPurpose --creation-token ${AWS_CLUSTER_NAME}-efs; \
	export EFS_ID=`aws efs describe-file-systems --query "FileSystems[?CreationToken=='${AWS_CLUSTER_NAME}-efs'].FileSystemId" --output text`; \
	echo EFS ID: $$EFS_ID; \
	\
	echo Creating mount targets...; \
	sleep 5; \
	export EKS_SUBNET_ID=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[0].SubnetId' --output text`; \
	aws efs create-mount-target --file-system-id $$EFS_ID --subnet-id $$EKS_SUBNET_ID --security-groups $$EKS_SECURITY_GROUP_ID; \
	export EKS_SUBNET_ID=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[1].SubnetId' --output text`; \
	aws efs create-mount-target --file-system-id $$EFS_ID --subnet-id $$EKS_SUBNET_ID --security-groups $$EKS_SECURITY_GROUP_ID; \
	export EKS_SUBNET_ID=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$$EKS_VPC_ID" --query 'Subnets[2].SubnetId' --output text`; \
	aws efs create-mount-target --file-system-id $$EFS_ID --subnet-id $$EKS_SUBNET_ID --security-groups $$EKS_SECURITY_GROUP_ID; \
	\
	echo Creating storage class and PVC...; \
	envsubst < aws/efs-pvc.tmpl.yaml > aws/efs-pvc.yaml
	kubectl apply -f aws/efs-pvc.yaml
	echo Done creating EFS!
delete-efs:
	echo Deleting storage class and PVC!
	kubectl delete -f aws/efs-pvc.yaml; \
	echo Deleted storage class and PVC!
