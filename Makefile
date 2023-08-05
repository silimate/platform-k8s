# Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s
AWS_ROOT_ARN := arn:aws:iam::$(AWS_ACCOUNT_ID):root

# For Docker K8s
platform-start:
	kubectl apply -f pg-pv-volume-claim.yaml
	kubectl apply -f pg-pv-volume.yaml
	kubectl apply -f platform.yaml
platform-stop:
	kubectl delete -f platform.yaml
platform-destroy: platform-stop
	kubectl delete -f pg-pv-volume-claim.yaml
	kubectl delete -f pg-pv-volume.yaml

# For EKS K8s
eks-start: eks-create-cluster eks-create-iam-idmap eks-create-ebs-addon eks-platform-start
eks-teardown: eks-platform-destroy eks-delete-ebs-addon eks-delete-cluster

eks-create-cluster:
	eksctl create cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --version=1.27 --with-oidc
eks-register-cluster:
	eksctl register cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --provider EKS 
eks-delete-cluster:
	eksctl delete cluster --name $(AWS_CLUSTER_NAME) --region $(AWS_REGION)

eks-create-iam-mapping:
	kubectl apply -f iam-mapping.yaml
eks-create-oidc-provider:
	eksctl utils associate-iam-oidc-provider --cluster $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --approve

eks-setup-ebs-addon:
	aws iam create-role --role-name AmazonEKS_EBS_CSI_Driver_Role --assume-role-policy-document file://"trust-policy.json"
	aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --role-name AmazonEKS_EBS_CSI_Driver_Role
	aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEKSClusterPolicy --role-name AmazonEKS_EBS_CSI_Driver_Role
	aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEKSDriverPolicy --role-name AmazonEKS_EBS_CSI_Driver_Role
eks-setup-efs-addon:
	eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster $(AWS_CLUSTER_NAME) \
    --role-name AmazonEKS_EFS_CSI_Driver_Role \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
    --approve
	TRUST_POLICY=$$(aws iam get-role --role-name AmazonEKS_EFS_CSI_Driver_Role --query 'Role.AssumeRolePolicyDocument' | \
	sed -e 's/efs-csi-controller-sa/efs-csi-*/' -e 's/StringEquals/StringLike/')
	aws iam update-assume-role-policy --role-name AmazonEKS_EFS_CSI_Driver_Role --policy-document "$$TRUST_POLICY"
eks-create-addon:
	aws eks create-addon --cluster-name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --addon-name $(ADDON_NAME) --service-account-role-arn arn:aws:iam::$(AWS_ACCOUNT_ID):role/AmazonEKS_EBS_CSI_DriverRole
eks-delete-addon:
	aws eks delete-addon --cluster-name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --addon-name $(ADDON_NAME)
eks-check-addons:
	eksctl get addon --cluster $(AWS_CLUSTER_NAME) --region $(AWS_REGION)

eks-create-ng:
	eksctl create nodegroup --cluster $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --name platform-ng --node-type m5.large --nodes 6 --nodes-min 6 --nodes-max 15

eks-platform-start:
	kubectl apply -f pg-pv-volume-claim.aws.yaml
	kubectl apply -f platform.aws.yaml
eks-platform-juststart:
	kubectl apply -f platform.aws.yaml
eks-platform-stop:
	kubectl delete -f platform.aws.yaml
eks-platform-destroy: eks-platform-stop
	kubectl delete -f pg-pv-volume-claim.aws.yaml

eks-pods:
	kubectl get pods
eks-nodes:
	kubectl get nodes
eks-events:
	kubectl get events --sort-by=.lastTimestamp
