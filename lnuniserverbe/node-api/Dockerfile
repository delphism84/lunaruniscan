FROM node:20-alpine

ENV NODE_ENV=production
ENV PORT=50100

WORKDIR /usr/src/app

COPY package.json ./
RUN npm install --only=production

COPY server.js ./server.js

# ensure files folder exists
RUN mkdir -p /usr/src/app/files

EXPOSE 50100

CMD ["npm", "start"]


