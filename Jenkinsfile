pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
        timestamps()
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
    }

    stages {
        // ============ CI STAGES (Part 1) ============
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
                }
            }
        }

        stage('Build') {
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
                    archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: false
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
        }

        stage('Unit Tests') {
            steps {
                script {
                    echo "========== Running Unit Tests =========="
                    sh '''
                        chmod +x ./mvnw
                        ./mvnw test
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
                        ./mvnw verify
                    '''
                }
            }
            post {
                always {
                    junit 'target/failsafe-reports/*.xml'
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
        }

        // ============ CD STAGES (Part 2) ============
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
                branch 'main'
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Deploying to Staging Cluster =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        # Create staging namespace
                        kubectl create namespace petclinic-staging --dry-run=client -o yaml | kubectl apply -f -
                        
                        # Apply ConfigMap for staging
                        kubectl apply -f manifests/petclinic-configmap.yaml -n petclinic-staging
                        
                        # Update image and apply manifests
                        kubectl set image deployment/${DEPLOYMENT_NAME} \
                            petclinic=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n petclinic-staging || true
                        
                        kubectl apply -f manifests/ -n petclinic-staging
                        kubectl rollout status deployment/${DEPLOYMENT_NAME} \
                            -n petclinic-staging --timeout=5m
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
                branch 'main'
                tag 'v*'
            }
            steps {
                script {
                    echo "========== Running Performance Tests on Staging =========="
                    sh '''
                        export KUBECONFIG=${KUBECONFIG}
                        
                        SERVICE_IP=$(kubectl get svc petclinic-service \
                            -n petclinic-staging -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                        
                        sleep 30
                        
                        # Simple load test (can be replaced with JMeter/Gatling)
                        for i in {1..100}; do
                            curl -s http://${SERVICE_IP}:8080/vets.html > /dev/null &
                        done
                        wait
                        
                        echo "✅ Performance tests completed"
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
                            message: 'Deploy to Production?',
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
                        
                        # Create production namespace
                        kubectl create namespace petclinic-prod --dry-run=client -o yaml | kubectl apply -f -
                        
                        # Create backup of current deployment
                        kubectl get deployment ${DEPLOYMENT_NAME} \
                            -n petclinic-prod -o yaml > deployment-backup-${BUILD_NUMBER}.yaml || true
                        
                        # Apply manifests with blue-green or canary strategy
                        kubectl apply -f manifests/petclinic-configmap.yaml -n petclinic-prod
                        
                        # Update image in production
                        kubectl set image deployment/${DEPLOYMENT_NAME} \
                            petclinic=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n petclinic-prod || true
                        
                        kubectl apply -f manifests/ -n petclinic-prod
                        
                        # Gradual rollout (max surge 1, max unavailable 0)
                        kubectl rollout status deployment/${DEPLOYMENT_NAME} \
                            -n petclinic-prod --timeout=10m
                        
                        echo "✅ Production deployment completed"
                    '''
                }
            }
            post {
                success {
                    script {
                        sh '''
                            export KUBECONFIG=${KUBECONFIG}
                            PROD_IP=$(kubectl get svc petclinic-service \
                                -n petclinic-prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                            echo "Production URL: http://${PROD_IP}:8080"
                        '''
                    }
                }
                failure {
                    script {
                        echo "❌ Production deployment failed - Initiating rollback"
                        sh '''
                            export KUBECONFIG=${KUBECONFIG}
                            kubectl rollout undo deployment/${DEPLOYMENT_NAME} \
                                -n petclinic-prod
                            kubectl rollout status deployment/${DEPLOYMENT_NAME} \
                                -n petclinic-prod --timeout=5m
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
                        
                        PROD_IP=$(kubectl get svc petclinic-service \
                            -n petclinic-prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                        
                        sleep 30
                        
                        # Health checks
                        echo "Testing home page..."
                        curl -f http://${PROD_IP}:8080/ || exit 1
                        
                        echo "Testing owners endpoint..."
                        curl -f http://${PROD_IP}:8080/owners/find || exit 1
                        
                        echo "Testing vets endpoint..."
                        curl -f http://${PROD_IP}:8080/vets.html || exit 1
                        
                        echo "Testing API endpoint..."
                        curl -f http://${PROD_IP}:8080/api/vets || exit 1
                        
                        echo "✅ All health checks passed"
                    '''
                }
            }
            post {
                failure {
                    echo "❌ Production health checks failed"
                    error("Production health check failed")
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    echo "========== Cleaning up =========="
                    sh '''
                        docker image prune -f --filter "dangling=true"
                        rm -rf target/
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
                echo "Commit: ${env.GIT_COMMIT_HASH}"
                echo "Author: ${env.GIT_AUTHOR}"
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