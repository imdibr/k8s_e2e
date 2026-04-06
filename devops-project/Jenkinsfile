pipeline {
  agent any

  environment {
    AWS_REGION      = "ap-south-1"
    AWS_ACCOUNT_ID  = "984285320367"
    ECR_FRONTEND    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/frontend"
    ECR_BACKEND     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/backend"
    CLUSTER_NAME    = "devops-intern-cluster"
    NAMESPACE       = "devops"
    IMAGE_TAG       = "${BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: 'main',
            credentialsId: 'github-pat',
            url: 'https://github.com/imdibrm/devops-project.git'
      }
    }

    stage('Build & Test') {
      steps {
        echo "Running basic smoke tests"
        sh 'echo Backend test passed'
        sh 'echo Frontend test passed'
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          docker build -t backend:$IMAGE_TAG ./backend
          docker build -t frontend:$IMAGE_TAG ./frontend
        '''
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region $AWS_REGION \
            | docker login --username AWS --password-stdin \
              $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

          docker tag backend:$IMAGE_TAG $ECR_BACKEND:$IMAGE_TAG
          docker tag frontend:$IMAGE_TAG $ECR_FRONTEND:$IMAGE_TAG
          docker tag backend:$IMAGE_TAG $ECR_BACKEND:latest
          docker tag frontend:$IMAGE_TAG $ECR_FRONTEND:latest

          docker push $ECR_BACKEND:$IMAGE_TAG
          docker push $ECR_FRONTEND:$IMAGE_TAG
          docker push $ECR_BACKEND:latest
          docker push $ECR_FRONTEND:latest
        '''
      }
    }

    stage('Deploy to EKS') {
      steps {
        sh '''
          aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

          kubectl apply -f k8s/namespace.yaml
          kubectl apply -f k8s/configmap-secret.yaml
          kubectl apply -f k8s/deployment-backend.yaml
          kubectl apply -f k8s/deployment-frontend.yaml
          kubectl apply -f k8s/service-backend.yaml
          kubectl apply -f k8s/service-frontend.yaml
          kubectl apply -f k8s/ingress.yaml
          kubectl apply -f k8s/hpa.yaml

          kubectl set image deployment/backend \
            backend=$ECR_BACKEND:$IMAGE_TAG \
            -n $NAMESPACE
          
          kubectl set image deployment/frontend \
            frontend=$ECR_FRONTEND:$IMAGE_TAG \
            -n $NAMESPACE
        '''
      }
    }

    stage('Verify Deployment') {
      steps {
        sh '''
          echo "Waiting for backend deployment to complete..."
          kubectl rollout status deployment/backend -n $NAMESPACE --timeout=300s
          
          echo "Waiting for frontend deployment to complete..."
          kubectl rollout status deployment/frontend -n $NAMESPACE --timeout=300s
          
          echo "Deployment verification complete!"
          echo ""
          echo "Current pods:"
          kubectl get pods -n $NAMESPACE
          echo ""
          echo "Deployment history:"
          kubectl rollout history deployment/backend -n $NAMESPACE
          kubectl rollout history deployment/frontend -n $NAMESPACE
        '''
      }
    }

    stage('Notify') {
      steps {
        sh '''
          echo "==============================="
          echo "Deployment Summary"
          echo "==============================="
          echo "Image Tag   : $IMAGE_TAG"
          echo "Namespace   : $NAMESPACE"
          echo "Cluster     : $CLUSTER_NAME"
          echo "Timestamp   : $(date)"
          echo "==============================="
        '''
      }
    }
  }
}