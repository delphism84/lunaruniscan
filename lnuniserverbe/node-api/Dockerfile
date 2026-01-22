FROM node:20-alpine

ENV NODE_ENV=production
ENV PORT=45444

WORKDIR /usr/src/app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./server.js

# ensure files folder exists
RUN mkdir -p /usr/src/app/files

EXPOSE 45444

CMD ["npm", "start"]


