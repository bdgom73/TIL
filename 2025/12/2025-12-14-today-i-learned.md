---
title: "Resilience4j Circuit Breaker: 외부 시스템 장애로부터 내 서비스 보호하기"
date: 2025-12-14
categories: [Spring, MSA, Resilience]
tags: [Resilience4j, Circuit Breaker, Fault Tolerance, Spring Boot, Fallback, MSA, TIL]
excerpt: "MSA 환경에서 외부 서비스 장애가 전체 시스템의 장애로 번지는 '장애 전파(Cascading Failure)'를 막기 위한 서킷 브레이커 패턴을 학습합니다. Resilience4j를 사용하여 실패율 기반으로 회로를 차단하고, Fallback 메서드를 통해 우아하게 대처하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Resilience4j Circuit Breaker: 외부 시스템 장애로부터 내 서비스 보호하기

## 📚 오늘 학습한 내용

마이크로서비스 아키텍처(MSA)를 운영하다 보면, **"결제 서비스가 느려졌는데, 그 여파로 주문 서비스의 스레드 풀이 고갈되어 전체 서버가 멈추는"** 끔찍한 연쇄 장애(Cascading Failure)를 겪을 수 있습니다.

타임아웃 설정만으로는 부족한 이 상황을 해결하기 위해, 전기 회로 차단기에서 아이디어를 얻은 **서킷 브레이커(Circuit Breaker)** 패턴과 이를 구현한 라이브러리인 **Resilience4j**의 적용법을 학습했습니다.

---

### 1. **서킷 브레이커의 3가지 상태 🚦**

서킷 브레이커는 상태 기계(State Machine)처럼 동작하며, 외부 호출의 성공/실패 여부에 따라 상태가 변합니다.



1.  **CLOSED (정상)**: 평소 상태입니다. 요청을 외부 서비스로 정상적으로 보냅니다. 실패율이 임계치를 넘으면 `OPEN` 됩니다.
2.  **OPEN (차단)**: 장애 상태입니다. **요청을 아예 보내지 않고 즉시 에러(또는 Fallback)를 반환**합니다. (Fail Fast). 일정 시간이 지나면 `HALF_OPEN` 상태로 바뀝니다.
3.  **HALF_OPEN (반 열림)**: 간보기 상태입니다. 제한된 수의 요청만 살짝 보내봅니다. 성공하면 `CLOSED`로 돌아가고, 또 실패하면 다시 `OPEN` 됩니다.

---

### 2. **Spring Boot에 적용하기**

과거의 Hystrix(Netflix)는 유지보수 모드에 들어갔으므로, 함수형 프로그래밍을 지원하고 가벼운 **Resilience4j**가 표준입니다.

#### **Step 1: 의존성 추가**
AOP 기반으로 동작하므로 `spring-boot-starter-aop`가 필요합니다.

```groovy
implementation 'org.springframework.cloud:spring-cloud-starter-circuitbreaker-resilience4j'
implementation 'org.springframework.boot:spring-boot-starter-aop'
```

#### **Step 2: `application.yml` 설정**
서킷을 언제 열고, 언제 다시 닫을지 규칙을 정합니다.

```yaml
resilience4j:
  circuitbreaker:
    instances:
      paymentService: # 서킷 브레이커 이름
        baseConfig: default
        registerHealthIndicator: true # Actuator 헬스 체크에 포함
        slidingWindowType: COUNT_BASED # 횟수 기반 (또는 TIME_BASED)
        slidingWindowSize: 10 # 최근 10개 요청을 기준으로 판단
        minimumNumberOfCalls: 5 # 최소 5번은 호출해야 계산 시작
        failureRateThreshold: 50 # 실패율 50% 넘으면 OPEN (10개 중 5개 실패 시)
        waitDurationInOpenState: 10s # OPEN 상태에서 10초 대기 후 HALF_OPEN 전환
        permittedNumberOfCallsInHalfOpenState: 3 # HALF_OPEN 상태에서 3번 테스트 허용
```

#### **Step 3: `@CircuitBreaker` 적용 및 Fallback**

외부 API를 호출하는 서비스 메서드에 애노테이션을 붙입니다.

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService {

    private final PaymentClient paymentClient; // FeignClient or RestTemplate

    @CircuitBreaker(name = "paymentService", fallbackMethod = "fallbackPayment")
    public String processPayment(String orderId) {
        // 외부 결제 서비스 호출 (장애 발생 가능성 있음)
        return paymentClient.pay(orderId);
    }

    // Fallback 메서드: 서킷이 OPEN 되거나 예외 발생 시 실행됨
    // 주의: 원본 메서드와 파라미터가 같아야 하고, 마지막에 Exception을 받아야 함
    public String fallbackPayment(String orderId, Throwable t) {
        log.error("Payment Service failed for order: {}. Error: {}", orderId, t.getMessage());
        
        // 1. 기본값 반환
        // return "PAYMENT_PENDING"; 
        
        // 2. 또는 캐시된 데이터 반환, 아니면 커스텀 예외 던지기
        throw new ServiceUnavailableException("결제 서비스가 일시적으로 불가능합니다. 잠시 후 시도해주세요.");
    }
}
```

---

### 3. **RecordFailurePredicate: 어떤 에러를 실패로 볼 것인가?**

모든 예외가 서킷을 열어야 하는 '장애'는 아닙니다. 예를 들어 "잔액 부족(400 Bad Request)"은 비즈니스 예외이지 시스템 장애가 아니므로 서킷을 열면 안 됩니다.

```yaml
resilience4j:
  circuitbreaker:
    configs:
      default:
        # 특정 예외는 실패율 집계에서 제외 (서킷 오픈에 영향 안 줌)
        ignoreExceptions:
          - com.example.exception.BusinessException 
        # 특정 예외만 실패로 간주
        recordExceptions:
          - java.util.concurrent.TimeoutException
          - org.springframework.web.client.HttpServerErrorException
```

---

## 💡 배운 점

1.  **Fail Fast의 미학**: 장애가 난 서버에 계속 요청을 보내 응답을 기다리는(Blocking) 것은 자원 낭비입니다. 서킷 브레이커가 "지금은 안 돼"라고 즉시 거절해줌으로써 내 서버의 스레드를 보호하고 전체 시스템의 회복 탄력성(Resilience)을 높일 수 있음을 깨달았습니다.
2.  **Fallback은 신중하게**: Fallback 메서드에서 또 다른 네트워크 호출을 하거나 무거운 로직을 수행하면, Fallback 자체가 장애 지점이 될 수 있습니다. Fallback은 최대한 가볍고 안전하게(기본값 반환, 로깅 등) 작성해야 합니다.
3.  **Actuator와의 궁합**: `registerHealthIndicator: true` 설정을 통해 Prometheus나 Grafana에서 서킷의 상태(OPEN/CLOSED)를 실시간으로 모니터링할 수 있다는 점이 운영 관점에서 매우 유용했습니다.

---

## 🔗 참고 자료

-   [Resilience4j Official Documentation](https://resilience4j.readme.io/docs/circuitbreaker)
-   [Spring Boot Circuit Breaker Guide](https://spring.io/guides/gs/circuit-breaker/)
-   [Netflix TechBlog: Fault Tolerance in a High Volume, Distributed System](https://netflixtechblog.com/fault-tolerance-in-a-high-volume-distributed-system-91ab4faae74a)