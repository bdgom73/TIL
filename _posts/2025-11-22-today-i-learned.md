---
title: "API 멱등성(Idempotency) 설계: 중복 결제와 데이터 오염 방지하기"
date: 2025-11-22
categories: [Architecture, API]
tags: [Idempotency, API Design, Redis, Distributed System, Payment, TIL]
excerpt: "네트워크 타임아웃이나 재시도로 인해 동일한 요청이 여러 번 서버에 도달했을 때, 데이터의 정합성을 보장하는 '멱등성(Idempotency)'의 개념을 학습합니다. Redis와 Idempotency Key를 활용하여 중복 처리를 방지하는 실무적인 구현 패턴을 알아봅니다."
author_profile: true
---

# Today I Learned: API 멱등성(Idempotency) 설계: 중복 결제와 데이터 오염 방지하기

## 📚 오늘 학습한 내용

3~4년차 개발자로서 결제나 주문 같은 중요한 로직을 다룰 때 가장 두려운 상황은 **"클라이언트는 타임아웃으로 실패했다고 생각하는데, 서버에서는 처리가 완료된 경우"**입니다. 이때 클라이언트가 (혹은 FeignClient의 Retry 설정이) 재시도를 수행하면 **중복 결제**나 **중복 주문**이라는 치명적인 데이터 오염이 발생합니다.

오늘은 이러한 분산 환경의 불확실성 속에서도 시스템의 안정성을 보장하는 핵심 원칙인 **멱등성(Idempotency)**과, 이를 Spring Boot와 Redis로 구현하는 전략을 학습했습니다.

---

### 1. **멱등성(Idempotency)이란? 🔄**

수학적 정의로는 연산을 여러 번 적용하더라도 결과가 달라지지 않는 성질($f(f(x)) = f(x)$)을 의미합니다. API 관점에서는 **"동일한 요청을 한 번 보내든, 여러 번 연속으로 보내든 서버의 상태와 응답 결과가 항상 동일해야 한다"**는 뜻입니다.

-   **멱등한 메서드**: `GET`, `PUT`, `DELETE` (여러 번 수행해도 결과 상태는 같음)
-   **멱등하지 않은 메서드**: `POST` (호출할 때마다 새로운 리소스가 생성되거나 상태가 변함 - e.g., 결제 요청)

**핵심 목표**: 멱등하지 않은 `POST` 요청(결제, 주문 등)을 **멱등하게 동작하도록** 만드는 것.

---

### 2. **해결 전략: Idempotency Key 패턴**

서버가 "이 요청은 아까 처리한 요청이야"라고 알 수 있으려면, 요청 자체에 **고유한 식별자**가 있어야 합니다.

1.  **클라이언트**: 요청을 보낼 때 헤더에 유니크한 키(`Idempotency-Key`: UUID 등)를 생성해서 담아 보냅니다. 재시도할 때는 **같은 키**를 사용합니다.
2.  **서버**:
    -   요청이 오면 `Idempotency-Key`를 확인합니다.
    -   **처음 본 키라면**: 로직을 수행하고, 결과(응답)를 키와 함께 저장소(Redis)에 저장합니다.
    -   **이미 처리된 키라면**: 로직을 수행하지 않고, 저장해둔 이전 응답 결과를 그대로 반환합니다.
    -   **처리 중인 키라면**: 다른 요청이 처리 중이므로 에러를 반환하거나 대기합니다.



---

### 3. **Spring Boot + Redis로 멱등성 구현하기**

`Filter`나 `Interceptor`를 사용하여 비즈니스 로직 침투 없이 공통 관심사로 처리하는 것이 좋습니다.

#### **1. Controller**
클라이언트는 헤더에 `Idempotency-Key`를 담아 요청합니다.

```java
@PostMapping("/orders")
public ResponseEntity<OrderResponse> createOrder(
        @RequestHeader(value = "Idempotency-Key") String idempotencyKey, 
        @RequestBody OrderRequest request) {
    // 비즈니스 로직에는 멱등성 처리 로직이 없음 (Interceptor에서 처리)
    return ResponseEntity.ok(orderService.placeOrder(request));
}
```

