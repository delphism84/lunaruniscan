## ?댁쁺 怨꾪쉷

- 蹂꾨룄??Nginx濡?WSS(SSL) ?ы듃瑜??댁쁺?쒕떎.
- ?몃?: `server.lunarsystem.co.kr:44444` ?먯꽌 WSS ?섏떊 ???대?: `127.0.0.1:45444` 濡??꾨줉???낃렇?덉씠???ㅻ뜑 ?ы븿)
  - 二쇱쓽: 諛깆뿏??WSS ?쒕퉬?ㅻ뒗 `127.0.0.1:45444` 濡?由ъ뒯?섎룄濡?留욎텣?? Nginx媛 44444瑜??먯쑀?섎?濡?異⑸룎 諛⑹?.
- ?몄쬆?? `server.lunarsystem.co.kr` ?꾨찓?몄뿉 ???Let's Encrypt 諛쒓툒/?먮룞 媛깆떊
- ?곗씠?곕쿋?댁뒪: MongoDB LTS, ?몃? ?묒냽 ?덉슜 ?ы듃 47017, 湲곕낯 DB `lunarUniScan`

?ъ쟾 以鍮?
- DNS: `server.lunarsystem.co.kr` ???꾩옱 ?쒕쾭 怨듭씤 IP濡?A?덉퐫???ㅼ젙
- 蹂댁븞洹몃９/諛⑺솕踰? 80, 443, 44444, 47017 TCP ?닿린 (?꾨옒 泥댄겕由ъ뒪??李멸퀬)

## ?붾젆?곕━ 援ъ“ (Bind Mount)

- 猷⑦듃: `/var/UniScan/docker`
- ?곗씠?? `/var/UniScan/docker/data/mongo`
- 珥덇린???ㅽ겕由쏀듃: `/var/UniScan/docker/mongo-init/init.js`
- 濡쒓렇/湲고?: `/var/UniScan/docker/logs`, `/var/UniScan/docker/config`

## Docker ?ㅼ튂 (Ubuntu/Debian 怨꾩뿴)

```bash
sudo apt-get update -y && sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
# ?꾩옱 ?몄뀡??利됱떆 諛섏쁺?섏? ?딆?留?異뷀썑瑜??꾪빐 ?ъ슜???꾩빱 洹몃９ 異붽?
sudo usermod -aG docker "$USER"
```

?뺤씤
```bash
docker --version
docker compose version
```

## Docker Compose ?뚯씪 ?묒꽦

寃쎈줈: `/var/UniScan/docker/docker-compose.yml`

```yaml
version: "3.8"

services:
  mongo:
    image: mongo:6.0
    container_name: lunar-mongo
    restart: always
    ports:
      - "47017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: ladmin
      MONGO_INITDB_ROOT_PASSWORD: "Eldpdj!@34"
    command: ["mongod", "--port", "27017", "--bind_ip", "0.0.0.0"]
    volumes:
      - /var/UniScan/docker/data/mongo:/data/db
      - /var/UniScan/docker/mongo-init:/docker-entrypoint-initdb.d:ro
```

珥덇린???ㅽ겕由쏀듃 ?묒꽦
- 寃쎈줈: `/var/UniScan/docker/mongo-init/init.js`
```javascript
// create initial db
var dbName = 'lunarUniScan';
var dbRef = db.getSiblingDB(dbName);
// touch a collection to ensure creation
if (!dbRef.getCollectionNames().includes('init')) {
  dbRef.createCollection('init');
}
```

湲곕룞
```bash
sudo mkdir -p /var/UniScan/docker/{data/mongo,logs,config} /var/UniScan/docker/mongo-init
# ??寃쎈줈??docker-compose.yml, init.js 諛곗튂 ??
sudo docker compose -f /var/UniScan/docker/docker-compose.yml up -d
sudo docker ps | cat
```

?몃? ?묒냽 ?뺤씤 (?꾩떆)
```bash
# ?숈씪 ?쒕쾭?먯꽌 ?ы듃 ?ㅽ뵂 ?щ? ?먭?
nc -zv 127.0.0.1 47017 || true
```

?먭꺽 ?묒냽 媛?대뱶
- ?묒냽 URI: `mongodb://ladmin:YOUR_PASSWORD@SERVER_IP:47017/admin`
- 珥덇린 鍮꾨?踰덊샇: `Eldpdj!@34` (?꾩닔 蹂寃?沅뚯옣)

## Nginx 諛?Certbot ?ㅼ튂

```bash
sudo apt-get update -y && sudo apt-get install -y nginx certbot python3-certbot-nginx
sudo systemctl enable --now nginx
```

?몄쬆??諛쒓툒 (臾댁씤)
```bash
# DNS媛 ?쒕쾭濡??щ컮瑜닿쾶 ?ν븷 ???ㅽ뻾
sudo certbot certonly --nginx -d server.lunarsystem.co.kr --agree-tos -n --register-unsafely-without-email
# ?깃났 ???몄쬆??寃쎈줈:
# /etc/letsencrypt/live/server.lunarsystem.co.kr/fullchain.pem
# /etc/letsencrypt/live/server.lunarsystem.co.kr/privkey.pem
```

## Nginx WSS 由щ쾭???꾨줉??44444)

寃쎈줈: `/etc/nginx/sites-available/UniScan-wss-44444`

```nginx
server {
    listen 44444 ssl;
    server_name server.lunarsystem.co.kr;

    ssl_certificate     /etc/letsencrypt/live/server.lunarsystem.co.kr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/server.lunarsystem.co.kr/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # ?뱀냼耳??낃렇?덉씠??
    location / {
        proxy_pass http://127.0.0.1:45444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 600s;
    }
}
```

?곸슜
```bash
# ?ъ씠???쒖꽦??
sudo ln -sf /etc/nginx/sites-available/UniScan-wss-44444 /etc/nginx/sites-enabled/UniScan-wss-44444
# 臾몃쾿 寃??諛??ъ떆??
sudo nginx -t && sudo systemctl reload nginx
```

諛깆뿏??WSS ?쒕퉬???덉떆
- ?쒕퉬?ㅻ뒗 `127.0.0.1:45444` ?먯꽌 WS濡?由ъ뒯
- ?대씪?댁뼵?몃뒗 `wss://server.lunarsystem.co.kr:44444` 濡??묒냽

## 諛⑺솕踰?蹂댁븞洹몃９ 泥댄겕由ъ뒪??

- AWS 蹂댁븞洹몃９ ?몃컮?대뱶 ?덉슜: TCP 80, 443, 44444, 47017
- OS 諛⑺솕踰?UFW ?? ?ъ슜 ??
```bash
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true
sudo ufw allow 44444/tcp || true
sudo ufw allow 47017/tcp || true
```

## 湲곕낯 ?먭?

- MongoDB
  - ?쒕쾭 ?대?: `nc -zv 127.0.0.1 47017`
  - ?먭꺽: `mongo --host server.lunarsystem.co.kr --port 47017 -u ladmin -p` (?대씪?댁뼵???ㅼ튂 ?꾩슂)
- WSS
  - ?쒕쾭 ?몃?: `wscat -c wss://server.lunarsystem.co.kr:44444` (wscat ?꾩슂)

## 李멸퀬/硫붾え
- 44444 ?ы듃???몃? WSS?⑹쑝濡??덉빟?? ?대? 諛깆뿏?쒕뒗 45444 ??蹂꾨룄 ?ы듃瑜??ъ슜.
- 珥덇린 鍮꾨?踰덊샇 諛??ы듃???댁쁺 ?ъ엯 ??蹂寃?寃??沅뚯옣.

