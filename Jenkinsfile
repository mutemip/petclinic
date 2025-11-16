pipeline {
    agent {
        label 'linux-agent'  // Use a labeled agent with pre-installed tools
    }

    environment {
        DOCKERHUB_USERNAME = "mutemip"
        APP_NAME = "spring-petclinic"
        IMAGE_NAME = "${DOCKERHUB_USERNAME}" + "/" + "${APP_NAME}"
        IMAGE_TAG = "${BUILD_NUMBER}"
        SONAR_HOME = "/opt/sonar-scanner"
        DOCKER_CONFIG = "${HOME}/.docker"
    }

    stages {
        stage('Clone the Codebase') {
            steps {
                withCredentials([string(credentialsId: 'githubToken', variable: 'GITHUB_TOKEN')]) {
                    sh '''
                        rm -rf .git
                        git clone https://${GITHUB_TOKEN}@github.com/mutemip/petclinic.git .
                        git checkout main
                    '''
                }
            }
        }

        stage('Run Tests') {
            steps {
                sh 'mvn test'
            }
            post {
                success {
                    junit '**/target/surefire-reports/*.xml'
                }
            }
        }

        stage('Build Application') {
            steps {
                sh 'mvn package -DskipTests'
            }
        }

        stage('Sonar Scan') {
            steps {
                withSonarQubeEnv(credentialsId: 'sonar', installationName: 'sonarserver') {
                    sh '''
                        ${SONAR_HOME}/bin/sonar-scanner \
                            -Dsonar.projectKey=petclinic \
                            -Dsonar.projectName=petclinic \
                            -Dsonar.projectVersion=1.0 \
                            -Dsonar.sources=src/main \
                            -Dsonar.tests=src/test \
                            -Dsonar.java.binaries=target/classes \
                            -Dsonar.language=java \
                            -Dsonar.sourceEncoding=UTF-8 \
                            -Dsonar.java.libraries=target/classes
                    '''
                }
            }
        }

        stage('Wait for Quality Gate') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Docker Image and Push to Docker Hub') {
            steps {
                withCredentials([file(credentialsId: 'dockerCreds', variable: 'DOCKER_CONFIG_FILE')]) {
                    sh '''
                        mkdir -p ${DOCKER_CONFIG}
                        cp ${DOCKER_CONFIG_FILE} ${DOCKER_CONFIG}/config.json
                        chmod 600 ${DOCKER_CONFIG}/config.json
                        
                        docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                        
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:latest
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes via manifests') {
            steps {
                withKubeConfig(credentialsId: 'kubernetes') {
                    sh '''
                        kubectl apply -f k8-deployment.yaml
                        kubectl rollout status deployment/petclinic -n default --timeout=5m
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        failure {
            echo 'Pipeline failed!'
        }
        success {
            echo 'Pipeline completed successfully!'
        }
    }
}