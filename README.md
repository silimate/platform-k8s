# Silimate Platform K8s
Kubernetes configuration/provisioning for deployments, including Postgres database Docker

## AWS EKS Deployment guide
Go to AWS and do the following:
- Spin up RDS Postgres instance
  - Type: Aurora (PostgreSQL Compatible)
  - Version: latest
  - Name: `silimate-platform-db`
  - Username: `silimate`
  - Password: auto-generated
  - Instance type: `db.r5.large`
  - Don't create an aurora replica
  - VPC: K8s VPC
  - DevOps Guru: off
- Put password as secret into all GitHub actions that generate Docker containers
- 