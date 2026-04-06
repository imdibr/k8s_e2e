# Submission

## CI/CD Pipeline on AWS with Jenkins & EKS

**Region:** ap-south-1 (Mumbai)  
**GitHub:** github.com/imdibrm/devops-project

---

## Table of Contents

1. Project Overview
2. Phase 1 — AWS Infrastructure & VPC Setup
3. Phase 2 — Amazon EKS Cluster Setup
4. Phase 3 — CI/CD Pipeline with Jenkins
5. Phase 4 — Kubernetes Application Deployment
6. Phase 5 — Documentation & Security
7. Issues Encountered & Resolved
8. Final Submission Checklist

---

## 1. Project Overview

This project implements a production-grade DevOps infrastructure on AWS, built entirely with **Terraform (Infrastructure as Code)**. A full-stack application is containerized, pushed to Amazon ECR, and deployed to an EKS Kubernetes cluster via an automated Jenkins CI/CD pipeline.

| Layer | Technology | Details |
|-------|-----------|---------|
| IaC | Terraform | 3 modules (vpc, eks, jenkins) — 47 managed resources |
| Networking | Custom VPC | 10.0.0.0/16 — 2 public + 2 private subnets, IGW, NAT, route tables |
| CI/CD | Jenkins on EC2 | t3.micro, Ubuntu 22.04, .war install, IAM Instance Profile |
| Orchestration | Amazon EKS | Kubernetes 1.32, 2× t3.micro worker nodes in private subnets |
| Containers | Docker + ECR | Frontend (nginx:alpine) + Backend (node:18-alpine) |
| Ingress | AWS ALB | Internet-facing, path-based routing (/ → frontend, /api → backend) |
| Autoscaling | HPA | Backend: min 1, max 2, CPU threshold 60% |
| Storage | PVC + EBS CSI | PostgreSQL StatefulSet with 1Gi gp2 persistent volume |

---

## 2. Phase 1 — AWS Infrastructure & VPC Setup

### 2.1 VPC Architecture

| Component | Configuration |
|-----------|--------------|
| VPC | CIDR `10.0.0.0/16`, DNS hostnames & resolution enabled |
| Public Subnet 1 | `10.0.0.0/24` — ap-south-1a (Jenkins, ALB, NAT Gateway) |
| Public Subnet 2 | `10.0.1.0/24` — ap-south-1b (ALB multi-AZ) |
| Private Subnet 1 | `10.0.10.0/24` — ap-south-1a (EKS worker node 1) |
| Private Subnet 2 | `10.0.11.0/24` — ap-south-1b (EKS worker node 2) |
| Internet Gateway | Attached to VPC — routes public subnet traffic to internet |
| NAT Gateway | In public subnet 1 with Elastic IP — private subnet outbound |
| Route Tables | Public RT → IGW (0.0.0.0/0), Private RT → NAT (0.0.0.0/0) |


### Architecture Diagram

https://tinyurl.com/yc238dhf

### 2.2 Security Groups

| Security Group | Inbound Rules | Principle |
|---------------|--------------|-----------|
| Jenkins SG | Port 22 (SSH) — operator IP only, Port 8080 (Jenkins UI) — operator IP only | Least privilege — IP detected dynamically via `data.http.myip` |
| EKS Cluster SG | All traffic from VPC CIDR (10.0.0.0/16) | Cluster ↔ node communication |
| ALB SG | Port 80 from 0.0.0.0/0 | Internet-facing (auto-created by ALB controller) |

### 2.3 IAM Roles

| Role | Attached To | Policies |
|------|-----------|----------|
| `jenkins-ec2-role` | Jenkins EC2 (Instance Profile) | ECR PowerUser, EKS ClusterPolicy, EKS WorkerNodePolicy |
| `eks-cluster-role` | EKS Control Plane | AmazonEKSClusterPolicy |
| `eks-node-role` | Worker Nodes | WorkerNodePolicy, CNI Policy, ECR ReadOnly |
| `alb-controller-role` | ALB Controller (IRSA) | Custom policy — ELB, EC2 |

Jenkins uses IAM Instance Profile. ALB Controller uses IRSA (IAM Roles for Service Accounts) with OIDC federation.

### 2.4 Jenkins EC2 Instance

