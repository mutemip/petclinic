FROM maven:4.0.0-rc-4-eclipse-temurin-17-noble AS builder
WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests -X

# Stage 2: Create the final image
FROM maven:4.0.0-rc-4-eclipse-temurin-17-noble
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
USER 1000:1000
EXPOSE 8082
ENTRYPOINT ["java","-jar","app.jar"]