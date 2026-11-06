FROM node:22-slim AS build
WORKDIR /code
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-slim
WORKDIR /code
ENV NODE_ENV=production
COPY package*.json ./
RUN npm install --omit=dev
COPY --from=build /code/dist ./dist
CMD ["node", "dist/server.js"]
