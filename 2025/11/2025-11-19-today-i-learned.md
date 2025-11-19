---
title: "Bucket4j와 Redis를 활용한 분산 환경 API Rate Limiting 구현"
date: 2025-11-19
categories: [Spring, Architecture]
tags: [Rate Limiting, Bucket4j, Redis, Token Bucket, API Security, Throttling, TIL]
excerpt: "특정 클라이언트의 과도한 트래픽으로부터 서버를 보호하기 위한 API Rate Limiting 기법을 학습합니다. 토큰 버킷(Token Bucket) 알고리즘의 원리를 이해하고, Bucket4j와 Redis를 연동하여 분산 환경에서도 동작하는 처리율 제한 장치를 구현해봅니다."
author_profile: true
---

# Today I Learned: Bucket4j와 Redis를 활용한 분산 환경 API Rate Limiting 구현

## 📚 오늘 학습한 내용

API 서버를 운영하다 보면 특정 IP나 사용자로부터 비정상적으로 많은 요청이 들어와 전체 시스템의 성능을 저하시키거나, 외부 API(SMS 발송 등) 비용을 급증시키는 문제가 발생할 수 있습니다. 이를 방지하기 위해 **처리율 제한(Rate Limiting)** 장치를 도입해야 합니다.

단일 서버라면 Guava RateLimiter 등으로 간단히 해결되지만, 오토스케일링되는 **분산 환경(MSA)**에서는 여러 서버가 요청 횟수를 공유해야 하므로 **Redis**와 같은 중앙 저장소가 필수적입니다. 오늘은 Java 진영의 표준적인 처리율 제한 라이브러리인 **Bucket4j**와 **Redis**를 결합하여 이를 구현하는 방법을 학습했습니다.

---

### 1. **토큰 버킷(Token Bucket) 알고리즘 🪣**

Rate Limiting에는 Leaky Bucket, Fixed Window 등 여러 알고리즘이 있지만, Bucket4j는 **토큰 버킷** 알고리즘을 사용합니다.



-   **원리**:
    1.  버킷에 **토큰**이 정해진 속도(Refill Rate)로 채워집니다. (e.g., 1초에 10개)
    2.  버킷에는 담을 수 있는 **최대 토큰 수(Capacity)**가 정해져 있습니다.
    3.  요청이 들어오면 버킷에서 토큰을 하나 가져갑니다(**Consume**).
    4.  토큰이 있으면 요청을 처리하고, 토큰이 없으면 요청을 거부(Reject)합니다.
-   **장점**: 짧은 시간 동안의 **버스트 트래픽(Burst Traffic)**을 허용하면서도 전체적인 처리율을 제어할 수 있어, 사용자 경험 측면에서 유리합니다.

---

### 2. **Spring Boot + Bucket4j + Redis 구현**

분산 환경에서 Rate Limiting을 적용하기 위해 Redis를 백엔드로 사용하는 Bucket4j 설정을 진행했습니다.

#### **1. 의존성 추가 (`build.gradle`)**
`bucket4j-core`와 Redis 연동을 위한 `bucket4j-redis`가 필요합니다. (Redisson 클라이언트 사용 가정)

```groovy
implementation 'com.bucket4j:bucket4j-core:8.10.1'
implementation 'com.bucket4j:bucket4j-redis:8.10.1'
implementation 'org.redisson:redisson-spring-boot-starter:3.27.0'
```

#### **2. RateLimitService 구현**
Redisson을 기반으로 Bucket4j의 `ProxyManager`를 설정하고, 버킷을 생성/조회하는 로직입니다.

```java
@Service
@RequiredArgsConstructor
public class RateLimitService {

    private final RedissonClient redissonClient;
    private ProxyManager<String> proxyManager;

    @PostConstruct
    public void init() {
        // Redis 기반의 ProxyManager 생성
        this.proxyManager = Bucket4jRedis.builder()
                .withKeyExpirationStrategy(ExpirationAfterWriteStrategy.basedOnTimeForRefillingBucketUpToMax(Duration.ofSeconds(10)))
                .build(redissonClient.getMap("rate-limit-buckets", StringCodec.INSTANCE));
    }

    /**
     * 클라이언트 키(IP, UserId)를 기반으로 버킷을 가져오거나 생성
     */
    public Bucket resolveBucket(String key) {
        return proxyManager.builder().build(key, this::getConfig);
    }

    /**
     * 버킷 정책 설정: 분당 60회 요청 허용 (1초에 1개씩 충전)
     */
    private BucketConfiguration getConfig() {
        return BucketConfiguration.builder()
                .addLimit(Bandwidth.classic(60, Refill.intervally(60, Duration.ofMinutes(1))))
                .build();
    }
}
```

