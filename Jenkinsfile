pipeline {
    agent {
        kubernetes {
            namespace 'default'
            yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
spec:
  serviceAccountName: jenkins
  containers:
  - name: maven
    image: maven:3.9-eclipse-temurin-17
    command:
    - sleep
    args:
    - 99d
    volumeMounts:
    - name: maven-cache
      mountPath: /root/.m2
  - name: docker
    image: docker:24-dind
    securityContext:
      privileged: true
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run
  - name: kubectl
    image: bitnami/kubectl:latest
    command:
    - sleep
    args:
    - 99d
  volumes:
  - name: maven-cache
    emptyDir: {}
  - name: docker-sock
    emptyDir: {}
'''
        }
    }
    
    environment {
        DOCKER_HUB_REPO = 'mutemip/springpetclinic'
        DOCKER_CREDENTIALS_ID = 'dockerhub-credentials'
        GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
        IMAGE_TAG = "latest"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    echo "Building commit: ${GIT_COMMIT_SHORT}"
                    echo "Image tag: ${IMAGE_TAG}"
                }
            }
        }
        
        stage('Build') {
            steps {
                container('maven') {
                    sh '''
                        echo "Building Spring Boot application..."
                        mvn clean package -DskipTests
                    '''
                }
            }
        }
        
        stage('Test') {
            steps {
                container('maven') {
                    sh '''
                        echo "Running tests..."
                        mvn test
                    '''
                }
            }
            post {
                always {
                    junit '**/target/surefire-reports/*.xml'
                }
            }
        }
        
        stage('Static Analysis - SonarQube') {
            steps {
                container('maven') {
                    script {
                        echo "SonarQube analysis would run here"
                        // Uncomment when SonarQube is configured:
                        // withSonarQubeEnv('SonarQube') {
                        //     sh 'mvn sonar:sonar'
                        // }
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                container('docker') {
                    sh '''
                        dockerd &
                        sleep 10
                        docker build -t ${DOCKER_HUB_REPO}:${IMAGE_TAG} .
                        docker tag ${DOCKER_HUB_REPO}:${IMAGE_TAG} ${DOCKER_HUB_REPO}:latest
                    '''
                }
            }
        }
        
        stage('Push to Docker Hub') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh '''
                            echo "Logging in to Docker Hub..."
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            
                            echo "Pushing image: ${DOCKER_HUB_REPO}:${IMAGE_TAG}"
                            docker push ${DOCKER_HUB_REPO}:${IMAGE_TAG}
                            
                            echo "Pushing image: ${DOCKER_HUB_REPO}:latest"
                            docker push ${DOCKER_HUB_REPO}:latest
                            
                            docker logout
                            echo "Push completed successfully!"
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    sh '''
                        # Update deployment with new image
                        sed -i "s|image:.*|image: ${DOCKER_HUB_REPO}:${IMAGE_TAG}|g" k8s/deployment.yaml
                        
                        # Apply configurations
                        kubectl apply -f k8s/deployment.yaml
                        kubectl apply -f k8s/service.yaml
                        
                        # Wait for rollout
                        kubectl rollout status deployment/petclinic -n default --timeout=5m
                        
                        # Verify deployment
                        kubectl get pods -n default -l app=petclinic
                        kubectl get svc -n default petclinic-service
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo "Pipeline completed successfully! 🎉"
            echo "Application deployed with image: ${DOCKER_HUB_REPO}:${IMAGE_TAG}"
        }
        failure {
            echo "Pipeline failed! 😞"
        }
        always {
            echo "Cleaning up workspace..."
            // cleanWs() requires Workspace Cleanup plugin
            // Alternatively, just let Kubernetes handle cleanup
        }
    }
}