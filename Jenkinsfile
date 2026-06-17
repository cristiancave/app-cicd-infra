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
                sh 'docker build -t ${DOCKER_IMAGE}:${IMAGE_TAG} -t ${DOCKER_IMAGE}:latest .'
                echo 'Docker image built successfully'
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo "Pushing image: ${DOCKER_IMAGE}:${IMAGE_TAG}"
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${DOCKER_IMAGE}:${IMAGE_TAG}
                        docker push ${DOCKER_IMAGE}:latest
                    '''
                }
                echo 'Image pushed to Docker Hub successfully'
            }
        }

        stage('Deploy to AKS') {
            steps {
                echo "Deploying to AKS cluster: ${AKS_CLUSTER}"
                withCredentials([azureServicePrincipal('azure-sp-appcicd')]) {
                    sh '''
                        az login --service-principal \
                            -u $AZURE_CLIENT_ID \
                            -p $AZURE_CLIENT_SECRET \
                            --tenant $AZURE_TENANT_ID
                        az aks get-credentials \
                            --resource-group ${AKS_RG} \
                            --name ${AKS_CLUSTER} \
                            --overwrite-existing
                        kubectl apply -f k8s/deployment.yaml
                        kubectl apply -f k8s/service.yaml
                        kubectl set image deployment/app-cicd app-cicd=${DOCKER_IMAGE}:${IMAGE_TAG}
                        kubectl rollout status deployment/app-cicd
                    '''
                }
                echo 'Deployment to AKS completed successfully'
            }
        }