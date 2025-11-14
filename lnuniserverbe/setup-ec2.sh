#!/bin/bash

# EC2 Ubuntu 서버 설정 스크립트

# 시스템 업데이트
sudo apt update && sudo apt upgrade -y

# Docker 설치
sudo apt install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# .NET 8 설치
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt update
sudo apt install -y dotnet-sdk-8.0

# Node.js 설치 (NextJS용)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Nginx 설치 (Docker 대신 직접 설치하는 경우)
sudo apt install -y nginx

# 방화벽 설정
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

# SSL 인증서 초기 발급 (도메인 설정 후 실행)
# sudo certbot --nginx -d domain1.com -d www.domain1.com -d api.domain1.com

echo "EC2 서버 설정 완료!"
echo "다음 단계:"
echo "1. 도메인 DNS를 EC2 IP로 설정"
echo "2. SSL 인증서 발급: sudo certbot --nginx -d yourdomain.com"
echo "3. Docker Compose 실행: docker-compose up -d"
