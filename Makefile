# Local or EKS (cloud)
K8S_CONTEXT := eks

# AWS Configuration
AWS_ACCOUNT_ID := 596912105783
AWS_REGION := us-west-1
AWS_ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
AWS_CLUSTER_NAME := silimate-platform-k8s
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

eks-setup-efs-addon:
	eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster $(AWS_CLUSTER_NAME) \
    --role-name AmazonEKS_EFS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
    --approve
	TRUST_POLICY=$$(aws iam get-role --role-name AmazonEKS_EFS_CSI_DriverRole --query 'Role.AssumeRolePolicyDocument' | sed -e 's/efs-csi-controller-sa/efs-csi-*/' -e 's/StringEquals/StringLike/') && \
	aws iam update-assume-role-policy --role-name AmazonEKS_EFS_CSI_DriverRole --policy-document "$$TRUST_POLICY"
eks-create-addon:
	aws eks create-addon --cluster-name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --addon-name $(ADDON_NAME) --service-account-role-arn arn:aws:iam::$(AWS_ACCOUNT_ID):role/AmazonEKS_EBS_CSI_DriverRole
eks-delete-addon:
	aws eks delete-addon --cluster-name $(AWS_CLUSTER_NAME) --region $(AWS_REGION) --addon-name $(AWS_ADDON_NAME)
eks-check-addons:
	eksctl get addon --cluster $(AWS_CLUSTER_NAME) --region $(AWS_REGION)
