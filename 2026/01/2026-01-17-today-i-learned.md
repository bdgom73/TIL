---
title: "API 신뢰성의 척도: 멱등성(Idempotency) 구현과 네트워크 타임아웃 방어 전략"
date: 2026-01-17
categories: [Backend, API, Architecture]
tags: [Idempotency, Redis, AOP, API Design, Distributed System, Payment, TIL]
excerpt: "네트워크 불안정으로 인한 클라이언트의 재시도(Retry) 요청이 중복 결제나 데이터 오염을 유발하는 문제를 해결합니다. 멱등성(Idempotency)의 개념을 이해하고, Redis와 Spring AOP를 활용하여 'Idempotency-Key' 헤더 기반의 중복 요청 방지 메커니즘을 구현하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: API 신뢰성의 척도: 멱등성(Idempotency) 구현과 네트워크 타임아웃 방어 전략

## 📚 오늘 학습한 내용

결제 승인 API를 개발하던 중, 클라이언트(앱)가 타임아웃으로 인해 응답을 못 받아 **동일한 결제 요청을 자동으로 3번 재시도**하는 상황을 목격했습니다. 서버 로직 자체는 문제가 없었으나, 재시도 요청이 모두 DB에 반영되어 **중복 결제**가 발생하는 치명적인 이슈가 있었습니다.

단순히 `INSERT` 전에 `SELECT`를 하는 것으로는 동시성 이슈를 막을 수 없기에, 오늘은 API의 안전 장치인 **멱등성(Idempotency)**을 시스템 레벨에서 보장하는 아키텍처를 설계하고 구현했습니다.

---

### 1. **멱등성(Idempotency)이란? 🔄**

수학적 정의로는 `f(f(x)) = f(x)`입니다. API 관점에서는 **"동일한 요청을 한 번 보내든, 여러 번 보내든 서버의 상태와 응답 결과가 항상 같아야 한다"**는 원칙입니다.

-   **GET, PUT, DELETE**: HTTP 스펙상 기본적으로 멱등합니다. (여러 번 삭제해도 삭제된 상태는 같음)
-   **POST (문제의 핵심)**: 기본적으로 **멱등하지 않습니다.** (여러 번 호출하면 데이터가 여러 개 생성됨)
-   **해결책**: 클라이언트가 요청 시 유니크한 키(`Idempotency-Key`)를 헤더에 담아 보내고, 서버는 이 키를 기준으로 중복 처리를 막아야 합니다.

---

### 2. **설계: Redis를 활용한 상태 관리**

DB를 매번 조회하는 것은 성능상 좋지 않으므로, 빠른 속도와 TTL(Time To Live)을 지원하는 **Redis**를 사용합니다.

1.  **요청 수신**: 헤더에서 `Idempotency-Key` 추출.
2.  **Redis 확인**: 해당 키가 존재하는지 확인.
    -   **존재함 (처리 완료)**: 저장해둔 이전 응답(JSON)을 그대로 반환.
    -   **존재함 (처리 중)**: `409 Conflict` 또는 `429 Too Many Requests` 반환.
    -   **없음**: 키를 저장하고 비즈니스 로직 수행.
3.  **로직 수행 & 결과 저장**: 비즈니스 로직 성공 시, 응답 결과를 Redis에 업데이트.

---

### 3. **구현: Spring AOP + Redis**

비즈니스 로직을 더럽히지 않기 위해 커스텀 애노테이션과 AOP로 구현했습니다.

#### **Step 1: 애노테이션 정의**

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Idempotent {
    String headerName() default "Idempotency-Key";
    long ttl() default 60; // 키 유지 시간 (초)
}
```

#### **Step 2: AOP Aspect 구현**

핵심은 Redis의 `setIfAbsent` (SETNX) 명령어를 사용하여 **원자성(Atomicity)**을 보장하는 것입니다.

```java
@Aspect
@Component
@RequiredArgsConstructor
@Slf4j
public class IdempotencyAspect {