#### **3. Interceptor 적용**
API 요청이 컨트롤러에 도달하기 전에 `HandlerInterceptor`에서 처리율을 검사합니다.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class RateLimitInterceptor implements HandlerInterceptor {

    private final RateLimitService rateLimitService;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // 1. 식별자 추출 (API Key, User ID, IP Address 등)
        String apiKey = request.getHeader("X-API-KEY");
        if (apiKey == null || apiKey.isBlank()) {
            apiKey = request.getRemoteAddr(); // 비회원은 IP 기준
        }

        // 2. 해당 식별자의 버킷 조회
        Bucket bucket = rateLimitService.resolveBucket(apiKey);

        // 3. 토큰 소비 시도 (1개 소비)
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        if (probe.isConsumed()) {
            // 성공 시 남은 토큰 수를 헤더에 알려줌 (친절한 API)
            response.addHeader("X-RateLimit-Remaining", String.valueOf(probe.getRemainingTokens()));
            return true;
        } else {
            // 4. 실패 시 429 Too Many Requests 반환
            long waitForRefill = probe.getNanosToWaitForRefill() / 1_000_000_000;
            log.warn("Rate limit exceeded for key: {}. Try again in {} seconds", apiKey, waitForRefill);
            
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value()); // 429
            response.addHeader("X-RateLimit-Retry-After-Seconds", String.valueOf(waitForRefill));
            return false;
        }
    }
}
```

---

### 3. **HTTP 429와 Retry-After 헤더**

Rate Limiting을 구현할 때 단순히 에러를 뱉는 것보다, 클라이언트가 **"언제 다시 요청할 수 있는지"** 알려주는 것이 표준입니다.

-   **HTTP Status**: `429 Too Many Requests`가 표준입니다.
-   **Response Header**:
    -   `X-RateLimit-Limit`: 허용된 요청 한도
    -   `X-RateLimit-Remaining`: 남은 요청 수
    -   `Retry-After`: (초 단위) 이 시간 이후에 다시 요청하시오.

Bucket4j의 `tryConsumeAndReturnRemaining` 메서드는 남은 토큰 수와, 실패 시 토큰이 채워지기까지 남은 시간(`getNanosToWaitForRefill`)을 반환해주므로, 이 헤더들을 손쉽게 구성할 수 있습니다.

---

## 💡 배운 점

1.  **분산 환경의 상태 관리**: 로컬 메모리에 버킷을 저장하면, 로드 밸런서 뒤의 서버 A에서는 차단되었지만 서버 B에서는 요청이 허용되는 문제가 발생합니다. Redis를 통해 **버킷의 상태(남은 토큰 수)를 공유**함으로써 시스템 전체의 일관된 처리율 제한이 가능함을 확인했습니다.
2.  **Throttling은 인프라 보호의 핵심**: 단순히 악의적인 공격 방어뿐만 아니라, 이벤트 오픈 등 트래픽이 폭주하는 상황에서 DB나 다운스트림 서비스가 터지지 않도록 보호하는 **안전장치(Backpressure)** 역할을 수행한다는 점을 깨달았습니다.
3.  **유연한 정책 적용**: Bucket4j는 단순 횟수 제한뿐만 아니라, `Greedy`(즉시 충전) vs `Intervally`(구간별 충전) 전략을 선택할 수 있고, 사용자의 등급(Basic/Premium)에 따라 버킷 용량을 다르게 설정하는 등 비즈니스 로직에 맞춘 유연한 설계가 가능합니다.

---

## 🔗 참고 자료

-   [Bucket4j Official Documentation](https://bucket4j.com/)
-   [Spring Boot Rate Limiting with Bucket4j (Baeldung)](https://www.baeldung.com/spring-bucket4j)
-   [Redis Pattern: Rate Limiter](https://redis.io/commands/incr/#pattern-rate-limiter)