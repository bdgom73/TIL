---
title: "네트워크 핵심 프로토콜: TCP, HTTPS, 그리고 로드 밸런서"
date: 2025-09-22
categories: [Network, CS]
tags: [TCP, Handshake, HTTPS, TLS, Load Balancer, L4, L7, TIL]
excerpt: "TCP의 3-way/4-way Handshake와 Keep-Alive, HTTPS의 SSL/TLS Handshake 과정, 그리고 L4와 L7 로드 밸런서의 동작 방식과 차이점에 대해 깊이 있게 학습합니다."
author_profile: true
---

# Today I Learned: 네트워크 핵심 프로토콜: TCP, HTTPS, 그리고 로드 밸런서

## 📚 오늘 학습한 내용

안정적이고 확장성 있는 백엔드 시스템을 구축하기 위해서는 그 근간이 되는 네트워크 지식이 필수적입니다. 오늘은 데이터 통신의 신뢰성을 보장하는 TCP 연결 과정, 안전한 통신을 위한 HTTPS의 암호화 방식, 그리고 트래픽을 효율적으로 분산시키는 로드 밸런서의 동작 원리에 대해 학습했습니다.

---

### 1. **TCP 3-way/4-way Handshake와 HTTP Keep-Alive**

TCP는 신뢰성 있는 데이터 전송을 보장하는 프로토콜로, 통신 전에 반드시 연결을 수립하고(Handshake), 통신이 끝나면 연결을 해제하는 과정을 거칩니다.

#### **🤝 3-way Handshake: 연결 수립 과정**

클라이언트와 서버가 통신을 시작하기 전에 서로 준비가 되었는지 확인하는 과정입니다.

1.  **[SYN] Client → Server**: 클라이언트가 서버에 접속을 요청하는 `SYN`(Synchronize) 패킷을 보냅니다. 클라이언트는 `SYN_SENT` 상태가 됩니다.
2.  **[SYN+ACK] Server → Client**: 서버는 요청을 수락한다는 의미로 `SYN` 패킷과 함께 응답 `ACK`(Acknowledgement) 패킷을 보냅니다. 서버는 `SYN_RECEIVED` 상태가 됩니다.
3.  **[ACK] Client → Server**: 클라이언트는 서버의 응답을 잘 받았다는 `ACK` 패킷을 다시 서버로 보냅니다. 이 과정이 끝나면 클라이언트와 서버 모두 `ESTABLISHED` 상태가 되어 데이터 통신을 시작할 수 있습니다.



#### **👋 4-way Handshake: 연결 해제 과정**

연결을 안전하게 종료하기 위해 양방향 통신을 모두 확인하며 해제하는 과정입니다.

1.  **[FIN] Client → Server**: 클라이언트가 연결을 종료하겠다는 `FIN`(Finish) 패킷을 보냅니다.
2.  **[ACK] Server → Client**: 서버는 클라이언트의 요청을 잘 받았다는 `ACK`를 보냅니다. 이 때 서버는 아직 보낼 데이터가 남아있을 수 있으므로 연결을 바로 끊지 않고 `CLOSE_WAIT` 상태로 대기합니다.
3.  **[FIN] Server → Client**: 서버도 모든 데이터 전송을 마치면, 연결을 종료하겠다는 `FIN` 패킷을 클라이언트로 보냅니다.
4.  **[ACK] Client → Server**: 클라이언트는 서버의 종료 요청을 잘 받았다는 `ACK`를 보낸 후, 혹시 모를 패킷을 기다리는 `TIME_WAIT` 상태를 거쳐 연결을 최종 종료합니다.

#### **HTTP Keep-Alive**

-   **동작 원리**: HTTP 통신은 TCP 위에서 이루어집니다. `Keep-Alive` 옵션이 활성화되면, 한 번 수립된 TCP 연결(3-way handshake)을 바로 끊지 않고, 정해진 시간 동안 여러 HTTP 요청과 응답에 **재사용**합니다.
-   **장점**: 매번 요청마다 Handshake 과정을 반복하는 오버헤드를 줄여 애플리케이션의 응답 속도를 크게 향상시킵니다.

---

### 2. **HTTPS 동작 방식: SSL/TLS 핸드셰이크 과정**

HTTPS는 HTTP 통신을 **SSL/TLS(Secure Sockets Layer/Transport Layer Security)** 프로토콜을 통해 암호화하는 방식입니다. 이 과정의 핵심은 클라이언트와 서버가 안전하게 암호화 키를 교환하는 **SSL/TLS Handshake**입니다.

-   **암호화 방식**:
    -   **비대칭키 암호화 (Asymmetric Key)**: 공개키(Public Key)와 개인키(Private Key) 쌍을 사용합니다. 공개키로 암호화한 데이터는 개인키로만 복호화할 수 있습니다. Handshake 과정에서 **대칭키를 안전하게 교환**하는 데 사용됩니다.
    -   **대칭키 암호화 (Symmetric Key)**: 암호화와 복호화에 동일한 키(세션 키)를 사용합니다. 비대칭키 방식보다 훨씬 빠르기 때문에, Handshake가 끝난 후 **실제 데이터를 암호화**하는 데 사용됩니다.

#### **SSL/TLS Handshake 상세 과정**

