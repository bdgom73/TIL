---
title: "Observability의 완성: Micrometer Tracing과 OpenTelemetry로 분산 추적하기"
date: 2025-10-26
categories: [DevOps, MSA]
tags: [Observability, Distributed Tracing, Micrometer Tracing, OpenTelemetry, Zipkin, Spring Boot, TIL]
excerpt: "MSA 환경에서 발생하는 로그 파편화 문제를 해결하기 위한 분산 추적(Distributed Tracing)의 개념을 학습합니다. Spring Boot 3의 표준인 Micrometer Tracing과 OpenTelemetry(OTel)를 사용하여 Zipkin으로 트레이스를 시각화하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Observability의 완성: Micrometer Tracing과 OpenTelemetry로 분산 추적하기

## 📚 오늘 학습한 내용

MSA(마이크로서비스 아키텍처) 환경에서 장애가 발생했을 때, 저는 종종 '로그 파편화' 문제에 부딪혔습니다. 사용자 요청 하나를 처리하기 위해 `A 서비스` -> `B 서비스(Kafka)` -> `C 서비스`로 이어지는 복잡한 호출 체인이 발생할 때, 각 서비스의 로그 파일이 뿔뿔이 흩어져 있어 에러의 근본 원인을 찾거나 전체 요청의 흐름을 파악하기가 매우 어려웠습니다.

오늘은 `Metrics`(Micrometer)와 `Logging`에 이어 **Observability(관찰 가능성)의 세 번째 기둥**이라 불리는 **분산 추적(Distributed Tracing)**에 대해 학습했습니다. Spring Boot 3부터 표준이 된 **Micrometer Tracing**과 **OpenTelemetry(OTel)**를 중심으로 정리했습니다.

---

### 1. **분산 추적(Distributed Tracing)이란?**

분산 추적은 여러 서비스에 걸친 하나의 요청 흐름을 **시각적으로 추적**할 수 있도록 만드는 기술입니다. 이를 위해 두 가지 핵심 개념을 사용합니다.

-   **Trace (트레이스)**: 하나의 사용자 요청으로 시작되어 여러 서비스를 거치는 **전체 트랜잭션의 여정**.
-   **Span (스팬)**: Trace를 구성하는 **개별 작업 단위**. (e.g., `A 서비스`의 API 호출, `B 서비스`의 DB 쿼리)



이 모든 것을 하나로 묶는 열쇠가 바로 **Trace ID**입니다.
1.  사용자의 첫 요청이 `A 서비스`(Gateway 등)에 도착하면, 고유한 **Trace ID**가 생성됩니다.
2.  `A 서비스`가 `B 서비스`를 호출할 때, 이 **Trace ID**를 HTTP 헤더(혹은 Kafka 헤더)에 담아 함께 전파(Propagate)시킵니다.
3.  `B 서비스`와 `C 서비스`는 이 Trace ID를 받아 자신의 로그와 스팬(Span)에 기록합니다.

결과적으로, **Zipkin**이나 Jaeger 같은 분산 추적 시스템에서 이 **Trace ID** 하나만 검색하면, 모든 서비스에 흩어져 있던 로그와 작업 단위(Span)들이 하나의 시간 순서도(Gantt 차트)로 완벽하게 재구성되어 나타납니다.

---

### 2. **Spring Boot 3의 현대적인 트레이싱 스택: Micrometer + OTel**

과거에는 Spring Cloud Sleuth를 사용했지만, Spring Boot 3부터는 Micrometer가 이 역할을 담당합니다.

-   **Micrometer Tracing**: `Micrometer Metrics`가 Prometheus, Datadog 등 다양한 모니터링 시스템의 '측정' 인터페이스를 제공했듯, `Micrometer Tracing`은 OpenTelemetry, Zipkin Brave 등 다양한 트레이서의 **'추적'을 위한 표준 인터페이스(API)**를 제공합니다. (SLF4J와 같은 역할)
-   **OpenTelemetry (OTel)**: `Micrometer Tracing` API의 **표준 구현체**입니다. (Logback과 같은 역할)
-   **Zipkin Exporter**: OTel이 수집한 트레이스 데이터를 **Zipkin 서버**로 전송하는 '내보내기' 도구입니다.

---

### 3. **Spring Boot 3에 적용하기**

