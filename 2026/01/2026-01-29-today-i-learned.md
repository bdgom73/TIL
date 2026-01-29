---
title: "API 과부하 방어: Bucket4j와 Redis를 활용한 분산 환경 Rate Limiting 구현"
date: 2026-01-29
categories: [Spring, Network, Security]
tags: [Rate Limiting, Bucket4j, Redis, Spring Boot, Interceptor, Token Bucket, Throttling, TIL]
excerpt: "특정 클라이언트의 과도한 API 호출로 전체 시스템이 느려지는 문제를 막기 위해 애플리케이션 레벨의 처리율 제한(Rate Limiting)을 도입합니다. Token Bucket 알고리즘을 구현한 Bucket4j 라이브러리를 사용하며, 로컬 메모리가 아닌 Redis를 통해 다중 서버 환경에서도 정확한 제한을 거는 분산 처리 전략을 학습합니다."
author_profile: true
---

# Today I Learned: API 과부하 방어: Bucket4j와 Redis를 활용한 분산 환경 Rate Limiting 구현

## 📚 오늘 학습한 내용

외부 업체에 API를 오픈했는데, 특정 업체가 버그가 있는 루프 코드를 배포하여 초당 수천 건의 요청을 보내 서버 전체가 마비될 뻔한 아찔한 상황이 있었습니다. Nginx 같은 앞단에서 IP 기반으로 막을 수도 있지만, **API Key별(사용자별)로 정교하게 제한**하거나 **유료 플랜별로 등급을 나누기 위해** 애플리케이션 레벨의 Rate Limiting을 도입했습니다.

Java 진영의 표준 라이브러리인 **Bucket4j**를 사용하여, Scale-out 환경에서도 일관된 제한을 거는 방법을 정리했습니다.

---

### 1. **Token Bucket 알고리즘이란? 🪣**

Rate Limiting의 가장 대표적인 알고리즘입니다.



1.  **버킷(Bucket)**: 토큰을 담는 그릇입니다. 용량(Capacity) 제한이 있습니다.
2.  **충전(Refill)**: 일정 시간마다 토큰이 채워집니다. (예: 1초에 10개씩)
3.  **소비(Consume)**: 요청이 들어오면 토큰을 하나 꺼냅니다.
    -   토큰이 있으면 -> 요청 처리 (Pass)
    -   토큰이 없으면 -> 요청 거부 (HTTP 429 Too Many Requests)

---

### 2. **Bucket4j와 Redis (Distributed)**

단일 서버라면 로컬 메모리에 버킷을 두면 되지만, 서버가 3대라면 **총 허용량이 3배**로 늘어나는 문제가 있습니다. 따라서 모든 서버가 **Redis**를 바라보고 토큰을 차감해야 합니다.

#### **Step 1: 의존성 추가**

Redis 연동을 위해 `bucket4j-redis` 확장이 필요합니다.

```groovy
// Bucket4j Core
implementation 'com.bucket4j:bucket4j-core:8.10.1'
// Redis Extension (Lettuce 사용 시)
implementation 'com.bucket4j:bucket4j-redis:8.10.1'
```

#### **Step 2: ProxyManager 설정**

Redis를 저장소로 사용하는 `ProxyManager`를 빈으로 등록합니다.

```java
@Configuration
public class RateLimitConfig {

    @Bean
    public ProxyManager<String> lettuceProxyManager(RedisClient redisClient) {
        StatefulRedisConnection<String, byte[]> connection = redisClient.connect(RedisCodec.of(StringCodec.UTF8, ByteArrayCodec.INSTANCE));
        
        // Redis 기반의 버킷 매니저 생성
        // basedOn: 만료 정책 (시간이 지나면 Redis 키 삭제)
        return LettuceBasedProxyManager.builderFor(connection)
                .withExpirationStrategy(ExpirationAfterWriteStrategy.basedOnTimeForRefillingBucketUpToMax(Duration.ofMinutes(1)))
                .build();
    }
}
```

