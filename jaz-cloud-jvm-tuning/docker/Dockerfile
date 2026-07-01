# syntax=docker/dockerfile:1

# ---- Build stage: compile the Spring Boot jar with Maven on JDK 21 ----
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY app/pom.xml .
# Warm the dependency cache first so source-only changes rebuild fast.
RUN mvn -q -B dependency:go-offline
COPY app/src ./src
RUN mvn -q -B clean package -DskipTests

# ---- Runtime stage: Microsoft Build of OpenJDK 21, which ships with jaz preinstalled ----
FROM mcr.microsoft.com/openjdk/jdk:21-ubuntu
WORKDIR /app
COPY --from=build /src/target/digital-bank.jar /app/app.jar

# The run matrix selects the launcher (java vs jaz) and any measurement-only flags (e.g. -Xlog:gc*,
# which jaz does NOT treat as a tuning flag, so jaz still applies its own tuning).
ENV LAUNCHER=java
ENV JAVA_ARGS=""
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "exec ${LAUNCHER} ${JAVA_ARGS} -jar /app/app.jar"]
