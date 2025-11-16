## 운영 계획

- 별도의 Nginx로 WSS(SSL) 프록시를 운영한다.
- 외부: `server.lunarsystem.co.kr:44444` 에서 WSS 수신 → 내부: `127.0.0.1:45444` 로 프록시 (백엔드 WS는 로컬에서만 리슨)
  - 주의: 백엔드 WSS 리슨을 `127.0.0.1:45444` 로 맞추어 Nginx(44444)와 포트 충돌을 방지한다.
- 인증서: `server.lunarsystem.co.kr` 도메인에 Let's Encrypt 발급/자동 갱신
- 데이터베이스: MongoDB LTS, 호스트 포트 47017, 기본 DB `uniscan`

## 사전 준비
- DNS: `server.lunarsystem.co.kr` A 레코드를 서버 공인 IP로 설정
- 보안그룹/방화벽: TCP 80, 443, 44444, 47017 허용 (아래 체크리스트 참고)

## 디렉터리 구조 (Bind Mount)

- 루트: `/var/UniScan/docker`
- 데이터: `/var/UniScan/docker/data/mongo`
- 초기화 스크립트: `/var/UniScan/docker/mongo-init/init.js`
- 로그/설정: `/var/UniScan/docker/logs`, `/var/UniScan/docker/config`

## Docker 설치 (Ubuntu/Debian 계열)

```bash
sudo apt-get update -y && sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
# 현재 세션에 즉시 반영되지는 않음. 추후 재로그인 또는 도커 그룹 추가 반영 필요
sudo usermod -aG docker "$USER"
```

확인
```bash
docker --version
docker compose version
```

## Docker Compose 파일 작성

경로: `/var/UniScan/docker/docker-compose.yml`

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

초기화 스크립트 작성
- 경로: `/var/UniScan/docker/mongo-init/init.js`
```javascript
// create initial db
var dbName = 'uniscan';
var dbRef = db.getSiblingDB(dbName);
// touch a collection to ensure creation
if (!dbRef.getCollectionNames().includes('init')) {
  dbRef.createCollection('init');
}
```

기동
```bash
sudo mkdir -p /var/UniScan/docker/{data/mongo,logs,config} /var/UniScan/docker/mongo-init
# 위 경로에 docker-compose.yml, init.js 배치 후
sudo docker compose -f /var/UniScan/docker/docker-compose.yml up -d
sudo docker ps | cat
```

포트 오픈 확인 (필요시)
```bash
# 로컬 서버에서 포트 오픈 확인
nc -zv 127.0.0.1 47017 || true
```

원격 접속 가이드
- 접속 URI: `mongodb://ladmin:YOUR_PASSWORD@SERVER_IP:47017/admin`
- 초기 비밀번호: `Eldpdj!@34` (필수 변경 권장)

## Nginx & Certbot 설치

```bash
sudo apt-get update -y && sudo apt-get install -y nginx certbot python3-certbot-nginx
sudo systemctl enable --now nginx
```

인증서 발급 (무인)
```bash
# DNS가 서버에 바르게 향할 것 가정
sudo certbot certonly --nginx -d server.lunarsystem.co.kr --agree-tos -n --register-unsafely-without-email
# 발급 경로:
# /etc/letsencrypt/live/server.lunarsystem.co.kr/fullchain.pem
# /etc/letsencrypt/live/server.lunarsystem.co.kr/privkey.pem
```

## Nginx WSS 리버스 프록시(44444)

경로: `/etc/nginx/sites-available/UniScan-wss-44444`

```nginx
server {
    listen 44444 ssl;
    server_name server.lunarsystem.co.kr;

    ssl_certificate     /etc/letsencrypt/live/server.lunarsystem.co.kr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/server.lunarsystem.co.kr/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # 웹소켓 프록시
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

적용
```bash
# 심볼릭 링크 생성
sudo ln -sf /etc/nginx/sites-available/UniScan-wss-44444 /etc/nginx/sites-enabled/UniScan-wss-44444
# 문법 검사 후 재로드
sudo nginx -t && sudo systemctl reload nginx
```

백엔드 WSS 준비
- 백엔드는 `127.0.0.1:45444` 에서 WS로 리슨
- 클라이언트는 `wss://server.lunarsystem.co.kr:44444` 로 접속

## 방화벽/보안그룹 체크리스트

- AWS 보안그룹 예시: TCP 80, 443, 44444, 47017
- OS 방화벽(UFW 등) 개방
```bash
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true
sudo ufw allow 44444/tcp || true
sudo ufw allow 47017/tcp || true
```

## 기본 점검

- MongoDB
  - 서버 확인: `nc -zv 127.0.0.1 47017`
  - 원격: `mongo --host server.lunarsystem.co.kr --port 47017 -u ladmin -p` (클라이언트 설치 필요)
- WSS
  - 서버 확인: `wscat -c wss://server.lunarsystem.co.kr:44444` (wscat 필요)

## 참고/메모
- 44444 포트에서는 WSS만 사용하고, 백엔드는 45444 로컬 포트를 사용.
- 초기 비밀번호 및 보안 설정은 운영 투입 전에 변경/검토 권장.

