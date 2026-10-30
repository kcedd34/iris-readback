# The interface and its reverse proxy. Stage 1 builds the frontend (the build output is never committed);
# stage 2 serves it with nginx and forwards only the Readback paths to the platform (contracts/proxy-paths.md).
FROM node:24.22.2-alpine AS build
WORKDIR /app
COPY frontend/package.json frontend/package-lock.json frontend/.npmrc ./
RUN npm ci --ignore-scripts
COPY frontend/ ./
RUN npm run build && npm run check-budget && npm run check-contrast && npm run check-external

FROM nginx:1.30.6-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY src/ops/proxy/nginx.conf.template /etc/nginx/readback.conf.template
COPY src/ops/proxy/readback-proxy.inc /etc/nginx/readback-proxy.inc
COPY src/ops/proxy/entrypoint.sh /readback-entrypoint.sh
RUN chmod 0755 /readback-entrypoint.sh
ENTRYPOINT ["/readback-entrypoint.sh"]