    private final RedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    @Around("@annotation(idempotent)")
    public Object handleIdempotency(ProceedingJoinPoint joinPoint, Idempotent idempotent) throws Throwable {
        // 1. 헤더에서 키 추출
        HttpServletRequest request = ((ServletRequestAttributes) RequestContextHolder.currentRequestAttributes()).getRequest();
        String key = request.getHeader(idempotent.headerName());

        if (!StringUtils.hasText(key)) {
            throw new IllegalArgumentException("Idempotency-Key 헤더가 누락되었습니다.");
        }

        String redisKey = "idempotency:" + key;
        
        // 2. 키 선점 시도 (Value="PROCESSING")
        // setIfAbsent: 키가 없을 때만 저장 (Atomic 연산)
        Boolean isFirstRequest = redisTemplate.opsForValue()
                .setIfAbsent(redisKey, "PROCESSING", Duration.ofSeconds(idempotent.ttl()));

        if (Boolean.FALSE.equals(isFirstRequest)) {
            // 3. 이미 키가 존재함 -> 결과 조회
            Object cachedResponse = redisTemplate.opsForValue().get(redisKey);
            
            if ("PROCESSING".equals(cachedResponse)) {
                throw new ConflictException("이전 요청이 아직 처리 중입니다.");
            }
            
            log.info("중복 요청 감지. 저장된 응답 반환. Key={}", key);
            return cachedResponse; // 이전 결과(DTO 등) 반환
        }

        // 4. 최초 요청 -> 비즈니스 로직 수행
        try {
            Object result = joinPoint.proceed();
            
            // 5. 성공 시 결과 덮어쓰기
            redisTemplate.opsForValue().set(redisKey, result, Duration.ofSeconds(idempotent.ttl()));
            return result;
        } catch (Exception e) {
            // 6. 실패 시 키 삭제 (그래야 재시도 가능)
            redisTemplate.delete(redisKey);
            throw e;
        }
    }
}
```

---

### 4. **컨트롤러 적용 예시**

```java
@RestController
@RequiredArgsConstructor
public class PaymentController {

    private final PaymentService paymentService;

    @PostMapping("/api/payments")
    @Idempotent(ttl = 60 * 60 * 24) // 24시간 동안 중복 결제 방지
    public PaymentResponse processPayment(@RequestBody PaymentRequest request) {
        // 비즈니스 로직 내부는 멱등성을 신경 쓸 필요 없음
        return paymentService.pay(request);
    }
}
```

---

### 5. **주의사항 및 고려할 점 🚧**

1.  **응답 객체의 직렬화**: Redis에 저장할 `Object result`는 반드시 직렬화(Serializable)가 가능해야 합니다. JSON String으로 변환해서 저장하고, 꺼낼 때 다시 객체로 매핑하는 과정이 필요할 수 있습니다.
2.  **TTL 설정 전략**: 멱등성 키를 영원히 들고 있을 수는 없습니다. 비즈니스 성격에 따라 24시간 혹은 1주일 정도의 만료 시간을 설정해야 Redis 메모리를 관리할 수 있습니다. (보통 결제 재시도는 수 분 내에 일어나므로 24시간이면 충분함)
3.  **Client와의 합의**: "어떤 값을 키로 쓸 것인가?"가 중요합니다. `UUID`를 매 요청마다 새로 생성하면 멱등성이 깨집니다. 클라이언트는 **"동일한 행위"에 대해서는 같은 UUID를 재사용**해서 보내줘야 합니다.

---

## 💡 배운 점

1.  **네트워크는 믿을 수 없다**: "요청을 보냈는데 응답이 안 왔다"가 "서버가 일을 안 했다"를 의미하지 않습니다. 서버는 일을 다 하고 응답을 보내는 중에 랜선이 뽑혔을 수도 있습니다. 멱등성은 이런 불확실한 분산 환경에서 데이터 정합성을 지키는 필수 패턴임을 배웠습니다.
2.  **Atomic 연산의 중요성**: 만약 `get()` 하고 `set()`을 따로 했다면, 그 찰나에 동시 요청이 들어와 둘 다 `set()`을 수행했을 겁니다. Redis의 `SETNX` 같은 원자적 연산이 동시성 제어의 핵심이었습니다.
3.  **AOP의 활용**: 멱등성 로직을 Service 계층에 섞지 않고 AOP로 분리하니, 결제뿐만 아니라 포인트 지급, 쿠폰 발급 등 다른 도메인에도 쉽게 적용할 수 있는 확장성을 얻었습니다.

---

## 🔗 참고 자료

-   [Stripe API Idempotency Guide](https://stripe.com/docs/api/idempotent_requests)
-   [Spring AOP with Redis](https://www.baeldung.com/spring-aop-annotation)
-   [Distributed Systems Patterns: Idempotency](https://microservices.io/patterns/communication-style/idempotent-consumer.html)