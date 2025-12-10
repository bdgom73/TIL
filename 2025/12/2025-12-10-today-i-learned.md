---
title: "Spring Boot 3.x Observability: Micrometer Tracing으로 분산 추적(Distributed Tracing) 구현하기"
date: 2025-12-10
categories: [DevOps, Observability]
tags: [Spring Boot 3, Micrometer Tracing, Zipkin, Distributed Tracing, Sleuth, Observability, TIL]
excerpt: "MSA 환경에서 여러 마이크로서비스를 거쳐가는 요청의 흐름을 추적하기 위해, Spring Cloud Sleuth를 대체하는 Spring Boot 3의 표준 관측성 도구인 Micrometer Tracing과 Zipkin을 적용하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Boot 3.x Observability: Micrometer Tracing으로 분산 추적(Distributed Tracing) 구현하기

## 📚 오늘 학습한 내용

마이크로서비스 아키텍처(MSA)에서는 클라이언트의 HTTP 요청 하나가 Gateway, Service A, Service B, DB 등을 거치며 처리됩니다. 특정 요청에서 에러가 발생했을 때, 각 서비스의 로그 파일이 분산되어 있어 원인을 추적하기가 매우 어렵습니다.

과거 Spring Boot 2.x에서는 **Spring Cloud Sleuth**가 이 문제를 해결했지만, Spring Boot 3.x부터는 Sleuth가 삭제되고 **Micrometer Tracing**으로 통합되었습니다. 오늘은 변화된 추적(Tracing) 생태계와 적용 방법을 학습했습니다.

---

### 1. **핵심 개념: Trace ID와 Span ID 🕵️‍♀️**

분산 추적 시스템은 요청 헤더에 식별자를 주입하여 전파(Propagation)하는 방식으로 동작합니다.



-   **Trace ID**: 하나의 요청 트랜잭션 전체를 관통하는 고유 ID입니다. (Client -> A -> B -> End) 모든 구간에서 동일하게 유지됩니다.
-   **Span ID**: 각 서비스나 컴포넌트(작업 단위) 내에서의 고유 ID입니다. 서비스 A에서 B로 넘어갈 때 새로운 Span ID가 생성되며, 부모-자식 관계를 형성합니다.

---

### 2. **Spring Boot 3.x에서의 변화 (Sleuth -> Micrometer)**

Spring Boot 3에서는 관측성(Observability)이 프레임워크 코어 레벨로 들어왔습니다.

-   **Legacy**: `Spring Cloud Sleuth` (Boot 3에서 제거됨)
-   **Current**: `Micrometer Tracing` + `Brave` (또는 OpenTelemetry)

이제 별도의 Spring Cloud 의존성 관리 없이, Micrometer 의존성만으로 추적 기능을 구현할 수 있습니다.

---

### 3. **Zipkin 연동 구현하기**

로그에 Trace ID를 남기는 것을 넘어, 시각화 도구인 **Zipkin** 서버로 추적 데이터를 전송하는 설정을 진행합니다.

#### **Step 1: 의존성 추가 (`build.gradle`)**

```groovy
// 1. Actuator (Metric & Tracing 기능의 기반)
implementation 'org.springframework.boot:spring-boot-starter-actuator'

// 2. Micrometer Tracing (추적 Facade)
implementation 'io.micrometer:micrometer-tracing-bridge-brave' 

// 3. Zipkin Reporter (추적 데이터를 Zipkin으로 전송)
implementation 'io.zipkin.reporter2:zipkin-reporter-brave'
```
> **참고**: `brave` 대신 `otel`(OpenTelemetry) 브릿지를 사용할 수도 있습니다. 여기서는 기존 Sleuth와 호환성이 좋은 Brave를 사용했습니다.

#### **Step 2: `application.yml` 설정**

```yaml
management:
  tracing:
    sampling:
      probability: 1.0 # 1.0 = 모든 요청을 추적 (운영환경에서는 0.1 등으로 조정 권장)
    propagation:
      type: w3c # or b3 (헤더 전송 방식 표준 설정)
  
  zipkin:
    tracing:
      endpoint: "http://localhost:9411/api/v2/spans" # Zipkin 서버 주소

logging:
  pattern:
    # 로그 포맷에 TraceID와 SpanID 포함시키기
    level: "%5p [${spring.application.name:},%X{traceId:-},%X{spanId:-}]"
```

#### **Step 3: 동작 확인**

서비스 A에서 서비스 B를 호출하는 로직(`RestTemplate` 또는 `FeignClient` 사용)을 수행하면, 로그에 자동으로 ID가 찍힙니다.

**Console Log:**
```text
INFO [order-service,6575a6c3f9d2e1a2,6575a6c3f9d2e1a2] : Order created...
INFO [payment-service,6575a6c3f9d2e1a2,8b2c1d3e4f5a6b7c] : Payment processing...
```
-   `order-service`와 `payment-service`가 서로 다른 서버임에도 **동일한 Trace ID** (`6575a6c3f9d2e1a2`)를 공유하는 것을 볼 수 있습니다.

---

### 4. **Zipkin UI를 통한 시각화**

Docker로 Zipkin 서버를 띄우고(`docker run -d -p 9411:9411 openzipkin/zipkin`), 브라우저에서 접속하면 다음과 같은 정보를 볼 수 있습니다.

1.  **Dependency Graph**: 서비스 간의 호출 관계가 자동으로 그려집니다. (어떤 서비스가 어떤 서비스를 호출했는가?)
2.  **Latency Analysis**: 전체 요청 시간 중 어느 구간(서비스)에서 가장 시간이 많이 소요되었는지 막대그래프로 확인 가능합니다. (병목 지점 파악)
3.  **Error Tracking**: 호출 체인 중 어느 지점에서 500 에러가 발생했는지 붉은색으로 표시됩니다.

---

## 💡 배운 점

1.  **Spring Boot 3의 Observability 통합**: 과거에는 Sleuth, Micrometer, Actuator가 따로 노는 느낌이었는데, 3.x부터는 `Micrometer`라는 우산 아래 메트릭(Metric)과 추적(Tracing)이 일관성 있게 통합되었다는 점을 체감했습니다.
2.  **샘플링 비율(Sampling Rate)의 중요성**: `probability: 1.0`은 개발계에서는 좋지만, 운영계에서 모든 요청을 Zipkin으로 보내면 네트워크와 저장소에 엄청난 부하를 줍니다. 트래픽에 따라 적절한 비율(e.g., 0.05)을 설정하는 것이 운영 노하우임을 알게 되었습니다.
3.  **문제 해결 시간(MTTR) 단축**: "결제가 왜 안 돼요?"라는 문의가 왔을 때, 이전에는 로그 파일 3개를 뒤졌다면, 이제는 Trace ID 하나만으로 전체 흐름을 한눈에 보고 "결제 서비스의 DB 타임아웃이 원인입니다"라고 즉시 파악할 수 있는 환경이 구축되었습니다.

---

## 🔗 참고 자료

-   [Spring Boot 3.0 Migration Guide (Observability)](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Migration-Guide#observability)
-   [Micrometer Tracing Documentation](https://micrometer.io/docs/tracing)
-   [Zipkin Architecture](https://zipkin.io/pages/architecture.html)