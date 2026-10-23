FROM node:24-alpine AS build

WORKDIR /app
COPY .code-interpreter/packages/code/package.json .code-interpreter/packages/code/package-lock.json .code-interpreter/packages/code/tsconfig.json ./
RUN npm ci
COPY .code-interpreter/packages/code/src ./src
RUN npm run build

FROM node:24-alpine

RUN apk add --no-cache docker-cli
WORKDIR /app
COPY --from=build /app/package.json /app/package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
ENTRYPOINT ["node", "dist/cli.js"]
