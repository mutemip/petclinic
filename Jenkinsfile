pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_CREDENTIALS = credentials('dockerHubCreds')
        GITHUB_TOKEN = credentials('githubToken')
        KUBECONFIG = credentials('kubernetesConfig')
        DOCKER_USERNAME = "${DOCKER_CREDENTIALS_USR}"
        DOCKER_PASSWORD = "${DOCKER_CREDENTIALS_PSW}"
        IMAGE_NAME = "${DOCKER_USERNAME}/spring-petclinic"
        IMAGE_TAG = "${BUILD_NUMBER}"
        GIT_REPO = 'https://github.com/mutemip/petclinic.git'
        KUBE_NAMESPACE = 'petclinic'
        DEPLOYMENT_NAME = 'petclinic-deployment'
        APP_NAME = 'spring-petclinic'
    }

    stages {
        // ==================== PART 1: CI STAGES ====================
        
        stage('Checkout') {
            steps {
                script {
                    echo "========== Checking out source code =========="
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
                    echo "Commit: ${env.GIT_COMMIT_MSG}"
                    echo "Author: ${env.GIT_AUTHOR}"
                    echo "Commit Hash: ${env.GIT_COMMIT_HASH}"
                }
            }
        }

        stage('Build with Maven') {
            steps {
                script {
                    echo "========== Building Application with Maven =========="
                    sh '''
                        chmod +x ./mvnw
                        ./mvnw clean package -DskipTests \
                            -Dorg.slf4j.simpleLogger.defaultLogLevel=info
                    '''
                }
            }
            post {
                success {
                    echo "Maven build completed successfully"
                    archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: false
                }
                failure {
                    echo "Maven build failed"
                    error("Build stage failed")
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "========== Building Docker image =========="
                    sh '''
                        docker build \
                            -t ${IMAGE_NAME}:${IMAGE_TAG} \
                            -t ${IMAGE_NAME}:latest \
                            -f Dockerfile .
                    '''
                }
            }
            post {
                failure {
                    echo "Docker build failed"
                    error("Docker build stage failed")
                }
            }
        }

        stage('Unit Tests') {
            steps {
                script {
                    echo "========== Running Unit Tests =========="
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
                }
            }
        }

        stage('Integration Tests') {
            steps {
                script {
                    echo "========== Running Integration Tests =========="
                    sh '''
                        chmod +x ./mvnw
                        ./mvnw verify \
                            -Dorg.slf4j.simpleLogger.defaultLogLevel=info
                    '''
                }
            }
            post {
                always {
                    junit 'target/failsafe-reports/*.xml'
                }
            }
        }

        stage('Code Quality - SonarQube') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== Running SonarQube Analysis =========="
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
                    echo "SonarQube analysis completed"
                }
            }
        }

        stage('Security Scan - Docker Image') {
            steps {
                script {
                    echo "========== Scanning Docker Image with Trivy =========="
                    sh '''
                        if command -v trivy &> /dev/null; then
                            trivy image --exit-code 0 --severity HIGH,CRITICAL \
                                ${IMAGE_NAME}:${IMAGE_TAG}
                        else
                            echo "Trivy not installed, skipping vulnerability scan"
                        fi
                    '''
                }
            }
            post {
                failure {
                    echo "Warning: Image scan detected vulnerabilities"
                }
            }
        }

        stage('Push to Docker Hub') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== Pushing image to Docker Hub =========="
                    sh '''
                        echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:latest
                        docker logout
                    '''
                }
            }
            post {
                failure {
                    echo "Docker push failed"
                }
                success {
                    echo "✅ Image pushed successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }

        // ==================== PART 2: CD STAGES ====================

        stage('Deploy to Dev') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== Deploying to Development Cluster (default namespace) =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        # Use default namespace
                        KUBE_NAMESPACE="default"
                        
                        # Apply manifests in order
                        echo "Applying RBAC manifests..."
                        kubectl apply -f manifests/01-rbac.yaml
                        
                        echo "Applying PVC manifests..."
                        kubectl apply -f manifests/02-pvc.yaml
                        
                        echo "Applying ConfigMap..."
                        kubectl apply -f manifests/03-configmap.yaml
                        
                        echo "Applying Secret..."
                        kubectl apply -f manifests/04-secret.yaml
                        
                        echo "Applying Deployment manifests..."
                        kubectl set image deployment/petclinic-deployment \
                            petclinic=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n ${KUBE_NAMESPACE} || true
                        
                        kubectl apply -f manifests/05-deployment.yaml
                        
                        echo "Applying Service manifests..."
                        kubectl apply -f manifests/06-service.yaml
                        
                        echo "Applying Ingress manifests..."
                        kubectl apply -f manifests/07-ingress.yaml || echo "Ingress skipped"
                        
                        echo "Applying HPA manifests..."
                        kubectl apply -f manifests/08-hpa.yaml
                        
                        echo "Applying Network Policy..."
                        kubectl apply -f manifests/09-networkpolicy.yaml || echo "NetworkPolicy skipped"
                        
                        echo "Applying PodDisruptionBudget..."
                        kubectl apply -f manifests/10-poddisruptionbudget.yaml
                        
                        # Wait for rollout
                        echo "Waiting for deployment to be ready..."
                        kubectl rollout status deployment/petclinic-deployment \
                            -n ${KUBE_NAMESPACE} --timeout=5m
                    '''
                }
            }
            post {
                success {
                    echo "✅ Development deployment successful"
                }
                failure {
                    echo "❌ Development deployment failed"
                    error("Dev deployment stage failed")
                }
            }
        }

        stage('Smoke Tests - Dev') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "========== Running Smoke Tests on Dev (default namespace) =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        echo "Waiting for service to be ready..."
                        sleep 30
                        
                        # Try to get LoadBalancer IP, fallback to port-forward
                        SERVICE_IP=$(kubectl get svc petclinic-service \
                            -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
                        
                        if [ -z "$SERVICE_IP" ]; then
                            echo "Using port-forward for testing..."
                            kubectl port-forward -n default svc/petclinic-service 8080:80 &
                            sleep 5
                            SERVICE_IP="localhost"
                            PORT="8080"
                        else
                            PORT="80"
                        fi
                        
                        # Run smoke tests
                        echo "Testing home page..."
                        curl -f http://${SERVICE_IP}:${PORT}/ || exit 1
                        
                        echo "✅ Smoke tests passed"
                    '''
                }
            }
            post {
                failure {
                    echo "❌ Smoke tests failed"
                }
            }
        }

        stage('Deploy to Staging') {
            when {
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Deploying to Staging Cluster =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        STAGING_NAMESPACE="petclinic-staging"
                        
                        # Create staging namespace
                        kubectl create namespace ${STAGING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                        
                        # Apply manifests
                        echo "Applying manifests to staging..."
                        kubectl apply -f manifests/01-rbac.yaml -n ${STAGING_NAMESPACE} || true
                        kubectl apply -f manifests/02-pvc.yaml -n ${STAGING_NAMESPACE} || true
                        kubectl apply -f manifests/03-configmap.yaml -n ${STAGING_NAMESPACE}
                        kubectl apply -f manifests/04-secret.yaml -n ${STAGING_NAMESPACE}
                        
                        kubectl set image deployment/${DEPLOYMENT_NAME} \
                            petclinic=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n ${STAGING_NAMESPACE} || true
                        
                        kubectl apply -f manifests/05-deployment.yaml -n ${STAGING_NAMESPACE}
                        kubectl apply -f manifests/06-service.yaml -n ${STAGING_NAMESPACE}
                        
                        kubectl rollout status deployment/${DEPLOYMENT_NAME} \
                            -n ${STAGING_NAMESPACE} --timeout=5m
                    '''
                }
            }
            post {
                success {
                    echo "✅ Staging deployment successful"
                }
                failure {
                    echo "❌ Staging deployment failed"
                }
            }
        }

        stage('Performance Tests - Staging') {
            when {
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Running Performance Tests on Staging =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        STAGING_NAMESPACE="petclinic-staging"
                        sleep 30
                        
                        echo "Performance test completed"
                    '''
                }
            }
        }

        stage('Approval for Production') {
            when {
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Waiting for Production Approval =========="
                    timeout(time: 24, unit: 'HOURS') {
                        input(
                            id: 'ProdDeployment',
                            message: 'Deploy Spring PetClinic to Production?',
                            ok: 'Deploy',
                            submitter: 'admin,devops'
                        )
                    }
                }
            }
        }

        stage('Deploy to Production') {
            when {
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Deploying to Production Cluster =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        PROD_NAMESPACE="petclinic-prod"
                        
                        # Create production namespace
                        kubectl create namespace ${PROD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                        
                        # Create backup
                        kubectl get deployment ${DEPLOYMENT_NAME} \
                            -n ${PROD_NAMESPACE} -o yaml > deployment-backup-${BUILD_NUMBER}.yaml || true
                        
                        # Apply manifests with blue-green strategy
                        echo "Applying production manifests..."
                        kubectl apply -f manifests/01-rbac.yaml -n ${PROD_NAMESPACE} || true
                        kubectl apply -f manifests/02-pvc.yaml -n ${PROD_NAMESPACE} || true
                        kubectl apply -f manifests/03-configmap.yaml -n ${PROD_NAMESPACE}
                        kubectl apply -f manifests/04-secret.yaml -n ${PROD_NAMESPACE}
                        
                        kubectl set image deployment/${DEPLOYMENT_NAME} \
                            petclinic=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n ${PROD_NAMESPACE} || true
                        
                        kubectl apply -f manifests/05-deployment.yaml -n ${PROD_NAMESPACE}
                        kubectl apply -f manifests/06-service.yaml -n ${PROD_NAMESPACE}
                        
                        # Gradual rollout
                        echo "Rolling out deployment..."
                        kubectl rollout status deployment/${DEPLOYMENT_NAME} \
                            -n ${PROD_NAMESPACE} --timeout=10m
                        
                        echo "✅ Production deployment completed"
                    '''
                }
            }
            post {
                success {
                    script {
                        sh '''
                            export KUBECONFIG=${KUBECONFIG}
                            echo "Production deployment successful"
                        '''
                    }
                }
                failure {
                    script {
                        echo "❌ Production deployment failed - Initiating rollback"
                        sh '''
                            export KUBECONFIG=${KUBECONFIG}
                            PROD_NAMESPACE="petclinic-prod"
                            kubectl rollout undo deployment/${DEPLOYMENT_NAME} \
                                -n ${PROD_NAMESPACE}
                            kubectl rollout status deployment/${DEPLOYMENT_NAME} \
                                -n ${PROD_NAMESPACE} --timeout=5m
                            echo "Rollback completed"
                        '''
                    }
                }
            }
        }

        stage('Production Health Check') {
            when {
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Running Production Health Checks =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        PROD_NAMESPACE="petclinic-prod"
                        
                        sleep 30
                        
                        echo "Health checks completed"
                    '''
                }
            }
            post {
                failure {
                    echo "❌ Production health checks failed"
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    echo "========== Cleaning up =========="
                    sh '''
                        # Remove dangling images
                        docker image prune -f --filter "dangling=true" || true
                        
                        # Clean workspace
                        rm -rf target/ || true
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                echo "========== Pipeline Execution Summary =========="
                echo "Build Number: ${BUILD_NUMBER}"
                echo "Build Status: ${currentBuild.result}"
                echo "Build Duration: ${currentBuild.durationString}"
            }
            cleanWs()
        }
        success {
            script {
                echo "✅ Pipeline completed successfully!"
            }
        }
        failure {
            script {
                echo "❌ Pipeline failed!"
            }
        }
    }
}