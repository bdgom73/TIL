---
title: "Redis Caching 심화: Thundering Herd(Cache Stampede) 문제와 해결 전략"
date: 2026-01-16
categories: [Spring, Redis, Performance]
tags: [Redis, Caching, Cache Stampede, Thundering Herd, Spring Cache, Performance Tuning, TIL]
excerpt: "대용량 트래픽 환경에서 캐시가 만료되는 순간 수천 개의 요청이 동시에 DB를 타격하는 'Thundering Herd' 현상을 분석합니다. Spring Cache의 @Cacheable(sync=true) 옵션을 통한 로컬 락 적용 방법과 PER(Probabilistic Early Recomputation) 등 고급 캐싱 전략을 학습합니다."
author_profile: true
---

# Today I Learned: Redis Caching 심화: Thundering Herd(Cache Stampede) 문제와 해결 전략

## 📚 오늘 학습한 내용

서비스 메인 페이지의 '베스트 상품 목록' API에 Redis 캐싱(`@Cacheable`)을 적용해 두었습니다. 평소에는 빠르지만, **캐시가 만료되는(TTL Expire) 그 짧은 찰나**에 순간적으로 DB CPU가 100%를 치며 커넥션 풀이 고갈되는 현상을 겪었습니다.

이는 전형적인 **Thundering Herd (또는 Cache Stampede)** 문제로, 캐시 미스(Cache Miss)가 발생한 순간 대기하고 있던 수많은 요청이 동시에 "내가 캐시를 갱신하겠다"며 DB로 돌진해서 발생하는 문제입니다. 오늘은 이를 방어하기 위한 전략을 학습하고 적용했습니다.

---

### 1. **Thundering Herd 문제란? 🐂**

일반적인 Look-aside 캐싱 패턴에서는 다음과 같이 동작합니다.
1.  요청 1: 캐시 확인 -> 없음 -> **DB 조회** -> 캐시 저장 -> 응답
2.  요청 2: 캐시 확인 -> 있음 -> 응답

하지만 트래픽이 초당 1,000건일 때 캐시가 만료되면?
1.  요청 1~1000: (동시에) 캐시 확인 -> **다 같이 없음** -> **1,000개가 동시에 DB 조회** -> DB 사망 💀

---

### 2. **해결책 1: Spring Cache의 `sync = true`**

Spring Boot의 `@Cacheable` 애노테이션은 이 문제를 해결하기 위한 간단한 옵션을 제공합니다.

**적용 전**
```java
@Cacheable(value = "bestItems", key = "'main'")
public List<ItemDto> getBestItems() {
    return itemRepository.findBestItems(); // 동시 요청 시 여러 번 실행됨
}
```

**적용 후**
```java
// sync = true: 로컬에서 synchronized 블록을 걸어줌
@Cacheable(value = "bestItems", key = "'main'", sync = true)
public List<ItemDto> getBestItems() {
    return itemRepository.findBestItems();
}
```

-   **동작 원리**: 캐시 미스가 발생하면, 해당 키에 대해 **Java 레벨의 `synchronized` 락**을 겁니다.
    -   요청 1: 캐시 없음 -> 락 획득 -> DB 조회 -> 캐시 갱신 -> 락 해제
    -   요청 2~1000: 락 대기 -> (요청 1이 끝난 후) -> 캐시 확인 -> 있음(요청 1이 만듦) -> DB 안 가고 리턴
-   **한계**: 애플리케이션 서버가 여러 대(Scale-out)라면, **각 서버마다 1명씩**은 DB를 조회하므로 완벽한 전역 락은 아닙니다. (서버가 10대면 DB 조회 10회 발생). 하지만 1,000회 조회를 10회로 줄여주므로 실무에서 가장 가성비 좋은 해결책입니다.

---

### 3. **해결책 2: 분산 락(Distributed Lock) 사용**

서버 대수가 많아서 `sync=true`로도 DB 부하가 걱정된다면, Redis 자체의 분산 락을 사용해야 합니다.

```java
public List<ItemDto> getBestItems() {
    // 1. 캐시 조회
    List<ItemDto> cached = redisTemplate.opsForValue().get("bestItems");
    if (cached != null) return cached;

    // 2. 캐시 없으면 락 획득 시도 (Redisson 등 활용)
    RLock lock = redissonClient.getLock("bestItems:lock");
    try {
        if (lock.tryLock(5, 1, TimeUnit.SECONDS)) {
            // 3. 락 획득 후 다시 한번 캐시 확인 (Double Check Locking)
            cached = redisTemplate.opsForValue().get("bestItems");
            if (cached != null) return cached;

            // 4. 진짜 DB 조회 및 캐시 갱신
            List<ItemDto> data = itemRepository.findBestItems();
            redisTemplate.opsForValue().set("bestItems", data, Duration.ofMinutes(10));
            return data;
        } else {
            // 락 획득 실패 시: 잠시 대기 후 캐시 읽기 or 기본값 반환
            Thread.sleep(100);
            return redisTemplate.opsForValue().get("bestItems");
        }
    } finally {
        if (lock.isHeldByCurrentThread()) lock.unlock();
    }
}
```
> **단점**: 코드가 복잡해지고, 락 관리 비용이 발생합니다. 정말 중요한 데이터가 아니면 `sync=true`로 충분합니다.

---

### 4. **고급 전략: PER (Probabilistic Early Recomputation)**

락을 걸면 어쨌든 대기 시간(Latency)이 발생합니다. 락 없이 문제를 해결하는 확률적 알고리즘도 있습니다.

-   **개념**: 만료 시간(TTL)이 되기 **직전에**, 확률적으로 미리 캐시를 갱신해버리는 방식입니다.
-   **로직**:
    -   `남은 TTL` < `갱신에 걸리는 시간` * `Beta(가중치)` * `Random()`
    -   위 조건이 참이면, 캐시가 아직 만료되지 않았지만 미리 DB를 조회해서 갱신합니다.
-   **효과**: 캐시 만료 시점이 오기 전에 누군가가 갱신을 해두므로, 사용자는 항상 만료되지 않은 캐시를 보게 됩니다. (Background Refresh와 유사)

---

## 💡 배운 점

1.  **캐싱은 양날의 검**: 캐시를 도입하면 평소엔 빠르지만, 장애 시점에는 시스템을 더 취약하게 만들 수 있음을 깨달았습니다. 캐시가 없을 때의 부하(Fallback)를 항상 고려해야 합니다.
2.  **`sync=true`의 가치**: Spring Cache를 쓸 때 이 옵션 하나만 켜도 대형 사고를 막을 수 있다는 점이 놀라웠습니다. 특히 읽기 중심(Read-heavy)의 서비스에서는 필수 옵션으로 가져가야겠습니다.
3.  **TTL의 분산**: 모든 캐시가 정확히 10분 뒤에 동시에 만료되면 DB에 거대한 파도가 칩니다. TTL에 `Random(1~60초)` 정도의 지터를(Jitter) 섞어주는 것만으로도 부하를 시간 축으로 분산시킬 수 있습니다.

---

## 🔗 참고 자료

-   [Spring Boot Cache Documentation](https://docs.spring.io/spring-framework/reference/integration/cache.html)
-   [Caching Best Practices (AWS)](https://aws.amazon.com/caching/best-practices/)
-   [Thundering Herd Problem Wikipedia](https://en.wikipedia.org/wiki/Thundering_herd_problem)