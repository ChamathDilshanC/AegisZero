# syntax=docker/dockerfile:1
#
# Shared build for every Spring Boot service in the reactor. Build with:
#   docker build --build-arg SERVICE_NAME=auth-service -t aegiszero/auth-service .
# Docker's layer cache means the (slow) `mvn package` step only re-runs once
# per source change, not once per service image.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

COPY pom.xml .
COPY shared shared
COPY services services

RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre-alpine AS runtime
ARG SERVICE_NAME
ENV SERVICE_JAR=${SERVICE_NAME}.jar
WORKDIR /app

RUN addgroup -S aegiszero && adduser -S aegiszero -G aegiszero
COPY --from=build /workspace/services/${SERVICE_NAME}/target/${SERVICE_NAME}.jar /app/app.jar
USER aegiszero

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
