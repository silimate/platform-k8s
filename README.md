# Silimate Platform K8s
Kubernetes configuration/provisioning for deployments, including Postgres database Docker

## Creating an Airflow user
```
airflow users create --username silimate --role Admin --email contact@silimate.com --firstname Silimate --lastname Flow
```

## Deployment guide
```
make eks-create-cluster
make eks-iam-idmapping
```
Go to AWS EKS Console and install Amazon EBS CSI Driver Add-on
```
make eks-platform-start
```