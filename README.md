# CI/CD Pipeline on AWS with Jenkins & EKS

End-to-end DevOps project deploying a containerized web application on AWS using Terraform, Jenkins, and Kubernetes.

## Overview

This project provisions AWS infrastructure (VPC, EKS, EC2) using Terraform, sets up a Jenkins CI/CD pipeline that builds Docker images, pushes them to Amazon ECR, and deploys to an EKS cluster with Kubernetes manifests including services, ingress, HPA, and persistent storage.

## Repository Structure

- `infra/` — Terraform modules for VPC, EKS cluster, and Jenkins EC2 instance
- `devops-project/` — Application source code, Dockerfiles, Jenkinsfile, and Kubernetes manifests
- `screenshots/` — Project screenshots documenting each phase
- `FINAL_SUBMISSION_v2.md` — Full project report

## Tech Stack

- AWS (VPC, EKS, ECR, EC2, ALB)
- Terraform
- Jenkins
- Docker
- Kubernetes
- Nginx, Node.js (Express)
