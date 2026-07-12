ARG pathPrefix="/"

FROM node:lts-alpine AS build-step
ARG DYNAMIC_CONFIG=true
ARG historyMode="history"
ARG SB_CONFIG=""
ENV SB_historyMode="${historyMode}"
ENV SB_pathPrefix="/__SB_PATH_PREFIX__/"
ENV SB_CONFIG="${SB_CONFIG}"

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN \[ "${DYNAMIC_CONFIG}" == "true" \] && sed -i 's/<!--RC//;s/RC-->//' index.html
RUN npm run build


FROM nginxinc/nginx-unprivileged:1-alpine
ARG pathPrefix

USER root
RUN apk add --no-cache jq pcre-tools

COPY ./config.schema.json /etc/nginx/conf.d/config.schema.json
COPY --from=build-step /app/dist /usr/share/nginx/html
COPY --from=build-step /app/docker/default.conf /etc/nginx/templates/default.conf
ADD docker/docker-entrypoint.sh /docker-entrypoint.d/40-stac-browser-entrypoint.sh

ENV SB_pathPrefix="${pathPrefix}"

RUN chown -R nginx:nginx /usr/share/nginx/html /etc/nginx/conf.d && \
    chmod +x /docker-entrypoint.d/40-stac-browser-entrypoint.sh

EXPOSE 8080

STOPSIGNAL SIGTERM

USER nginx