| Setting | Value |
|---------|-------|
| AMI | Ubuntu 22.04 LTS  |
| Instance Type | t3.micro |
| Subnet | Public subnet 1 (10.0.0.0/24) |
| Key Pair | `devops-key` |
| Installed (user_data) | Java 17, Jenkins .war, Docker, kubectl, AWS CLI v2, Git, 2GB swap |
| JVM | `-Xmx256m` (t3.micro memory optimization) |

![alt text](screenshots/Screenshot%202026-04-01%20at%209.08.05%20PM.png)
Jenkins Dashboard screenshot + VPC Architecture Diagram



---

## 3. Phase 2 — Amazon EKS Cluster Setup

### 3.1 Cluster Configuration

| Setting | Value |
|---------|-------|
| Cluster Name | `devops-intern-cluster` |
| Kubernetes Version | 1.32 |
| VPC | Custom VPC (10.0.0.0/16) |
| Subnets | Private subnets only (worker placement) |
| Endpoint Access | Public + Private enabled |
| Security Group | `eks-cluster-sg` — VPC CIDR allowed inbound |

### 3.2 Node Group

| Setting | Value |
|---------|-------|
| Node Group Name | `devops-intern-nodes` |
| Instance Type | t3.micro (free tier constraint) |
| Desired / Min / Max | 2 / 2 / 4 |
| Subnets | Private subnets (10.0.10.0/24, 10.0.11.0/24) |
| Launch Template | Custom — `--max-pods=20` override via bootstrap args |

> **Note:** The assignment specifies t3.medium, but t3.micro was used due to free tier budget constraints. This introduced pod capacity limitations (4 pods/node ENI limit) which are documented in Section 7.

### 3.3 Cluster Add-ons 

| Add-on | Method | Purpose |
|--------|--------|---------|
| CoreDNS | EKS managed add-on (Terraform) | Cluster DNS resolution |
| kube-proxy | EKS managed add-on (Terraform) | Service networking / iptables |
| VPC CNI | EKS managed add-on (Terraform) | Pod networking with VPC IPs |
| AWS Load Balancer Controller | Helm chart via Terraform | Creates ALB from Ingress resource |
| EBS CSI Driver | EKS managed add-on | Dynamic EBS volume provisioning for PVC |
| Metrics Server | Helm chart via Terraform | HPA CPU metrics (scaled to 0 replicas — see Section 7) |

### 3.4 OIDC & IRSA

An OpenID Connect (OIDC) provider was created for the EKS cluster to enable **IAM Roles for Service Accounts (IRSA)**. This allows the AWS Load Balancer Controller to assume an IAM role without static credentials, by annotating its Kubernetes ServiceAccount with the IAM role ARN.

### 3.5 kubectl Access

```bash
aws eks update-kubeconfig --name devops-intern-cluster --region ap-south-1
```

kubectl get nodes (Ready) + kubectl get pods -n kube-system (healthy)
![alt text](screenshots/Screenshot%202026-04-03%20at%206.43.06%20PM.png)
![alt text](screenshots/Screenshot%202026-04-03%20at%206.43.19%20PM.png)

---

## 4. Phase 3 — CI/CD Pipeline with Jenkins

### 4.1 Repository Structure

```
devops-project/
├── Jenkinsfile                       # 7-stage declarative pipeline
├── backend/
│   ├── Dockerfile                    # FROM node:18-alpine
│   ├── app.js                        # Express.js — /health, /api, /
│   └── package.json
├── frontend/
│   ├── Dockerfile                    # FROM nginx:alpine
│   └── index.html                    # UI with fetch('/api')
└── k8s/
    ├── namespace.yaml                # devops namespace
    ├── configmap-secret.yaml         # APP_ENV, DB_HOST, DB_PASSWORD
    ├── deployment-backend.yaml       # 1 replica, liveness/readiness
    ├── deployment-frontend.yaml      # 1 replica, liveness/readiness
    ├── service-backend.yaml          # ClusterIP → port 3000
    ├── service-frontend.yaml         # ClusterIP → port 80
    ├── ingress.yaml                  # ALB, path-based routing
    ├── hpa.yaml                      # CPU-based autoscaling
    └── pv-pvc.yaml                   # PostgreSQL StatefulSet + PVC
```

