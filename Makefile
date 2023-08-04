# Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s
AWS_ROOT_ARN := arn:aws:iam::$(AWS_ACCOUNT_ID):root

# For Docker K8s
platform-start:
	kubectl apply -f pg-pv-volume-claim.yaml
	kubectl apply -f pg-pv-claim.yaml
	kubectl apply -f platform.yaml
platform-stop:
	kubectl delete -f platform.yaml
platform-destroy: platform-stop
	kubectl delete -f pg-pv-volume-claim.yaml
	kubectl delete -f pg-pv-claim.yaml

# For EKS K8s
eks-setup: eks-create-cluster eks-create-iam-idmap eks-create-efs-addon eks-platform-start
eks-teardown: eks-platform-destroy eks-delete-efs-addon eks-delete-cluster

eks-create-cluster:
	eksctl create cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --version=1.27 --fargate
eks-register-cluster:
	eksctl register cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --provider EKS 
eks-delete-cluster:
	eksctl delete cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION)

eks-create-iam-idmap:
	eksctl create iamidentitymapping --cluster $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --arn $(AWS_ROOT_ARN) --group system:masters
	
eks-create-efs-addon:
	aws eks create-addon --cluster-name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --addon-name aws-efs-csi-driver
eks-delete-efs-addon:
	aws eks delete-addon --cluster-name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --addon-name aws-efs-csi-driver

eks-platform-start:
	sed -E "s/image: (.*)/image: $(AWS_ECR_REPO)\/\1:latest/" platform.yaml > platform.aws.yaml
	kubectl apply -f pg-pv-volume-claim.aws.yaml
	kubectl apply -f platform.aws.yaml
eks-platform-stop:
	kubectl delete -f platform.aws.yaml
eks-platform-destroy: eks-platform-stop
	kubectl delete -f pg-pv-volume-claim.aws.yaml
