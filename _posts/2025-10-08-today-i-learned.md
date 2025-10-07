---
title: "MSA의 관문: Spring Cloud Gateway를 넘어 Kong, Apigee 살펴보기"
date: 2025-10-10
categories: [Architecture, MSA]
tags: [API Gateway, Kong, Apigee, Spring Cloud Gateway, MSA, TIL]
excerpt: "Spring Cloud Gateway를 넘어, 엔터프라이즈 환경에서 널리 사용되는 전문 API Gateway 솔루션인 Kong과 Apigee의 특징과 장단점을 비교 분석합니다. 각 솔루션이 어떤 상황에 더 적합한지 그 차이점을 알아봅니다."
author_profile: true
---

# Today I Learned: MSA의 관문: Spring Cloud Gateway를 넘어 Kong, Apigee 살펴보기

## 📚 오늘 학습한 내용

마이크로서비스 아키텍처(MSA)에서 **API Gateway**는 모든 클라이언트 요청의 단일 진입점 역할을 하며, 라우팅, 인증/인가, 로깅 등 공통 기능을 처리하는 핵심 컴포넌트입니다. Spring 생태계에서는 주로 **Spring Cloud Gateway**를 사용하지만, 더 복잡하고 규모가 큰 시스템에서는 **Kong**이나 **Apigee**와 같은 전문 솔루션들이 사용됩니다. 오늘은 이들 API Gateway 솔루션들의 특징을 비교하며 각각 어떤 상황에 더 적합한지 학습했습니다.

---

### 1. **Spring Cloud Gateway: Spring 개발자를 위한 맞춤형 게이트웨이**

-   **특징**: Spring WebFlux 기반으로 동작하는 **라이브러리 형태**의 게이트웨이입니다. 별도의 서버가 아닌, 하나의 Spring Boot 애플리케이션으로 실행됩니다.
-   **장점**:
    -   **높은 통합성**: Spring Boot, Spring Security 등 다른 Spring 프로젝트와 매우 자연스럽게 통합됩니다.
    -   **유연성**: Java와 Spring에 익숙한 개발자라면 필터를 직접 코드로 구현하는 등 매우 정교하고 복잡한 라우팅 로직을 쉽게 작성할 수 있습니다.
-   **단점**:
    -   **언어 종속성**: Java와 Spring 생태계에 강하게 결합되어 있어, 다양한 언어로 구성된 폴리글랏(Polyglot) MSA 환경에는 부적합할 수 있습니다.
    -   **관리 기능 부족**: API 사용량 분석, 개발자 포털, 수익화(Monetization) 등 전문적인 API 관리 기능은 내장하고 있지 않습니다.

---

### 2. **Kong: 성능과 확장성에 초점을 맞춘 오픈소스 게이트웨이 🦍**

-   **특징**: Nginx 기반으로 구축된 고성능 오픈소스 API Gateway입니다. **플러그인(Plugin)** 아키텍처를 통해 기능을 자유롭게 확장할 수 있는 것이 가장 큰 특징입니다.
-   **장점**:
    -   **압도적인 성능**: C와 Lua로 작성되어 매우 빠르고 낮은 지연 시간(Latency)을 보장합니다.
    -   **플랫폼 독립성**: 특정 언어나 프레임워크에 종속되지 않아 어떤 기술 스택으로 구성된 MSA 환경에도 적용할 수 있습니다.
    -   **강력한 확장성**: 인증, 보안, 트래픽 제어, 로깅 등 수많은 기능을 플러그인 형태로 손쉽게 추가하거나 제거할 수 있습니다.
    -   **클라우드 네이티브**: Kubernetes Ingress Controller로도 널리 사용되며, 컨테이너 환경과 잘 통합됩니다.
-   **단점**:
    -   **상대적으로 가파른 학습 곡선**: 다양한 플러그인과 Kong의 자체 관리 API를 학습하는 데 시간이 걸릴 수 있습니다.
    -   고급 기능(관리 UI, 개발자 포털 등)은 유료 버전인 **Kong Enterprise**에서 제공됩니다.



