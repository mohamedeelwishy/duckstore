# syntax=docker/dockerfile:1
FROM node:22-alpine

RUN apk add --no-cache tini

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY server.js ./

RUN chown -R node:node /app
USER node

ENV NODE_ENV=production \
    PORT=3000 \
    BACKEND_URL=http://duck-api.backend.svc.cluster.local:3000

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
