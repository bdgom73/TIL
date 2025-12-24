---
title: "API Rate Limiting: Bucket4j와 Redis로 트래픽 과부하 방지하기"
date: 2025-12-24
categories: [Backend, Security, Architecture]
tags: [Rate Limiting, Bucket4j, Redis, API Gateway, Throttling, Traffic Control, TIL]
excerpt: "특정 클라이언트의 과도한 API 호출로 인한 서버 장애를 막기 위해 처리율 제한(Rate Limiting) 장치를 도입합니다. 토큰 버킷 알고리즘을 구현한 Bucket4j 라이브러리와 Redis를 연동하여 분산 환경에서도 정확하게 요청 수를 제한하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: API Rate Limiting: Bucket4j와 Redis로 트래픽 과부하 방지하기

## 📚 오늘 학습한 내용

외부에 오픈된 API를 개발하다 보면, 특정 IP에서 디도스(DDoS) 성 공격이 들어오거나, 클라이언트의 버그로 인해 무한 루프 요청이 들어와 전체 서버가 마비되는 상황을 겪을 수 있습니다. Nginx 같은 웹 서버 단에서 제어할 수도 있지만, 비즈니스 로직(사용자 ID, API Key 등)에 따라 세밀하게 제어하기 위해서는 애플리케이션 레벨의 **Rate Limiting**이 필수적입니다.

오늘은 자바 진영의 대표적인 처리율 제한 라이브러리인 **Bucket4j**를 활용하여, **토큰 버킷(Token Bucket)** 알고리즘 기반의 트래픽 제어 로직을 구현했습니다. 특히 서버가 여러 대인 분산 환경을 고려하여 **Redis**를 백엔드로 사용했습니다.

---

### 1. **토큰 버킷(Token Bucket) 알고리즘이란? 🪣**

Rate Limiting에는 Leaky Bucket, Fixed Window 등 여러 알고리즘이 있지만, Bucket4j는 토큰 버킷을 사용합니다.

1.  **버킷 생성**: 각 사용자(Key)마다 버킷을 하나씩 할당합니다.
2.  **토큰 충전**: 버킷에는 일정 속도로 토큰이 자동으로 채워집니다. (예: 1초에 10개)
3.  **토큰 소비**: API 요청이 들어올 때마다 토큰을 하나 꺼냅니다.
4.  **제한**: 버킷에 남은 토큰이 없으면 요청을 거부(Reject)하고 `429 Too Many Requests`를 반환합니다.

---

### 2. **Spring Boot + Bucket4j + Redis 구현**

#### **Step 1: 의존성 추가**
분산 환경 지원을 위해 `bucket4j-redis` 모듈이 필요합니다.

```groovy
implementation 'com.giffing.bucket4j.spring.boot.starter:bucket4j-spring-boot-starter:0.10.3' // Starter 사용 시 간편함
// 혹은 커스텀 구현을 위해 Core 라이브러리 사용
implementation 'io.github.bucket4j:bucket4j-core:8.10.1'
implementation 'io.github.bucket4j:bucket4j-redis:8.10.1'
```

#### **Step 2: Redis 설정 및 ProxyManager 생성**
Redis를 저장소로 사용하는 `ProxyManager`를 빈으로 등록합니다. 이것이 토큰의 잔여량을 Redis에 저장하고 원자적(Atomic)으로 차감하는 역할을 합니다.

```java
@Configuration
public class RateLimitConfig {

    @Bean
    public ProxyManager<String> lettuceProxyManager(RedisClient redisClient) { // Lettuce Client 사용 가정
        StatefulRedisConnection<String, byte[]> connection = redisClient.connect(RedisCodec.of(StringCodec.UTF8, ByteArrayCodec.INSTANCE));
        
        return LettuceBasedProxyManager.builderFor(connection)
                .withExpirationStrategy(ExpirationAfterWriteStrategy.basedOnTimeForRefillingBucketUpToMax(Duration.ofSeconds(10)))
                .build();
    }
}
```