1.  **[Client Hello] Client → Server**: 클라이언트가 지원하는 TLS 버전, 암호화 방식(Cipher Suites), 랜덤 데이터 등을 서버에 전송합니다.
2.  **[Server Hello] Server → Client**: 서버는 클라이언트가 보낸 암호화 방식 중 하나를 선택하고, 서버의 SSL 인증서(서버의 공개키 포함), 그리고 서버가 생성한 랜덤 데이터를 클라이언트에 전송합니다.
3.  **[Certificate Verification & Key Exchange] Client**:
    -   클라이언트는 서버로부터 받은 인증서가 신뢰할 수 있는 CA(Certificate Authority)에 의해 서명되었는지 검증합니다.
    -   검증이 완료되면, 클라이언트는 **대칭키로 사용할 키(Pre-Master Secret)**를 생성하여 **서버의 공개키로 암호화**한 뒤 서버에 전송합니다.
4.  **[Decryption & Session Key Creation] Server**:
    -   서버는 자신의 **개인키**로 클라이언트가 보낸 데이터를 복호화하여 Pre-Master Secret을 얻습니다.
    -   이제 클라이언트와 서버는 일련의 랜덤 데이터와 Pre-Master Secret을 조합하여, 실제 데이터를 암호화하고 복호화할 **대칭키(세션 키)**를 각각 생성합니다.
5.  **[Finished] Client ↔ Server**: 양측은 생성된 대칭키를 이용해 Handshake 과정을 완료했다는 암호화된 메시지를 서로 교환합니다. 이 과정이 끝나면 모든 HTTP 요청/응답은 이 **대칭키**로 암호화되어 전송됩니다.



---

### 3. **로드 밸런서 (L4 vs L7) 종류와 동작 방식 비교 분석**

**로드 밸런서**는 여러 대의 서버에 트래픽을 효율적으로 분산시켜 가용성과 확장성을 높이는 장비입니다. 동작하는 OSI 계층에 따라 L4와 L7 로드 밸런서로 나뉩니다.

#### **L4 로드 밸런서 (Transport Layer)**

-   **동작 방식**: OSI 4계층인 **전송 계층**의 정보를 바탕으로 트래픽을 분산합니다. 주로 **IP 주소와 포트 번호**를 보고 어떤 서버로 요청을 보낼지 결정합니다.
-   **특징**:
    -   **고속 처리**: 패킷의 내용을 보지 않고 IP와 포트 정보만 확인하므로 처리 속도가 매우 빠릅니다.
    -   **단순한 분산**: 라운드 로빈, 최소 연결 방식 등 단순한 알고리즘을 사용합니다.
    -   **유연성 부족**: HTTP 헤더나 URL 같은 애플리케이션 레벨의 정보를 분석할 수 없어, 특정 URL에 따라 다른 서버로 보내는 등의 세밀한 제어가 불가능합니다.

#### **L7 로드 밸런서 (Application Layer)**

-   **동작 방식**: OSI 7계층인 **애플리케이션 계층**의 정보를 바탕으로 트래픽을 분산합니다. **HTTP/HTTPS 헤더, URL 경로, 쿠키, 요청 메서드** 등 구체적인 내용을 분석하여 라우팅 결정을 내립니다.
-   **특징**:
    -   **지능적인 분산**: `/api/images/` 경로는 이미지 서버로, `/api/videos/` 경로는 비디오 서버로 보내는 등 **콘텐츠 기반 라우팅**이 가능합니다.
    -   **다양한 기능**: SSL Offloading(암복호화 처리), 캐싱, 보안(WAF) 등 다양한 부가 기능을 수행할 수 있습니다.
    -   **성능 부하**: 패킷의 내용을 모두 분석해야 하므로 L4에 비해 처리 속도가 느리고 리소스 소모가 큽니다.

| 구분 | **L4 로드 밸런서** | **L7 로드 밸런서** |
| :--- | :--- | :--- |
| **동작 계층** | Transport Layer (OSI 4계층) | Application Layer (OSI 7계층) |
| **분산 기준** | IP, Port | URL, HTTP Header, Cookie 등 |
| **처리 속도** | 매우 빠름 | 상대적으로 느림 |
| **라우팅** | 단순, 저수준 라우팅 | 지능적, 고수준 라우팅 |
| **주요 기능** | 트래픽 분산 (TCP/UDP) | 콘텐츠 기반 스위칭, SSL Offloading, WAF |
| **대표 장비** | LVS, NLB (AWS) | Nginx, HAProxy, ALB (AWS) |

---

## 💡 배운 점

1.  **신뢰성과 효율성의 트레이드오프**: TCP Handshake는 신뢰성을 보장하지만 오버헤드가 크며, `Keep-Alive`는 이 오버헤드를 줄여 효율성을 높이는 중요한 최적화 기법임을 이해했습니다.
2.  **보안 통신의 핵심 원리**: HTTPS는 속도가 빠른 대칭키와 키 교환이 안전한 비대칭키의 장점을 조합한 하이브리드 방식이라는 것을 명확히 알게 되었습니다. SSL 인증서의 역할은 서버의 신원을 보증하고 공개키를 안전하게 전달하는 것입니다.
3.  **상황에 맞는 로드 밸런싱 전략**: 단순하고 빠른 트래픽 분산이 필요할 때는 L4를, 특정 콘텐츠나 클라이언트 상태에 따라 정교한 제어가 필요할 때는 L7을 선택해야 하며, 현대 웹 애플리케이션 아키텍처에서는 L7의 역할이 더욱 중요해지고 있음을 깨달았습니다.

---

## 🔗 참고 자료

-   [TCP 3-Way Handshake (GeeksforGeeks)](https://www.geeksforgeeks.org/tcp-3-way-handshake-process/)
-   [How HTTPS Works (SSL.com)](https://www.ssl.com/article/how-https-works/)
-   [What is a Load Balancer? L4 vs L7 (NGINX)](https://www.nginx.com/resources/glossary/load-balancing/)