---

### 3. **Interceptor로 제한 적용하기**

컨트롤러마다 코드를 넣는 것은 비효율적이므로 `HandlerInterceptor`에서 처리합니다.

```java
@Component
@RequiredArgsConstructor
public class RateLimitInterceptor implements HandlerInterceptor {

    private final ProxyManager<String> proxyManager;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        // 1. 식별자 추출 (API Key 또는 IP 주소)
        String apiKey = request.getHeader("X-API-KEY");
        if (apiKey == null) {
            apiKey = request.getRemoteAddr(); // 비회원이면 IP 기준
        }

        // 2. 버킷 설정 (플랜별로 다르게 적용 가능)
        // 예: 분당 60회 허용 (Capacity 60, Refill 60/1min)
        BucketConfiguration configuration = BucketConfiguration.builder()
                .addLimit(Bandwidth.builder()
                        .capacity(60)
                        .refillIntervally(60, Duration.ofMinutes(1))
                        .build())
                .build();

        // 3. Redis에서 버킷 조회 (없으면 생성)
        Bucket bucket = proxyManager.builder().build(apiKey, configuration);

        // 4. 토큰 소비 시도
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        if (probe.isConsumed()) {
            // 성공 시 남은 토큰 정보를 헤더에 알려줌 (친절한 API)
            response.addHeader("X-RateLimit-Remaining", String.valueOf(probe.getRemainingTokens()));
            return true;
        } else {
            // 실패 시 429 에러 반환
            long waitForRefill = probe.getNanosToWaitForRefill() / 1_000_000_000;
            response.addHeader("X-RateLimit-Retry-After-Seconds", String.valueOf(waitForRefill));
            response.sendError(HttpStatus.TOO_MANY_REQUESTS.value(), "Too many requests");
            return false;
        }
    }
}
```

---

### 4. **심화: Greedy Refill vs Interval Refill**

Bucket4j 설정을 할 때 리필 전략을 잘 골라야 합니다.

* **`refillGreedy(10, Duration.ofSeconds(1))`**: 0.1초마다 토큰 1개씩 꼬박꼬박 채워줍니다. 트래픽이 부드럽게 처리됩니다. (권장)
* **`refillIntervally(10, Duration.ofSeconds(1))`**: 0초에 10개를 주고, 0.99초까지 아무것도 안 주다가, 1.0초에 다시 10개를 줍니다. 순간적으로 트래픽이 튀는(Burst) 현상을 허용할 때 씁니다.

---

## 💡 배운 점

1.  **DDoS 방어 그 이상**: Rate Limiting은 단순히 공격 방어뿐만 아니라, **SaaS 서비스의 과금 모델(Tier)**을 구현하는 핵심 기술임을 알았습니다. Free 유저는 초당 5회, Pro 유저는 초당 100회 같은 로직을 여기서 태울 수 있습니다.
2.  **Redis 성능 고려**: 모든 요청마다 Redis를 조회하고 갱신(Atomic 연산)해야 하므로 Redis 부하가 늘어납니다. 하지만 Bucket4j는 내부적으로 최적화된 Lua Script를 사용하므로, 단순 Get/Set 보다는 훨씬 효율적이라는 것을 확인했습니다.
3.  **사용자 경험(UX)**: 무작정 에러를 뱉는 것보다, `Retry-After` 헤더를 통해 "언제 다시 요청하면 되는지" 알려주는 것이 클라이언트 개발자를 위한 배려이자 표준 스펙(RFC 6585)임을 배웠습니다.

---

## 🔗 참고 자료

-   [Bucket4j Official Documentation](https://bucket4j.com/)
-   [Spring Boot Rate Limiting with Bucket4j](https://www.baeldung.com/spring-bucket4j)
-   [Redis Pattern: Rate Limiter](https://redis.io/commands/incr/#pattern-rate-limiter-1)