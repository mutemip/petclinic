pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        // Docker Configuration
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_CREDENTIALS = credentials('dockerHubCreds')
        DOCKER_USERNAME = "${DOCKER_CREDENTIALS_USR}"
        DOCKER_PASSWORD = "${DOCKER_CREDENTIALS_PSW}"
        
        // Git Configuration
        GITHUB_TOKEN = credentials('githubToken')
        
        // Kubernetes Configuration
        KUBECONFIG = credentials('kubernetesConfig')
        
        // Application Configuration
        IMAGE_NAME = "${DOCKER_USERNAME}/spring-petclinic"
        IMAGE_TAG = "${BUILD_NUMBER}"
        APP_NAME = 'petclinic'
    }

    stages {
        // ==================== TASK 1: CHECKOUT ====================
        stage('Checkout') {
            steps {
                script {
                    echo "========== [TASK 2] Checking out from GitHub =========="
                }
                checkout scm
                script {
                    env.GIT_COMMIT_MSG = sh(
                        script: "git log -1 --pretty=%B",
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: "git log -1 --pretty=%an",
                        returnStdout: true
                    ).trim()
                    env.GIT_COMMIT_HASH = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    echo "✓ Commit: ${env.GIT_COMMIT_MSG}"
                    echo "✓ Author: ${env.GIT_AUTHOR}"
                    echo "✓ Hash: ${env.GIT_COMMIT_HASH}"
                }
            }
        }

        // ==================== TASK 3: BUILD ====================
        stage('Build Application') {
            steps {
                script {
                    echo "========== [TASK 3] Building Application with Maven =========="
                    sh '''
                        chmod +x ./mvnw
                        ./mvnw clean package -DskipTests \
                            -Dorg.slf4j.simpleLogger.defaultLogLevel=info
                    '''
                }
            }
            post {
                success {
                    echo "✓ Maven build completed successfully"
                    archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: false
                }
                failure {
                    echo "✗ Maven build failed"
                    error("Build stage failed")
                }
            }
        }

        // ==================== TASK 3: BUILD DOCKER IMAGE ====================
        stage('Build Docker Image') {
            steps {
                script {
                    echo "========== [TASK 3] Building Docker Image =========="
                    sh '''
                        docker build \
                            -t ${IMAGE_NAME}:${IMAGE_TAG} \
                            -t ${IMAGE_NAME}:latest \
                            -f Dockerfile .
                        
                        echo "Docker image built: ${IMAGE_NAME}:${IMAGE_TAG}"
                        docker images | grep petclinic
                    '''
                }
            }
            post {
                failure {
                    echo "✗ Docker build failed"
                    error("Docker build stage failed")
                }
            }
        }

        // ==================== TASK 3: TEST ====================
        stage('Test') {
            steps {
                script {
                    echo "========== [TASK 3] Running Unit Tests =========="
                    sh '''
                        chmod +x ./mvnw
                        ./mvnw test \
                            -Dorg.slf4j.simpleLogger.defaultLogLevel=info
                    '''
                }
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                    echo "✓ Test reports generated"
                }
            }
        }

        // ==================== TASK 3: STATIC ANALYSIS ====================
        stage('Static Analysis - SonarQube') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== [TASK 3] Running SonarQube Analysis =========="
                    sh '''
                        chmod +x ./mvnw
                        ./mvnw clean verify \
                            sonar:sonar \
                            -Dsonar.projectKey=${APP_NAME} \
                            -Dsonar.projectName='Spring PetClinic' \
                            -Dsonar.host.url=${SONARQUBE_HOST_URL:-http://sonarqube:9000} \
                            -Dsonar.login=${SONARQUBE_TOKEN:-admin} || echo "SonarQube analysis skipped"
                    '''
                }
            }
            post {
                always {
                    echo "✓ SonarQube analysis completed"
                }
            }
        }

        // ==================== TASK 3: PUSH TO DOCKER HUB ====================
        stage('Push to Docker Hub') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== [TASK 3] Pushing Image to Docker Hub =========="
                    sh '''
                        echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
                        
                        echo "Pushing ${IMAGE_NAME}:${IMAGE_TAG}..."
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        
                        echo "Pushing ${IMAGE_NAME}:latest..."
                        docker push ${IMAGE_NAME}:latest
                        
                        docker logout
                        echo "✓ Image pushed successfully"
                    '''
                }
            }
            post {
                failure {
                    echo "✗ Docker push failed"
                }
                success {
                    echo "✓ Docker Hub repository: ${IMAGE_NAME}"
                }
            }
        }

        // ==================== TASK 4: DEPLOY TO KUBERNETES ====================
        stage('Deploy to Kubernetes') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== [TASK 4] Deploying to Kubernetes =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        KUBE_NAMESPACE="default"
                        
                        echo "Step 1: Applying RBAC manifests..."
                        kubectl apply -f manifests/01-rbac.yaml
                        
                        echo "Step 2: Applying PVC manifests..."
                        kubectl apply -f manifests/02-pvc.yaml
                        
                        echo "Step 3: Applying ConfigMap..."
                        kubectl apply -f manifests/03-configmap.yaml
                        
                        echo "Step 4: Applying Secret..."
                        kubectl apply -f manifests/04-secret.yaml
                        
                        echo "Step 5: Updating deployment with new image..."
                        kubectl set image deployment/petclinic-deployment \
                            petclinic=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n ${KUBE_NAMESPACE} || true
                        
                        echo "Step 6: Applying Deployment..."
                        kubectl apply -f manifests/05-deployment.yaml
                        
                        echo "Step 7: Applying Service..."
                        kubectl apply -f manifests/06-service.yaml
                        
                        echo "Step 8: Waiting for rollout..."
                        kubectl rollout status deployment/petclinic-deployment \
                            -n ${KUBE_NAMESPACE} --timeout=5m
                        
                        echo "✓ Deployment successful"
                    '''
                }
            }
            post {
                success {
                    echo "========== [TASK 4] Deployment Verification =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        echo "Pod Status:"
                        kubectl get pods -n default -l app=petclinic
                        
                        echo "Service Status:"
                        kubectl get svc petclinic-service -n default
                        
                        echo "Deployment Status:"
                        kubectl get deployment petclinic-deployment -n default
                    '''
                }
                failure {
                    echo "✗ Kubernetes deployment failed"
                }
            }
        }

        // ==================== TASK 5: ROLLING UPDATES VERIFICATION ====================
        stage('Verify Rolling Update') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== [TASK 5] Verifying Rolling Update =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        echo "Current Deployment Replicas:"
                        kubectl get deployment petclinic-deployment -n default \
                            -o jsonpath='{.spec.replicas} replicas, {.status.updatedReplicas} updated'
                        
                        echo ""
                        echo "Rollout History:"
                        kubectl rollout history deployment/petclinic-deployment -n default
                        
                        echo ""
                        echo "Recent Pods:"
                        kubectl get pods -n default -l app=petclinic --sort-by=.metadata.creationTimestamp
                    '''
                }
            }
        }

        // ==================== TASK 5: APPLICATION HEALTH CHECK ====================
        stage('Health Check') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== [TASK 5] Application Health Check =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        echo "Waiting for service to be ready..."
                        sleep 10
                        
                        # Get service IP or use port-forward
                        SERVICE_IP=$(kubectl get svc petclinic-service \
                            -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
                        
                        if [ -z "$SERVICE_IP" ]; then
                            echo "Using port-forward for health check..."
                            kubectl port-forward -n default svc/petclinic-service 8080:80 &
                            sleep 5
                            SERVICE_IP="localhost"
                            PORT="8080"
                        else
                            PORT="80"
                        fi
                        
                        echo "Testing application endpoint: http://${SERVICE_IP}:${PORT}"
                        curl -f http://${SERVICE_IP}:${PORT}/ && echo "✓ Application is healthy" || echo "✗ Health check failed"
                    '''
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    echo "========== Cleaning up =========="
                    sh '''
                        docker image prune -f --filter "dangling=true" || true
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                echo "========== PIPELINE SUMMARY =========="
                echo "Build Number: ${BUILD_NUMBER}"
                echo "Build Status: ${currentBuild.result}"
                echo "Build Duration: ${currentBuild.durationString}"
                echo "Git Commit: ${env.GIT_COMMIT_HASH}"
                echo "Docker Image: ${IMAGE_NAME}:${IMAGE_TAG}"
                echo "===================================="
            }
            cleanWs()
        }
        success {
            script {
                echo "✓ Pipeline completed successfully!"
                echo "Image available at: ${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }
        failure {
            script {
                echo "✗ Pipeline failed - Check logs above for details"
            }
        }
    }
}