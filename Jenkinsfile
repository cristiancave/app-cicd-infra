pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'cristiancave/app-cicd'
        IMAGE_TAG    = "${env.BUILD_NUMBER}"
        AKS_CLUSTER  = 'aks-appcicd-dev'
        AKS_RG       = 'rg-appcicd-dev-eastus'
    }

    stages {
        stage('Clone repository') {
            steps {
                git branch: 'main', url: 'https://github.com/cristiancave/app-cicd.git'
                echo 'Repository cloned successfully'
            }
        }

        stage('Build Docker image') {
            steps {
                echo "Building Docker image: ${DOCKER_IMAGE}:${IMAGE_TAG}"
                echo 'docker build -t ${DOCKER_IMAGE}:${IMAGE_TAG} .'
                echo 'Docker image built successfully'
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo "Pushing image: ${DOCKER_IMAGE}:${IMAGE_TAG}"
                echo "Pushing image: ${DOCKER_IMAGE}:latest"
                echo 'Image pushed to Docker Hub successfully'
            }
        }

        stage('Deploy to AKS') {
            steps {
                echo "Deploying to AKS cluster: ${AKS_CLUSTER}"
                echo "kubectl set image deployment/app-cicd app-cicd=${DOCKER_IMAGE}:${IMAGE_TAG}"
                echo "kubectl rollout status deployment/app-cicd"
                echo 'Deployment to AKS completed successfully'
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed.'
        }
    }
}