pipeline {
    agent {
        kubernetes {
            yaml '''
        apiVersion: v1
        kind: Pod
        metadata:
          labels:
            app: test
        spec:
          containers:
          - name: maven
            image: maven:3.9-eclipse-temurin-25
            command:
            - cat
            tty: true
            volumeMounts:
            - mountPath: "/root/.m2/repository"
              name: cache
          - name: git
            image: bitnami/git:latest
            command:
            - cat
            tty: true
          - name: kaniko
            image: gcr.io/kaniko-project/executor:debug
            command: ["/busybox/cat"]
            tty: true
            volumeMounts:
            - name: docker-config
              mountPath: /kaniko/.docker
          - name: sonarcli
            image: sonarsource/sonar-scanner-cli:latest
            command:
            - cat
            tty: true
          - name: kubectl-helm-cli
            image: kunchalavikram/kubectl_helm_cli:latest
            command:
            - cat
            tty: true
          volumes:
          - name: cache
            persistentVolumeClaim:
              claimName: maven-cache
          - name: docker-config
            secret:
              secretName: docker-credentials
              items:
              - key: .dockerconfigjson
                path: config.json
      '''
        }
    }
    environment {
        DOCKERHUB_USERNAME = "mutemip"
        APP_NAME = "spring-petclinic"
        IMAGE_NAME = "${DOCKERHUB_USERNAME}" + "/" + "${APP_NAME}"
        IMAGE_TAG = "${BUILD_NUMBER}"
    }
    stages {
        stage('Clone the Codebase') {
            when {
                expression {
                    true
                }
            }
            steps {
                container('git') {
                    withCredentials([string(credentialsId: 'githubToken', variable: 'GITHUB_TOKEN')]) {
                        git url: 'https://${GITHUB_TOKEN}@github.com/mutemip/petclinic.git',
                        branch: 'main'
                    }
                }
            }
        }
        stage('Run Tests') {
            when {
                expression {
                    true
                }
            }
            steps {
                container('maven') {
                    sh 'mvn test'
                }
            }
            post {
                success {
                    junit '**/target/surefire-reports/*.xml'
                }
            }
        }
        stage('Build Application') {
            when {
                expression {
                    true
                }
            }
            steps {
                container('maven') {
                    sh 'mvn package -DskipTests'
                }
            }
        }
        stage('Sonar Scan') {
            when {
                expression {
                    true
                }
            }
            steps {
                container('sonarcli') {
                    withSonarQubeEnv(credentialsId: 'sonar', installationName: 'sonarserver') {
                        sh '''/opt/sonar-scanner/bin/sonar-scanner \
              -Dsonar.projectKey=petclinic \
              -Dsonar.projectName=petclinic \
              -Dsonar.projectVersion=1.0 \
              -Dsonar.sources=src/main \
              -Dsonar.tests=src/test \
              -Dsonar.java.binaries=target/classes  \
              -Dsonar.language=java \
              -Dsonar.sourceEncoding=UTF-8 \
              -Dsonar.java.libraries=target/classes
            '''
                    }
                }
            }
        }
        stage('Wait for Quality Gate') {
            when {
                expression {
                    true
                }
            }
            steps {
                container('sonarcli') {
                    timeout(time: 1, unit: 'HOURS') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
        }
        stage('Build Docker Image and Push to Docker Hub') {
            when {
                expression {
                    true
                }
            }
            steps {
                container('kaniko') {
                    withCredentials([file(credentialsId: 'dockerCreds', variable: 'DOCKER_CONFIG_FILE')]) {
                        sh '''
                        mkdir -p /kaniko/.docker
                        cp ${DOCKER_CONFIG_FILE} /kaniko/.docker/config.json
                        /kaniko/executor \
                          --context=${WORKSPACE} \
                          --dockerfile=Dockerfile \
                          --destination=${IMAGE_NAME}:${IMAGE_TAG} \
                          --destination=${IMAGE_NAME}:latest \
                          --cache=true
                        '''
                    }
                }
            }
        }
        stage("Deploy to Kubernetes via manifests") {
            when {
                expression {
                    true
                }
            }
            steps {
                container('kubectl-helm-cli') {
                    withKubeConfig(caCertificate: '', clusterName: '', contextName: '', credentialsId: 'k8s', namespace: '', restrictKubeConfigAccess: false, serverUrl: '') {
                        sh "kubectl apply -f k8-deployment.yaml"
                    }
                }
            }
        }
    }
}