**1. `build.gradle` 의존성 추가**
```groovy
dependencies {
    // 1. Micrometer Tracing의 핵심 API
    implementation 'io.micrometer:micrometer-tracing-bridge-otel'
    
    // 2. Zipkin으로 데이터를 내보내는 Exporter
    implementation 'io.opentelemetry:opentelemetry-exporter-zipkin'
    
    // Actuator는 트레이싱을 포함한 다양한 관리 엔드포인트를 제공
    implementation 'org.springframework.boot:spring-boot-starter-actuator'
}
```
> `spring-cloud-starter-sleuth`는 더 이상 필요하지 않습니다. 위 의존성을 추가하면 Spring Boot가 `RestTemplate`, `WebClient`, `@Async`, Kafka 등 주요 컴포넌트를 **자동으로 계측(instrumentation)**하여 Trace ID를 전파합니다.

**2. `application.yml` 설정**
```yaml
management:
  tracing:
    # 1. 트레이싱 활성화
    enabled: true
    # 2. 전송 방식 설정 (zipkin)
    sampling:
      # 모든 요청의 10%만 샘플링하여 추적 (운영 환경)
      # 1.0으로 설정하면 모든 요청을 추적 (개발/테스트 환경)
      probability: 0.1 
  
  zipkin:
    tracing:
      # 3. Zipkin 서버의 엔드포인트 주소
      endpoint: "http://localhost:9411/api/v2/spans"
      
logging:
  # 4. 로그에 Trace ID, Span ID가 자동으로 포함되도록 설정
  pattern:
    level: "%5p [${spring.application.name:},%X{traceId:-},%X{spanId:-}] %m%n"
```

**3. 로그(MDC) 자동 연동**
이제 애플리케이션을 실행하고 API를 호출하면, 별도 설정 없이도 모든 로그에 `traceId`와 `spanId`가 자동으로 찍힙니다.
```log
 INFO [my-service,6358c21a1f0a2e1d,6358c21a1f0a2e1d] Processing user request...
 INFO [my-service,6358c21a1f0a2e1d,7a4b3f8e0c9d2a1b] Calling external API...
```

**4. 수동 스팬 생성 (선택 사항)**
`RestTemplate` 같은 자동 계측 대상이 아닌, 복잡한 비즈니스 로직 자체를 별도의 스팬으로 추적하고 싶을 때 `Tracer`를 직접 주입받아 사용할 수 있습니다.

```java
@Service
@RequiredArgsConstructor
public class MyService {

    private final Tracer tracer; // Micrometer Tracing API

    public void myComplexBusinessLogic() {
        // "my-complex-logic"이라는 이름의 새로운 스팬 생성
        Span newSpan = this.tracer.nextSpan().name("my-complex-logic");
        
        // try-with-resources 구문으로 스팬의 시작과 종료를 관리
        try (Tracer.SpanInScope ws = this.tracer.withSpan(newSpan.start())) {
            
            // ... 복잡한 로직 수행 ...
            newSpan.tag("business.event", "step1_complete");
            // ...
            
        } catch (Exception e) {
            newSpan.error(e); // 에러 기록
            throw e;
        } finally {
            newSpan.end(); // 스팬 종료
        }
    }
}
```

---

## 💡 배운 점

1.  **Observability의 세 기둥이 연결되다**: 그동안 **Metrics**(Actuator/Micrometer)와 **Logs**(Logback)는 개별적으로만 봐왔습니다. **Tracing**은 이 두 가지를 `traceId`라는 하나의 '이야기'로 엮어주는 핵심 연결고리임을 깨달았습니다.
2.  **로그의 가치가 달라진다**: `traceId`가 없는 로그는 단순한 텍스트 줄에 불과하지만, `traceId`가 있는 로그는 Zipkin을 통해 전체 트랜잭션의 맥락 속에서 분석할 수 있는 '구조화된 데이터'가 됩니다. 이는 장애 대응 시간을 획기적으로 단축시킬 수 있습니다.
3.  **Spring Boot 3의 강력한 추상화**: 과거 Sleuth 시절보다 훨씬 표준화된(Micrometer + OTel) 방식으로 분산 추적이 이루어지는 것을 확인했습니다. 개발자는 의존성 추가와 최소한의 설정만으로도 복잡한 트레이스 전파 로직을 자동으로 적용받을 수 있어, 비즈니스 로직에 더욱 집중할 수 있습니다.

---

## 🔗 참고 자료

-   [Spring Boot Docs - Observability with Micrometer Tracing](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.observability)
-   [OpenTelemetry (OTel) - Concepts](https://opentelemetry.io/docs/concepts/)
-   [Zipkin - Official Site](https://zipkin.io/)