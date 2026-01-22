FROM node:20-alpine

ENV NODE_ENV=production
ENV PORT=50210

WORKDIR /usr/src/app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./server.js

EXPOSE 50210

CMD ["npm", "start"]

