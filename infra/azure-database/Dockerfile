# syntax=docker/dockerfile:1
FROM flyway/flyway:13.12.0-alpine

RUN apk add --no-cache postgresql-client

WORKDIR /nexfleet
COPY infra/azure/sql/bootstrap-service-roles.sql ./bootstrap-service-roles.sql
COPY services/identidade/src/main/resources/db/migration ./migrations/identidade
COPY services/frota/src/main/resources/db/migration ./migrations/frota
COPY services/operacoes/src/main/resources/db/migration ./migrations/operacoes
COPY services/indicadores/src/main/resources/db/migration ./migrations/indicadores
COPY functions/notificar-abastecimento/src/main/resources/db/migration ./migrations/notificacoes
COPY infra/azure-database/migrate.sh ./migrate.sh
COPY infra/azure-database/verify.sh ./verify.sh
COPY infra/azure-database/bootstrap-admin.sh ./bootstrap-admin.sh

RUN sed -i 's/\r$//' ./migrate.sh ./verify.sh ./bootstrap-admin.sh \
    && chmod 0555 ./migrate.sh ./verify.sh ./bootstrap-admin.sh \
    && find ./migrations -type f -name '*.sql' -exec chmod 0444 {} \; \
    && addgroup -S -g 10001 nexfleet \
    && adduser -S -D -H -u 10001 -G nexfleet nexfleet

ENV HOME=/tmp
USER 10001:10001
ENTRYPOINT ["/nexfleet/migrate.sh"]