#### **Step 3: RateLimitService 구현**
사용자별로 버킷을 생성하고 토큰을 차감하는 로직입니다.

```java
@Service
@RequiredArgsConstructor
public class RateLimitService {

    private final ProxyManager<String> proxyManager;

    public Bucket resolveBucket(String apiKey) {
        return proxyManager.builder().build(apiKey, this::pricingPlan);
    }

    // 버킷 정책 정의 (Plan)
    private BucketConfiguration pricingPlan() {
        // 1분당 100개의 요청 허용 (Capacity: 100, Refill: 100 tokens per 1 minute)
        Refill refill = Refill.intervally(100, Duration.ofMinutes(1));
        Bandwidth limit = Bandwidth.classic(100, refill);
        
        return BucketConfiguration.builder()
                .addLimit(limit)
                .build();
    }
}
```

#### **Step 4: Interceptor 적용**
컨트롤러 앞단에서 요청을 가로채 토큰을 검사합니다.

```java
@Component
@RequiredArgsConstructor
public class RateLimitInterceptor implements HandlerInterceptor {

    private final RateLimitService rateLimitService;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        String apiKey = request.getHeader("X-API-KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            return true; // 공용 API는 패스하거나 별도 정책 적용
        }

        Bucket bucket = rateLimitService.resolveBucket(apiKey);
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        if (probe.isConsumed()) {
            // 정상 처리: 남은 토큰 수를 헤더에 알려주면 친절한 API가 됨
            response.addHeader("X-RateLimit-Remaining", String.valueOf(probe.getRemainingTokens()));
            return true;
        } else {
            // 제한 초과: 429 에러 반환
            long waitForRefill = probe.getNanosToWaitForRefill() / 1_000_000_000;
            response.addHeader("X-RateLimit-Retry-After-Seconds", String.valueOf(waitForRefill));
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            return false;
        }
    }
}
```

---

### 3. **심화: IP 기반 vs User 기반 전략**

-   **IP 기반**: 로그인하지 않은 사용자 제어에 유용하지만, NAT 환경(공유기, 회사망)에서는 여러 사용자가 하나의 IP를 공유하므로 억울한 차단이 발생할 수 있습니다.
-   **User ID / API Key 기반**: 가장 정확하지만, 로그인 전 단계(회원가입, 로그인 시도 등)의 공격은 막을 수 없습니다.
-   **하이브리드 전략**:
    -   로그인 전: IP 기반으로 빡빡하게 제한 (1분당 5회).
    -   로그인 후: User ID 기반으로 넉넉하게 제한 (1분당 100회).
    -   이렇게 이중으로 방어막을 치는 것이 실무적인 Best Practice입니다.

---

## 💡 배운 점

1.  **비즈니스 연속성 보장**: Rate Limiting은 단순히 공격을 막는 보안 도구가 아니라, 일부 헤비 유저가 리소스를 독점하여 다른 일반 유저들이 피해를 보는 **'이웃 소음(Noisy Neighbor)'** 문제를 해결하는 핵심 품질 관리 도구임을 깨달았습니다.
2.  **분산 환경의 동시성**: Redis 없이 로컬 메모리(HashMap)로 Rate Limiter를 만들면, 서버가 3대일 때 총 3배의 트래픽을 허용하게 되는 문제가 있습니다. `Bucket4j-Redis`를 사용하면 여러 서버가 하나의 Redis 카운터를 공유하므로 정확한 글로벌 제한을 걸 수 있습니다.
3.  **친절한 에러 응답**: 무작정 에러를 뱉는 것보다, `X-RateLimit-Retry-After` 헤더를 통해 "몇 초 뒤에 다시 시도할 수 있는지" 알려주는 것이 클라이언트 개발자를 위한 중요한 배려임을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Bucket4j Official Documentation](https://github.com/bucket4j/bucket4j)
-   [Spring Boot Rate Limiting with Bucket4j](https://www.baeldung.com/spring-bucket4j)
-   [Rate Limiting Strategies and Techniques (Google Cloud)](https://cloud.google.com/architecture/rate-limiting-strategies-techniques)