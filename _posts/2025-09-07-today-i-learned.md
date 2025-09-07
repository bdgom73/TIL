---
title: "Nginx 경로 기반 라우팅으로 API 게이트웨이 구현하기"
date: 2025-09-07
categories: [DevOps, Nginx]
tags: [Nginx, Reverse Proxy, API Gateway, MSA]
excerpt: "하나의 도메인으로 들어오는 요청을 경로에 따라 다른 백엔드 서버로 분기하는 Nginx의 경로 기반 라우팅에 대해 학습했다. MSA 환경에서 API 게이트웨이를 구축하는 핵심 원리를 정리한다."
author_profile: true
Today I Learned: Nginx 경로 기반 라우팅으로 API 게이트웨이 구현하기
---

**API 게이트웨이(API Gateway)**란, 클라이언트의 모든 요청을 받아 적절한 마이크로서비스로 전달하는 중앙 진입점(Entry Point) 역할을 하는 서버다. 복잡한 MSA(마이크로서비스 아키텍처) 환경에서 이는 선택이 아닌 필수다. 잘못된 라우팅 처리로 인해 발생하는 문제는 다음과 같다:

* **클라이언트 복잡도 증가**: 클라이언트가 모든 서비스의 주소(IP, 포트)를 직접 관리해야 하는 문제.
* **인증/인가 로직 중복**: 각 서비스마다 공통적인 인증, 로깅, 모니터링 로직을 개별적으로 구현해야 하는 비효율.

### Nginx의 역할 📜

Nginx는 리버스 프록시(Reverse Proxy) 기능을 통해 이러한 문제를 해결하는 강력한 API 게이트웨이 솔루션이 될 수 있다. 오늘은 Nginx의 경로 기반 라우팅을 활용해 이 문제를 해결하는 방법을 배웠다.

### Nginx 라우팅의 핵심 개념 🔗

**경로 기반 라우팅(Path-Based Routing)**은 요청된 URL의 경로(Path)를 분석하여 미리 정의된 규칙에 따라 다른 백엔드 서버로 요청을 전달하는 기술이다. 이를 가능하게 하는 Nginx의 핵심 지시어는 `location`과 `proxy_pass`다.

* `location [경로] { ... }`: 특정 경로(URI)에 대한 요청을 어떻게 처리할지 정의하는 블록이다. Nginx는 클라이언트의 요청 URI와 `location` 지시어에 명시된 경로를 비교하여 일치하는 블록의 설정을 적용한다.
* `proxy_pass [주소]`: `location` 블록 내에서 사용되며, 일치된 요청을 전달할 백엔드 서버(프로토콜 포함)의 주소를 지정한다.

### Nginx 설정 예시 📝

아래는 `/api/users/`로 들어오는 요청은 **User 서비스**로, `/api/orders/`로 들어오는 요청은 **Order 서비스**로 분기하는 간단한 API 게이트웨이 설정 예시다.

```nginx
http {
    # 백엔드 마이크로서비스 그룹을 정의합니다.
    # 로드 밸런싱을 위해 여러 서버를 추가할 수도 있습니다.
    upstream user_service {
        server 127.0.0.1:8001; # User 서비스 주소
    }

    upstream order_service {
        server 127.0.0.1:8002; # Order 서비스 주소
    }

    server {
        listen 80; # API 게이트웨이는 80번 포트로 요청을 받습니다.

        # /api/users/ 경로로 시작하는 모든 요청을 처리합니다.
        location /api/users/ {
            # 매칭된 경로를 제외한 나머지 경로를 백엔드로 전달하기 위해
            # proxy_pass 주소 끝에 '/'를 붙여줍니다.
            # 예: /api/users/1 -> http://user_service/1
            proxy_pass http://user_service/;

            # 클라이언트의 원래 요청 헤더 정보를 백엔드 서버로 전달합니다.
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # /api/orders/ 경로로 시작하는 모든 요청을 처리합니다.
        location /api/orders/ {
            # 예: /api/orders/detail -> http://order_service/detail
            proxy_pass http://order_service/;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

### 정리하며 ✨

위와 같이 Nginx를 설정하면 클라이언트는 API 게이트웨이의 단일 주소(`http://your-domain.com`)만 알고 있으면 된다. Nginx가 마치 교통정리를 하듯, URL 경로에 따라 내부 마이크로서비스로 요청을 알아서 분배해준다. 이를 통해 클라이언트는 백엔드 구조의 복잡성을 알 필요가 없어지고, 각 마이크로서비스는 자신의 핵심 비즈니스 로직에만 집중할 수 있게 된다. 이것이 바로 Nginx를 활용한 API 게이트웨이 구축의 핵심 원리다.