---

### 3. **Apigee (Google Cloud): 포괄적인 API 관리 플랫폼 ☁️**

-   **특징**: 단순한 게이트웨이를 넘어, API의 설계, 보안, 배포, 분석, 수익화 등 **API 생명주기 전체를 관리**하는 Google Cloud의 완전 관리형(Fully-managed) 플랫폼입니다.
-   **장점**:
    -   **강력한 분석 및 모니터링**: API 트래픽, 에러율, 응답 시간 등 상세한 분석 데이터를 대시보드를 통해 제공하여 비즈니스 인사이트를 얻기 용이합니다.
    -   **개발자 생태계 구축**: 외부 개발자들이 API를 쉽게 사용해 볼 수 있도록 **개발자 포털**을 제공하고, API 사용량에 따라 과금하는 **수익화 모델**을 쉽게 구축할 수 있습니다.
    -   **엔터프라이즈급 보안**: OAuth 2.0, SAML, 위협 탐지 등 복잡한 보안 정책을 손쉽게 설정하고 적용할 수 있습니다.
-   **단점**:
    -   **높은 비용**: 포괄적인 기능을 제공하는 만큼 다른 솔루션에 비해 비용이 비쌉니다.
    -   **특정 벤더 종속성**: Google Cloud Platform에 깊이 통합되어 있어 다른 클라우드 환경으로의 이전이 어려울 수 있습니다.

---

### 4. **솔루션 비교 요약**

| 구분 | **Spring Cloud Gateway** | **Kong (Open Source)** | **Apigee (Google Cloud)** |
| :--- | :--- | :--- | :--- |
| **형태** | 라이브러리 (Spring Boot 앱) | 독립적인 애플리케이션 | 완전 관리형 서비스 (PaaS) |
| **주요 사용 사례** | Spring 기반 MSA 환경 | 고성능/확장성/유연성이 중요한 환경 | API 생태계 구축 및 비즈니스 분석 |
| **성능** | 좋음 (논블로킹 I/O) | 매우 뛰어남 (Nginx 기반) | 좋음 (Google 인프라 기반) |
| **확장성** | Java 코드로 직접 구현 | 플러그인 아키텍처 | 정책 기반 설정 |
| **주요 특징** | Spring 생태계와의 완벽한 통합 | 플랫폼 독립성, 다양한 플러그인 | 개발자 포털, API 분석, 수익화 |
| **적합한 환경** | 소~중규모, Spring 중심 프로젝트 | 중~대규모, 폴리글랏 MSA, 클라우드 네이티브 | 대규모 엔터프라이즈, API 비즈니스 |

---

## 💡 배운 점

1.  **API Gateway는 기술 선택의 폭이 넓다**: 단순히 요청을 라우팅하는 것을 넘어, 비즈니스의 규모와 목적에 따라 선택할 수 있는 다양한 스펙트럼의 솔루션이 존재한다는 것을 알게 되었습니다.
2.  **'Gateway' vs. 'API Management'**: Spring Cloud Gateway나 Kong이 기술적인 '게이트웨이' 역할에 집중한다면, Apigee는 API를 하나의 '제품(Product)'으로 보고 그 가치를 극대화하는 'API 관리'의 영역까지 다룬다는 차이점을 명확히 이해했습니다.
3.  **상황에 맞는 도구 선택의 중요성**: 우리 팀의 기술 스택이 주로 Spring으로 구성되어 있고 빠른 개발 속도가 중요하다면 Spring Cloud Gateway가 합리적일 것입니다. 반면, 최고의 성능이 필요하고 다양한 언어의 서비스를 통합해야 한다면 Kong이, API를 외부에 판매하고 파트너 생태계를 구축해야 한다면 Apigee가 더 나은 선택이 될 수 있다는 점을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Cloud Gateway (Official Docs)](https://spring.io/projects/spring-cloud-gateway)
-   [Kong API Gateway (Official Website)](https://konghq.com/kong)
-   [Google Cloud Apigee (Official Website)](https://cloud.google.com/apigee)