#### **2. Idempotency Interceptor 구현**
Redis의 `SETNX` (Set if Not Exists) 명령어를 활용하여 원자성을 보장합니다.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class IdempotencyInterceptor implements HandlerInterceptor {

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        // 1. POST 요청만 멱등성 검사
        if (!HttpMethod.POST.matches(request.getMethod())) {
            return true;
        }

        String key = request.getHeader("Idempotency-Key");
        if (key == null) {
            return true; // 키가 없으면 일반 처리 (혹은 에러 반환)
        }

        String redisKey = "idempotency:" + key;

        // 2. 키 상태 조회
        String cachedResponse = redisTemplate.opsForValue().get(redisKey);

        if (cachedResponse != null) {
            // 2-1. 이미 처리완료된 요청이면: 저장된 응답 반환 후 요청 종료
            log.info("Idempotency hit for key: {}", key);
            response.setContentType("application/json");
            response.getWriter().write(cachedResponse);
            return false; // 컨트롤러 실행 안 함
        }

        // 2-2. 처리 중(Lock) 혹은 처음 온 요청
        // SETNX로 "PROCESSING" 상태를 선점 시도 (TTL 5분)
        Boolean isFirstRequest = redisTemplate.opsForValue()
                .setIfAbsent(redisKey, "PROCESSING", Duration.ofMinutes(5));

        if (Boolean.FALSE.equals(isFirstRequest)) {
            // 이미 "PROCESSING" 상태인 경우 (동시 요청 방어)
            throw new ConflictException("이전 요청이 아직 처리 중입니다.");
        }

        // 3. 처음 온 요청이면 컨트롤러 실행 허용
        return true;
    }
}
```

#### **3. Response Caching (ResponseBodyAdvice 활용)**
컨트롤러가 성공적으로 실행된 후, 응답 값을 Redis에 업데이트해줘야 다음 요청 때 재사용할 수 있습니다. `ResponseBodyAdvice`를 사용하면 응답을 가로채서 저장할 수 있습니다.

```java
@ControllerAdvice
@RequiredArgsConstructor
public class IdempotencyResponseBodyAdvice implements ResponseBodyAdvice<Object> {

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;

    @Override
    public boolean supports(MethodParameter returnType, Class converterType) {
        return true; // POST 메서드 등 조건 추가 필요
    }

    @Override
    public Object beforeBodyWrite(Object body, MethodParameter returnType, MediaType selectedContentType,
                                  Class selectedConverterType, ServerHttpRequest request, ServerHttpResponse response) {
        
        // 요청 헤더에서 키 추출 (ServletRequestAttributes 등을 통해 접근)
        String key = getHeaderFromRequest("Idempotency-Key"); 

        if (key != null) {
            String redisKey = "idempotency:" + key;
            try {
                // "PROCESSING" 상태를 실제 응답 JSON으로 업데이트 (TTL 연장)
                String jsonResponse = objectMapper.writeValueAsString(body);
                redisTemplate.opsForValue().set(redisKey, jsonResponse, Duration.ofHours(24));
            } catch (JsonProcessingException e) {
                // 로깅 및 예외 처리 (키 삭제 등)
            }
        }
        return body;
    }
}
```

---

## 💡 배운 점

1.  **네트워크는 신뢰할 수 없다**: "요청을 보냈는데 응답이 없다"는 것이 "서버가 일을 안 했다"는 뜻이 아님을 뼈저리게 느꼈습니다. 3~4년차라면 재시도(Retry) 정책을 짤 때 반드시 멱등성 대책을 세트로 마련해야 합니다.
2.  **`Idempotency-Key`는 클라이언트의 책임이다**: 서버 혼자서는 이 요청이 재시도인지 새 요청인지 알 방법이 없습니다. 클라이언트(FE 또는 업스트림 서비스)가 UUID를 생성해서 헤더에 박아주는 **합의(Contract)**가 선행되어야 합니다.
3.  **상태 관리의 복잡성**: 단순히 DB 유니크 제약조건으로 막는 것은 한계가 있습니다. Redis를 활용해 **[처리 중 - 처리 완료 - 응답 저장]**의 라이프사이클을 관리해야만 동시성 문제와 중복 처리를 완벽하게 방어할 수 있음을 깨달았습니다.

---

## 🔗 참고 자료

-   [Stripe API - Idempotent Requests](https://stripe.com/docs/api/idempotent_requests)
-   [Toss Payments - 멱등성이 뭔가요?](https://docs.tosspayments.com/resources/glossary/idempotency)
-   [Designing Robust APIs with Idempotency](https://medium.com/@saurabh.singh0829/designing-robust-apis-with-idempotency-key-f6f223d39750)