---
title: "MSA 핵심 패턴: API Gateway, 서킷 브레이커, 분산 트랜잭션"
date: 2025-09-20
categories: [Spring Cloud, MSA]
tags: [API Gateway, Resilience4j, Circuit Breaker, Saga, 2PC, MSA, TIL]
excerpt: "마이크로서비스 아키텍처(MSA)의 핵심 요소인 API Gateway를 이용한 인증/인가, Resilience4j를 활용한 서킷 브레이커, 그리고 분산 트랜잭션 처리 패턴(Saga, 2PC)에 대해 학습합니다."
author_profile: true
---

# Today I Learned: MSA 핵심 패턴: API Gateway, 서킷 브레이커, 분산 트랜잭션

## 📚 오늘 학습한 내용

마이크로서비스 아키텍처(MSA)는 독립적으로 배포하고 확장할 수 있는 작은 서비스들의 모음입니다. 이러한 분산 환경에서는 서비스 간의 상호작용을 안정적으로 관리하는 것이 매우 중요합니다. 오늘은 MSA의 안정성과 확장성을 보장하는 세 가지 핵심 패턴에 대해 학습했습니다.

---

### 1. **Spring Cloud Gateway와 Filter를 이용한 API 인증/인가 처리**

마이크로서비스 환경에서 각 서비스가 개별적으로 인증/인가 로직을 갖는 것은 비효율적이고 관리 포인트를 늘립니다. **API Gateway**는 시스템의 단일 진입점(Single Point of Entry) 역할을 하며, 이러한 공통 기능을 중앙에서 처리합니다.

-   **역할**: API Gateway는 클라이언트의 모든 요청을 받아 적절한 마이크로서비스로 라우팅합니다. 이 과정에서 인증/인가, 로깅, 로드 밸런싱과 같은 **횡단 관심사(Cross-Cutting Concerns)**를 처리합니다.
-   **구현**: Spring Cloud Gateway에서는 `GlobalFilter`를 구현하여 모든 요청에 대해 특정 로직을 적용할 수 있습니다. 예를 들어, 요청 헤더에 있는 JWT(JSON Web Token)를 검증하여 유효하지 않은 토큰을 가진 요청을 차단할 수 있습니다.

```java
@Component
public class AuthenticationFilter implements GlobalFilter {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();

        // "/api/auth/**" 경로는 필터 예외 처리
        if (request.getURI().getPath().contains("/api/auth")) {
            return chain.filter(exchange);
        }

        // Authorization 헤더 존재 여부 확인
        if (!request.getHeaders().containsKey(HttpHeaders.AUTHORIZATION)) {
            return onError(exchange, "No authorization header", HttpStatus.UNAUTHORIZED);
        }

        // JWT 토큰 유효성 검증 로직 (생략)
        String token = request.getHeaders().get(HttpHeaders.AUTHORIZATION).get(0).replace("Bearer ", "");
        if (!isJwtValid(token)) {
            return onError(exchange, "Invalid token", HttpStatus.UNAUTHORIZED);
        }

        return chain.filter(exchange);
    }

    private Mono<Void> onError(ServerWebExchange exchange, String err, HttpStatus httpStatus) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(httpStatus);
        // ... 에러 응답 처리
        return response.setComplete();
    }

    private boolean isJwtValid(String token) {
        // 실제 토큰 검증 로직 구현
        return true;
    }
}
```

> **핵심**: 인증/인가 로직을 Gateway에 위임함으로써 각 마이크로서비스는 비즈니스 로직에만 집중할 수 있게 되어 **관심사의 분리(Separation of Concerns)** 원칙을 지킬 수 있습니다.

---

### 2. **Resilience4j를 이용한 서킷 브레이커 패턴 구현 및 장애 복구 전략**

MSA 환경에서는 하나의 서비스 장애가 다른 서비스로 전파되는 **연쇄 장애(Cascading Failures)**가 발생할 수 있습니다. **서킷 브레이커(Circuit Breaker)** 패턴은 이러한 문제를 방지하기 위한 핵심적인 장애 복구 전략입니다.

-   **개념**: 전기 회로의 차단기처럼, 특정 서비스에 대한 호출이 계속 실패하면 일시적으로 해당 서비스로의 요청을 차단하여 시스템 전체의 안정성을 확보합니다.
-   **상태**:
    -   `CLOSED`: 정상 상태. 요청을 그대로 전달합니다.
    -   `OPEN`: 장애 발생 상태. 설정된 시간 동안 요청을 즉시 실패시키고, 장애가 발생한 서비스가 복구될 시간을 줍니다.
    -   `HALF_OPEN`: `OPEN` 상태에서 일정 시간이 지나면 일부 테스트 요청을 보내 서비스의 복구 여부를 확인합니다.
-   **구현**: Netflix Hystrix의 개발 중단 이후, **Resilience4j**가 널리 사용됩니다. `@CircuitBreaker` 어노테이션과 `fallbackMethod`를 통해 쉽게 구현할 수 있습니다.

