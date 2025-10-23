---
title: "Nginx: 리버스 프록시와 로드 밸런서로 Spring Boot 배포하기"
date: 2025-10-23
categories: [DevOps, Nginx]
tags: [Nginx, Reverse Proxy, Load Balancer, Spring Boot, SSL, DevOps, TIL]
excerpt: "Spring Boot 애플리케이션을 단독으로 외부에 노출하는 대신, Nginx를 리버스 프록시(Reverse Proxy)로 앞에 두어야 하는 이유를 학습합니다. Nginx를 통해 SSL 적용, 로드 밸런싱, 정적 파일 서빙을 처리하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Nginx: 리버스 프록시와 로드 밸런서로 Spring Boot 배포하기

## 📚 오늘 학습한 내용

저는 3년 넘게 Spring Boot로 서버를 개발하면서, `java -jar app.jar` 명령어로 내장된 Tomcat(포트 8080)을 실행하는 데 익숙했습니다. 하지만 실제 운영 환경에서는 사용자가 80(HTTP)이나 443(HTTPS) 포트로 접속하며, 8080 포트를 직접 노출하는 경우는 거의 없습니다.

오늘은 왜 **Nginx** 같은 웹 서버를 Spring Boot 애플리케이션 앞에 두어야 하는지, 그리고 Nginx를 **리버스 프록시(Reverse Proxy)** 및 **로드 밸런서(Load Balancer)**로 활용하는 방법을 학습했습니다.

---

### 1. **왜 Nginx를 리버스 프록시로 사용해야 하는가? 🤔**

Spring Boot의 내장 Tomcat도 훌륭한 WAS(Web Application Server)이지만, 다음과 같은 작업에는 전문화되어 있지 않습니다.

1.  **보안 (포트 노출)**: Linux/Unix에서 1024번 미만(e.g., 80, 443)의 포트를 열려면 root 권한이 필요합니다. Java 애플리케이션을 root 권한으로 실행하는 것은 심각한 보안 위협입니다. Nginx가 80/443 포트를 리스닝하고, 일반 유저 권한으로 실행된 Spring Boot(e.g., 8080)로 요청을 전달하는 것이 훨씬 안전합니다.
2.  **SSL/TLS 처리 (HTTPS)**: Spring Boot 자체에서 SSL을 설정할 수도 있지만, 인증서를 관리하고 적용하는 과정이 Nginx보다 훨씬 복잡합니다. Nginx에 SSL 인증서를 적용하고(SSL Termination), Nginx와 내부 Spring Boot 간에는 가벼운 HTTP 통신을 하도록 구성하는 것이 일반적입니다.
3.  **정적 파일 서빙**: React, Vue 등으로 빌드된 정적 파일(JS, CSS, HTML)을 Tomcat이 서빙하는 것은 비효율적입니다. Nginx는 정적 파일을 매우 빠르고 효율적으로 서빙하도록 설계되었습니다.
4.  **로드 밸런싱**: 여러 대의 Spring Boot 서버를 실행하여 가용성을 높일 때, Nginx가 이 서버들로 트래픽을 분산하는 로드 밸런서 역할을 수행할 수 있습니다.

---

### 2. **리버스 프록시 (Reverse Proxy) 설정 🛡️**

리버스 프록시는 클라이언트의 요청을 받아, 내부망에 있는 백엔드 서버(Spring Boot)로 전달해주는 '대리인' 역할을 합니다.

-   **흐름**: Client → Nginx (Public IP, 443) → Spring Boot (localhost, 8080)

가장 기본적인 Nginx 설정 파일 (`/etc/nginx/sites-available/default`) 예시입니다.

```nginx
# /etc/nginx/sites-available/default

server {
    listen 80; # 80 포트로 들어오는 요청을 리스닝
    server_name mydomain.com; # 이 도메인으로 들어오는 요청을 처리

    # 80 포트 요청을 443(HTTPS)으로 리다이렉트 (선택 사항)
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl; # 443 포트(HTTPS) 리스닝
    server_name mydomain.com;

    # SSL 인증서 설정 (Let's Encrypt 등)
    ssl_certificate /etc/letsencrypt/live/mydomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mydomain.com/privkey.pem;

    # / (루트 경로)로 오는 모든 요청을
    location / {
        # http://localhost:8080 으로 넘긴다 (Spring Boot 애플리케이션)
        proxy_pass http://localhost:8080; 
        
        # 실제 클라이언트 IP와 호스트 정보를 헤더에 담아 넘겨준다
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

### 3. **로드 밸런싱 (Load Balancing) 설정 ⚖️**

애플리케이션의 가용성을 높이기 위해, Spring Boot 인스턴스를 두 대(e.g., 8080, 8081) 실행하고 Nginx가 트래픽을 분산하도록 설정할 수 있습니다.

```nginx
# /etc/nginx/nginx.conf (http 블록 내부)

# 1. 'upstream' 블록에 백엔드 서버 그룹을 정의
upstream my_spring_app {
    # 기본 방식은 round_robin
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
}

# /etc/nginx/sites-available/default (server 블록 내부)

server {
    listen 443 ssl;
    server_name mydomain.com;
    # ... (SSL 설정 동일) ...

    location / {
        # 2. proxy_pass 대상을 'localhost:8080'이 아닌 'upstream' 이름으로 변경
        proxy_pass http://my_spring_app; 
        
        # ... (proxy_set_header 동일) ...
    }
}
```
이제 Nginx는 `mydomain.com`으로 들어오는 요청을 8080 포트와 8081 포트의 서버로 번갈아가며(Round-Robin) 분배합니다. 만약 8080 서버가 죽더라도 Nginx가 이를 감지하고 8081로만 요청을 보내어 서비스 중단을 막을 수 있습니다.

---

## 💡 배운 점

1.  **관심사의 분리 (SoC)**: Nginx와 Spring Boot의 역할을 명확히 분리하는 것이 핵심이었습니다. **Nginx는 '네트워킹과 보안'**을, **Spring Boot(Tomcat)는 '비즈니스 로직 실행'**을 담당합니다. 이는 각자가 가장 잘하는 일에 집중하게 하여 시스템 전체의 안정성과 효율성을 높입니다.
2.  **SSL Termination의 편리함**: Spring Boot에 JKS 키스토어를 설정하고 HTTPS를 적용하는 것보다, Nginx에서 SSL을 처리하는(SSL Termination) 것이 훨씬 간편하고 중앙 관리하기 용이합니다. Let's Encrypt의 `certbot`을 사용하면 이 과정이 거의 자동화됩니다.
3.  **무중단 배포의 기반**: 로드 밸런싱(`upstream`) 구성은 Blue/Green 배포나 카나리 배포 같은 무중단 배포 전략을 구현하기 위한 첫걸음입니다. 배포 시 `upstream` 목록을 동적으로 변경하여 트래픽을 제어할 수 있다는 것을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Nginx Docs - Reverse Proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
-   [Nginx Docs - Load Balancer](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/)
-   [Spring Boot with Nginx (Baeldung)](https://www.baeldung.com/spring-boot-nginx-reverse-proxy)