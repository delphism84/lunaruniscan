## 운영 계획

- 별도의 Nginx로 WSS(SSL) 포트를 운영한다.
- 외부: `server.lunarsystem.co.kr:44444` 에서 WSS 수신 → 내부: `127.0.0.1:45444` 로 프록시(업그레이드 헤더 포함)
  - 주의: 백엔드 WSS 서비스는 `127.0.0.1:45444` 로 리슨하도록 맞춘다. Nginx가 44444를 점유하므로 충돌 방지.
- 인증서: `server.lunarsystem.co.kr` 도메인에 대해 Let's Encrypt 발급/자동 갱신
- 데이터베이스: MongoDB LTS, 외부 접속 허용 포트 47017, 기본 DB `lunarUniScanner`

사전 준비
- DNS: `server.lunarsystem.co.kr` → 현재 서버 공인 IP로 A레코드 설정
- 보안그룹/방화벽: 80, 443, 44444, 47017 TCP 열기 (아래 체크리스트 참고)

## 디렉터리 구조 (Bind Mount)

- 루트: `/var/uniscanner/docker`
- 데이터: `/var/uniscanner/docker/data/mongo`
- 초기화 스크립트: `/var/uniscanner/docker/mongo-init/init.js`
- 로그/기타: `/var/uniscanner/docker/logs`, `/var/uniscanner/docker/config`

## Docker 설치 (Ubuntu/Debian 계열)

```bash
sudo apt-get update -y && sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
# 현재 세션엔 즉시 반영되지 않지만 추후를 위해 사용자 도커 그룹 추가
sudo usermod -aG docker "$USER"
```

확인
```bash
docker --version
docker compose version
```

## Docker Compose 파일 작성

경로: `/var/uniscanner/docker/docker-compose.yml`

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
      - /var/uniscanner/docker/data/mongo:/data/db
      - /var/uniscanner/docker/mongo-init:/docker-entrypoint-initdb.d:ro
```

초기화 스크립트 작성
- 경로: `/var/uniscanner/docker/mongo-init/init.js`
```javascript
// create initial db
var dbName = 'lunarUniScanner';
var dbRef = db.getSiblingDB(dbName);
// touch a collection to ensure creation
if (!dbRef.getCollectionNames().includes('init')) {
  dbRef.createCollection('init');
}
```

기동
```bash
sudo mkdir -p /var/uniscanner/docker/{data/mongo,logs,config} /var/uniscanner/docker/mongo-init
# 위 경로에 docker-compose.yml, init.js 배치 후
sudo docker compose -f /var/uniscanner/docker/docker-compose.yml up -d
sudo docker ps | cat
```

외부 접속 확인 (임시)
```bash
# 동일 서버에서 포트 오픈 여부 점검
nc -zv 127.0.0.1 47017 || true
```

원격 접속 가이드
- 접속 URI: `mongodb://ladmin:YOUR_PASSWORD@SERVER_IP:47017/admin`
- 초기 비밀번호: `Eldpdj!@34` (필수 변경 권장)

## Nginx 및 Certbot 설치

```bash
sudo apt-get update -y && sudo apt-get install -y nginx certbot python3-certbot-nginx
sudo systemctl enable --now nginx
```

인증서 발급 (무인)
```bash
# DNS가 서버로 올바르게 향할 때 실행
sudo certbot certonly --nginx -d server.lunarsystem.co.kr --agree-tos -n --register-unsafely-without-email
# 성공 시 인증서 경로:
# /etc/letsencrypt/live/server.lunarsystem.co.kr/fullchain.pem
# /etc/letsencrypt/live/server.lunarsystem.co.kr/privkey.pem
```

## Nginx WSS 리버스 프록시(44444)

경로: `/etc/nginx/sites-available/uniscanner-wss-44444`

```nginx
server {
    listen 44444 ssl;
    server_name server.lunarsystem.co.kr;

    ssl_certificate     /etc/letsencrypt/live/server.lunarsystem.co.kr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/server.lunarsystem.co.kr/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # 웹소켓 업그레이드
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
# 사이트 활성화
sudo ln -sf /etc/nginx/sites-available/uniscanner-wss-44444 /etc/nginx/sites-enabled/uniscanner-wss-44444
# 문법 검사 및 재시작
sudo nginx -t && sudo systemctl reload nginx
```

백엔드 WSS 서비스 예시
- 서비스는 `127.0.0.1:45444` 에서 WS로 리슨
- 클라이언트는 `wss://server.lunarsystem.co.kr:44444` 로 접속

## 방화벽/보안그룹 체크리스트

- AWS 보안그룹 인바운드 허용: TCP 80, 443, 44444, 47017
- OS 방화벽(UFW 등) 사용 시:
```bash
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true
sudo ufw allow 44444/tcp || true
sudo ufw allow 47017/tcp || true
```

## 기본 점검

- MongoDB
  - 서버 내부: `nc -zv 127.0.0.1 47017`
  - 원격: `mongo --host server.lunarsystem.co.kr --port 47017 -u ladmin -p` (클라이언트 설치 필요)
- WSS
  - 서버 외부: `wscat -c wss://server.lunarsystem.co.kr:44444` (wscat 필요)

## 참고/메모
- 44444 포트는 외부 WSS용으로 예약됨. 내부 백엔드는 45444 등 별도 포트를 사용.
- 초기 비밀번호 및 포트는 운영 투입 전 변경/검토 권장.