```java
@Service
public class OrderService {

    private final RestTemplate restTemplate;

    // application.yml에 정의된 서킷 브레이커 'productService'를 사용
    @CircuitBreaker(name = "productService", fallbackMethod = "getProductFallback")
    public String getProductDetails(String productId) {
        // 상품 서비스 API 호출
        return restTemplate.getForObject("http://product-service/api/products/" + productId, String.class);
    }

    // fallback 메서드는 원본 메서드와 동일한 시그니처를 가져야 함
    public String getProductFallback(String productId, Throwable t) {
        // 상품 서비스 장애 시 기본 응답 또는 캐시된 데이터 반환
        return "Fallback: Product information is currently unavailable.";
    }
}
```

> **핵심**: 서킷 브레이커를 통해 장애가 전파되는 것을 막고, `Fallback` 로직을 통해 서비스의 **회복탄력성(Resilience)**을 높일 수 있습니다.

---

### 3. **분산 트랜잭션의 이해: Saga 패턴 vs. Two-Phase Commit (2PC)**

하나의 비즈니스 로직이 여러 마이크로서비스에 걸쳐 실행될 때, 데이터의 일관성을 유지하는 것은 매우 어렵습니다. 이를 **분산 트랜잭션**이라고 하며, 대표적인 해결책으로 2PC와 Saga 패턴이 있습니다.

#### **Two-Phase Commit (2PC)**

-   **동작 방식**: 트랜잭션 코디네이터(Coordinator)가 모든 참여자(Participant)에게 **1단계: 준비(Prepare)** 요청을 보내고, 모두가 동의하면 **2단계: 커밋(Commit)**을 실행합니다. 하나라도 실패하면 모두 롤백합니다.
-   **장점**: **강력한 데이터 일관성(Strong Consistency)**을 보장합니다.
-   **단점**: 모든 참여자가 응답할 때까지 **블로킹(Blocking)**되어 성능이 저하되고, 코디네이터에 장애가 발생하면 전체 시스템이 멈출 수 있어 MSA 환경에는 적합하지 않은 경우가 많습니다.

#### **Saga 패턴**

-   **동작 방식**: 하나의 큰 트랜잭션을 여러 개의 작은 **로컬 트랜잭션**의 시퀀스로 나눕니다. 각 로컬 트랜잭션이 성공하면 다음 트랜잭션을 호출하는 이벤트를 발행합니다. 만약 중간에 실패하면, 이전 트랜잭션들이 실행했던 작업을 취소하는 **보상 트랜잭션(Compensating Transaction)**을 실행합니다.
-   **장점**: 각 서비스가 독립적으로 동작하여 **결합도가 낮고(Loose Coupling)**, 블로킹이 없어 성능 및 확장성이 뛰어납니다.
-   **단점**: 모든 트랜잭션이 완료되기 전까지 데이터가 일시적으로 불일치하는 **최종 일관성(Eventual Consistency)**을 가집니다. 또한 보상 트랜잭션을 모두 구현해야 하므로 복잡성이 증가합니다.

| 구분 | **Two-Phase Commit (2PC)** | **Saga Pattern** |
| :--- | :--- | :--- |
| **일관성** | 강력한 일관성 (Strong Consistency) | 최종 일관성 (Eventual Consistency) |
| **결합도** | 높음 (Tight Coupling) | 낮음 (Loose Coupling) |
| **프로토콜** | 동기 (Synchronous, Blocking) | 비동기 (Asynchronous, Non-Blocking) |
| **복잡성** | 구현은 단순하나, 코디네이터 의존성 높음 | 보상 트랜잭션 구현으로 로직이 복잡함 |
| **주요 사용처** | 전통적인 모놀리식, 데이터 일관성이 극도로 중요할 때 | 마이크로서비스 아키텍처, 확장성과 가용성이 중요할 때 |

---

## 💡 배운 점

1.  **API Gateway**는 MSA의 얼굴과 같습니다. 인증/인가와 같은 공통 로직을 중앙에서 처리하여 각 서비스의 복잡도를 낮추고 개발 생산성을 높입니다.
2.  **서킷 브레이커**는 장애가 시스템 전체로 퍼지는 것을 막는 필수적인 안전장치입니다. Resilience4j를 사용하면 선언적으로 장애 복구 전략을 구현하여 안정적인 시스템을 만들 수 있습니다.
3.  MSA 환경에서 분산 트랜잭션은 피할 수 없는 과제입니다. 2PC는 강력한 일관성을 제공하지만 성능과 확장성에 한계가 있어, **Saga 패턴**이 현대적인 MSA에 더 적합한 해결책이라는 점을 이해했습니다.

---

## 🔗 참고 자료

-   [Spring Cloud Gateway 공식 문서](https://spring.io/projects/spring-cloud-gateway)
-   [Resilience4j 가이드](https://resilience4j.readme.io/docs)
-   [Martin Fowler - Saga Pattern](https://martinfowler.com/eaaDev/Saga.html)