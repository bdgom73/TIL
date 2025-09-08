---
title: "MSA 환경에서 Spring Resilience4j로 서비스 안정성 확보하기"
date: 2025-09-08
categories: [Spring, MSA, Resilience4j]
tags: [Spring Boot, Resilience4j, Circuit Breaker, Fault Tolerance, MSA, Java 17]
excerpt: "Java 17과 Spring Boot 3 환경에서 Resilience4j를 사용하여 MSA의 장애에 효과적으로 대응하는 방법을 학습했다. 특히 Circuit Breaker 패턴을 중심으로 서비스 안정성을 높이는 데 중점을 두었다."
author_profile: true
Today I Learned: Spring Resilience4j로 MSA 안정성 확보하기
---

## 🎯 오늘의 학습 내용

### 1. MSA 환경에서 서비스 안정성의 중요성
- **MSA(Microservices Architecture)**에서는 서비스 간 의존성이 높아 하나의 서비스 장애가 연쇄적으로 영향을 미칠 위험이 큼.
- 예: API 게이트웨이 → 서비스 A(정상) → 서비스 B(장애 발생)가 연결된 경우, 서비스 B의 장애로 인해 서비스 A까지 영향을 받을 수 있음.
- 이를 방지하기 위해 **Spring Resilience4j**를 사용하여 **Circuit Breaker** 패턴을 구성, 장애 확산을 통제하고 안정성을 확보.

---

### 2. Resilience4j의 소개
- **Resilience4j**는 MSA 장애 대응을 위한 인기 있는 라이브러리로, Java 17 및 Spring Boot 3 이상의 최신 환경에서 사용하기에 적합.
- 코루틴, 람다 표현식 및 최신 자바 문법과의 호환성을 위한 설계되어 경량이고 모듈화되어 있음.
- 주요 기능:
    - **Circuit Breaker:** 장애 대응 후 요청 차단.
    - **Rate Limiter:** 요청 트래픽 제한.
    - **Retry:** 실패한 요청 재시도.
    - **Time Limiter:** 특정 시간 초과 시 요청 취소.
    - **Bulkhead:** 자원 분리 및 격리.

---

### 3. Circuit Breaker 패턴의 이해
- Circuit Breaker는 3가지 상태로 운영됨:
    1. **Closed:** 서비스가 정상 동작, 모든 요청이 전달됨.
    2. **Open:** 반복된 실패로 요청 차단. 일정 시간 동안 모든 요청 차단.
    3. **Half-Open:** 한정된 요청만 전달해 상태를 테스트. 성공 시 Closed로 복귀. 실패 시 Open 상태 유지.

---

### 4. 실습: Spring Resilience4j로 Circuit Breaker 구현

#### 4.1 Gradle 의존성 추가
Java 17과 Spring Boot 3.x 사용을 가정하여 Gradle 의존성을 추가합니다:
```gradle
dependencies {
    implementation 'io.github.resilience4j:resilience4j-spring-boot3:2.0.2' // Spring Boot 3 전용
    implementation 'io.github.resilience4j:resilience4j-micrometer:2.0.2'   // 모니터링
}
```

#### 4.2 Circuit Breaker 기본 설정
`application.yml`에 Circuit Breaker를 정의:
```yaml
resilience4j:
  circuitbreaker:
    configs:
      default:
        slidingWindowSize: 20 # 과거 20개 요청을 관찰
        failureRateThreshold: 50 # 실패율 50% 이상일 때 Open 상태로 전환
        waitDurationInOpenState: 5s # Open 상태 유지 시간
        permittedNumberOfCallsInHalfOpenState: 5 # Half-Open 시 처리할 호출 수
        minimumNumberOfCalls: 10 # 최소 요청 수 (그 이하인 경우 Circuit Breaker 발동 안 함)
    instances:
      backendA:
        baseConfig: default
```

#### 4.3 Circuit Breaker 적용
서비스 코드에서 **CircuitBreaker** 애너테이션과 람다 표현식을 활용:

```java
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.springframework.stereotype.Service;

@Service
public class BackendService {

    @CircuitBreaker(name = "backendA", fallbackMethod = "fallbackMethod")
    public String callRemoteService(String param) {
        if (Math.random() > 0.7) { // 임의의 장애 상황 (성공확률 30%)
            throw new RuntimeException("Remote Service Failure!");
        }
        return "정상 응답: " + param;
    }

    // Fallback Method - 장애 처리
    public String fallbackMethod(String param, Throwable throwable) {
        return "Fallback 응답. 현재 사용이 불가능합니다.";
    }
}
```

> Java 17의 개선된 예외 처리를 적용하여 예외 상황을 깔끔하게 처리할 수 있습니다.

#### 4.4 Controller에서 서비스 호출
Spring Boot 컨트롤러에서 Circuit Breaker가 적용된 서비스를 호출:
```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class BackendController {

    private final BackendService backendService;

    public BackendController(BackendService backendService) {
        this.backendService = backendService;
    }

    @GetMapping("/test")
    public String testCircuitBreaker(@RequestParam String param) {
        return backendService.callRemoteService(param);
    }
}
```

---

### 5. 모니터링 통합 (Micrometer, Prometheus)
- Resilience4j에서 시행된 Circuit Breaker 상태 및 요청 성공/실패 통계를 **Micrometer**와 **Prometheus**로 확인 가능.
- `build.gradle`에 Prometheus 의존성 추가:
```gradle
implementation 'io.micrometer:micrometer-registry-prometheus'
```

- `application.yml`에 Micrometer 활성화:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: metrics, health
  metrics:
    export:
      prometheus:
        enabled: true
```
- 이후 `http://localhost:8080/actuator/metrics`을 통해 상태를 확인.

---

### 6. Nginx와의 연계
- 장기적인 장애를 Nginx에 전달하거나, Nginx에서 Circuit Breaker 역할을 분산 처리:
```nginx
location /api/ {
    proxy_pass http://backend-service;
    error_page 502 @fallback; # 장애 시 fallback
}

location @fallback {
    proxy_pass http://fallback-service;
}
```

---

### 7. 주요 학습 정리
1. **Java 17에서의 Resilience4j 사용**:
    - 최신 자바 문법(예: 람다, 예외 처리)을 활용해 간결하고 가독성 높은 코드 작성.
2. **Spring Boot와의 통합성**:
    - Spring Boot 설정 파일 및 애너테이션으로 빠르게 Circuit Breaker를 구현 가능.
3. **모니터링 도구 통합**:
    - Resilience4j와 Prometheus를 결합하여 장애 복구 및 상태 추적.
4. **MSA 안정성 확보**:
    - Resilience4j는 경량 라이브러리로, 불필요한 오버헤드 없이 MSA 환경에 적합.

---

### 8. 추가 학습 과제
- **Spring Cloud Gateway에서 Resilience4j 적용법** 탐구.
- 다양한 패턴(예: Bulkhead, Rate Limiter)을 통한 장애 시나리오 실험.
- Nginx 레벨에서의 Circuit Breaker와 Spring Resilience4j 성능 비교.

---

🎉 이번 학습을 통해 Java 17과 Spring Boot 3 환경에서 Resilience4j를 활용한 장애 관리 설계를 익힐 수 있었다. 실제 서비스에서 실험적 적용을 통해 더 깊이 있는 경험을 쌓을 계획이다.