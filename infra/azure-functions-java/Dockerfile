# syntax=docker/dockerfile:1
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY functions/notificar-abastecimento/pom.xml ./pom.xml
COPY functions/notificar-abastecimento/host.json ./host.json
COPY functions/notificar-abastecimento/src ./src
RUN --mount=type=cache,target=/root/.m2 mvn --batch-mode --no-transfer-progress verify

FROM mcr.microsoft.com/azure-functions/java:4-java21
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true
COPY --from=build /workspace/target/azure-functions/nexfleet-notificacoes /home/site/wwwroot
