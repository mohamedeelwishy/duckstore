# syntax=docker/dockerfile:1
FROM node:22-alpine

RUN apk add --no-cache tini

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY server.js schema.sql ./

RUN mkdir -p /data && chown -R node:node /data /app
USER node

ENV NODE_ENV=production \
    PORT=3000 \
    DB_PATH=/data/duckstore.db

EXPOSE 3000
VOLUME ["/data"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
