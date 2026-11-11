# Executor do CQ09 dentro da Azure (mesma regiao da homologacao), chamando a borda publica
# HTTPS do API Management. Remove do resultado a variacao da rede domestica do operador.
FROM node:24-bookworm-slim
WORKDIR /cq09
# Contexto de build: quality/load (o .dockerignore da raiz exclui quality/).
COPY cq09.mjs ./cq09.mjs
USER node
ENTRYPOINT ["node", "/cq09/cq09.mjs"]