### 4.2 Jenkinsfile — Pipeline Stages

| Stage | What It Does |
|-------|-------------|
| **1. Checkout** | Clones `main` branch from GitHub using PAT credential (`github-pat`) |
| **2. Build & Test** | Runs smoke tests (echo-based verification) |
| **3. Docker Build** | `docker build -t backend:$BUILD_NUMBER ./backend` and `docker build -t frontend:$BUILD_NUMBER ./frontend` |
| **4. Push to ECR** | Authenticates via `aws ecr get-login-password`, pushes with both `:BUILD_NUMBER` and `:latest` tags |
| **5. Deploy to EKS** | Updates kubeconfig, applies manifests individually, then `kubectl set image` to update containers |
| **6. Verify** | `kubectl rollout status --timeout=300s` for both deployments |
| **7. Notify** | Prints deployment summary (image tag, namespace, timestamp) |

### 4.3 Pipeline Environment Variables

```groovy
environment {
    AWS_REGION      = "ap-south-1"
    AWS_ACCOUNT_ID  = "984285320367"
    ECR_FRONTEND    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/frontend"
    ECR_BACKEND     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/backend"
    CLUSTER_NAME    = "devops-intern-cluster"
    NAMESPACE       = "devops"
    IMAGE_TAG       = "${BUILD_NUMBER}"
}
```

**Security:** No static AWS credentials in Jenkinsfile. Authentication is handled via IAM Instance Profile attached to the Jenkins EC2 instance.

![alt text](screenshots/Screenshot%202026-04-01%20at%209.08.05%20PM.png)
Pipeline — all stages green


---

## 5. Phase 4 — Kubernetes Application Deployment

### 5.1 Namespace

All application resources deployed in the `devops` namespace.

### 5.2 Deployments

| Setting | Backend | Frontend |
|---------|---------|----------|
| Image | `984285320367.dkr.ecr.ap-south-1.amazonaws.com/backend:BUILD_NUMBER` | `...frontend:BUILD_NUMBER` |
| Replicas | 1 | 1 |
| Port | 3000 | 80 |
| CPU Request / Limit | 20m / 50m | 10m / 30m |
| Memory Request / Limit | 32Mi / 64Mi | 16Mi / 48Mi |
| Liveness Probe | HTTP GET /health:3000 (15s delay, 20s period) | HTTP GET /:80 (10s delay, 20s period) |
| Readiness Probe | HTTP GET /health:3000 (5s delay, 10s period) | HTTP GET /:80 (5s delay, 10s period) |
| Update Strategy | RollingUpdate (maxSurge:0, maxUnavailable:1) | RollingUpdate (maxSurge:0, maxUnavailable:1) |

### 5.3 Services

| Service | Type | 
|---------|------|--------------|
| `backend-service` | ClusterIP | 
| `frontend-service` | ClusterIP |

### 5.4 Ingress (AWS ALB)

| Setting | Value |
|---------|-------|
| Ingress Class | `alb` (AWS Load Balancer Controller) |
| Scheme | `internet-facing` |
| Target Type | `ip` (direct pod IP targeting) |
| Route: `/api` | → backend-service:80 |
| Route: `/` | → frontend-service:80 |

### 5.5 Horizontal Pod Autoscaler (HPA)

| Setting | Value |
|---------|-------|
| Target | backend deployment |
| API Version | autoscaling/v2 |
| Min / Max Replicas | 1 / 2 |
| Metric | CPU utilization |
| Threshold | 60% |


### 5.6 Persistent Volume — PostgreSQL StatefulSet

| Setting | Value |
|---------|-------|
| Database | PostgreSQL 15 (postgres:15-alpine) |
| Kind | StatefulSet, 1 replica |
| Headless Service | `postgres-service` (clusterIP: None) |
| PVC | 1Gi, `gp2` StorageClass (EBS CSI Driver) |
| Mount Path | /var/lib/postgresql/data |
| CPU / Memory | 30m–100m / 64Mi–128Mi |

> **Note:** PostgreSQL StatefulSet was excluded from the Jenkins pipeline (`kubectl apply` targets individual manifests, not the entire k8s/ directory) to conserve pod capacity on t3.micro nodes. PVC was demonstrated separately in Bound state.


![alt text](screenshots/Screenshot%202026-04-01%20at%2012.07.48%20AM.png)
`kubectl get all -n devops`

![alt text](screenshots/Screenshot%202026-04-01%20at%201.14.07%20AM.png)
`kubectl get ingress -n devops`

![alt text](screenshots/Screenshot%202026-04-01%20at%2012.01.36%20AM.png)
`kubectl get hpa -n devops`

![alt text](screenshots/Screenshot%202026-04-01%20at%2012.30.14%20AM.png)
`kubectl get pvc -n devops`

![alt text](screenshots/Screenshot%202026-03-31%20at%206.22.58%20AM.png)

![alt text](screenshots/Screenshot%202026-03-31%20at%206.19.14%20AM.png)
`ALB URL`

---

## 6. Phase 5 — Documentation & Security

### 6.1 GitHub Repository

All source code, Dockerfiles, Jenkinsfile, and Kubernetes manifests are committed to: `https://github.com/imdibrm/devops-project.git`

Terraform infrastructure code is maintained separately in the `infra/` directory with three modules: `vpc`, `eks`, `jenkins`.

### 6.2 Security Checklist

| Requirement | Implementation | Status |
|------------|----------------|--------|
| No AWS credentials in code | IAM Instance Profile for Jenkins, IRSA for ALB Controller | Done |
| Workers in private subnets | Node group deployed only in private subnets | Done |
| Database in private subnets | PostgreSQL runs on EKS nodes in private subnets | Done |
| Security groups — least privilege | Jenkins SG: operator IP only (dynamic detection) | Done |
| Kubernetes Secrets for sensitive data | DB_PASSWORD, SECRET_KEY stored as K8s Secret (base64) | Done |
| IAM roles, not access keys | Instance Profile + IRSA — zero static keys in entire project | Done |
| Jenkins not open to 0.0.0.0/0 | SG uses `data.http.myip` for dynamic IP restriction | Done |

---

## 7. Issues Encountered & Resolved

| # | Issue | Root Cause | Resolution |
|---|-------|-----------|------------|
| 1 | ALB Controller CrashLoopBackOff | IRSA not configured — controller couldn't assume IAM role | Created OIDC provider, IAM role with trust policy, annotated ServiceAccount |
| 2 | ALB not created from Ingress | Public subnets missing Kubernetes discovery tags | Added `kubernetes.io/role/elb = 1` and cluster shared tags |
| 3 | Jenkins kubectl "access denied" | Jenkins IAM role missing EKS policies | Added EKSClusterPolicy + EKSWorkerNodePolicy to jenkins-ec2-role |
| 4 | Frontend pod Pending → ALB 503 | t3.micro ENI limit: 4 pods/node. PostgreSQL + metrics-server consumed slots | Excluded PostgreSQL from pipeline, scaled metrics-server to 0 |
| 5 | Jenkins unreachable after restart | Public IP changed → SG still had old IP | `terraform apply` refreshes `data.http.myip` |
| 6 | PVC stuck in Pending state | EBS CSI Driver not yet running | Verified CSI driver add-on active, PVC bound after driver ready |
| 7 | Pipeline deployed PostgreSQL unintentionally | Using `kubectl apply -f k8s/` applied all manifests | Changed to individual `kubectl apply -f k8s/<file>` per manifest |
| 8 | Jenkins OOM on t3.micro | Default JVM heap too large for 1GB RAM | Set `-Xmx256m` + 2GB swap in user_data |

### t3.micro Pod Capacity 

t3.micro has 2 ENIs × 2 IPs each = **4 pod slots per node** (max-pods=4). With 2 nodes = 8 total slots.

| Pod | Namespace | Required? |
|-----|-----------|-----------|
| aws-node (×2) | kube-system | Yes — VPC CNI DaemonSet |
| kube-proxy (×2) | kube-system | Yes — iptables DaemonSet |
| coredns | kube-system | Yes — DNS |
| ALB Controller | kube-system | Yes — creates ALB from Ingress |
| **backend** | devops | Application pod |
| **frontend** | devops | Application pod |

**8/8 slots used — zero spare capacity.** This required careful optimization: metrics-server scaled to 0, PostgreSQL excluded, replicas set to 1.

---

