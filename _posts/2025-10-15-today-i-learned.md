---
title: "Redis를 활용한 캐시 전략: Look-aside vs. Write-through"
date: 2025-10-15
categories: [Architecture, Cache]
tags: [Cache, Redis, System Design, Write-through, Look-aside, Performance, TIL]
excerpt: "애플리케이션의 성능을 극대화하기 위한 핵심 캐시 전략인 Cache-Aside(Look-aside)와 Write-through 패턴을 학습합니다. 각 전략의 데이터 흐름과 장단점을 비교하며, 어떤 상황에 어떤 캐시 전략을 선택해야 하는지 알아봅니다."
author_profile: true
---

# Today I Learned: Redis를 활용한 캐시 전략: Look-aside vs. Write-through

## 📚 오늘 학습한 내용

데이터베이스 부하를 줄이고 애플리케이션의 응답 속도를 향상시키기 위해 캐시(Cache)를 사용하는 것은 이제 선택이 아닌 필수입니다. 하지만 단순히 캐시를 도입하는 것을 넘어, **데이터를 '언제', '어떻게' 캐시에 쓰고 읽을지** 결정하는 **캐시 전략**을 이해하는 것이 중요합니다.

오늘은 가장 널리 사용되는 두 가지 캐시 전략인 **Cache-Aside(Look-aside)**와 **Write-through** 패턴의 동작 방식과 각각의 트레이드오프에 대해 학습했습니다.

---

### 1. **Cache-Aside (or Look-aside) Pattern: Lazy Loading 😴**

**Cache-Aside**는 **애플리케이션이 캐시와 직접 상호작용**하며, 필요할 때만 데이터를 캐시에 적재하는 **'게으른(Lazy)'** 전략입니다. 가장 일반적으로 사용되는 캐시 패턴입니다.

-   **데이터 흐름**:
    1.  **Read**:
        -   애플리케이션은 먼저 **캐시**에서 데이터를 찾습니다. (**Cache Hit**)
        -   만약 캐시에 데이터가 없으면 (**Cache Miss**), 애플리케이션이 **데이터베이스(DB)**에서 데이터를 조회합니다.
        -   조회한 데이터를 **캐시에 저장**한 후, 클라이언트에게 반환합니다.
    2.  **Write**:
        -   애플리케이션은 **DB**에 데이터를 먼저 쓰고,
        -   그다음 **캐시의 해당 데이터를 삭제(Invalidate)**합니다. (수정하는 것보다 삭제하는 것이 데이터 정합성 유지에 더 간단하고 안전합니다.)



#### **Java (Spring) 의사 코드**
```java
@Service
@RequiredArgsConstructor
public class ProductService {

    private final ProductRepository productRepository;
    private final RedisTemplate<String, Product> redisTemplate;

    public Product getProduct(Long id) {
        String cacheKey = "product:" + id;
        
        // 1. 캐시에서 먼저 조회
        Product cachedProduct = redisTemplate.opsForValue().get(cacheKey);
        
        if (cachedProduct != null) {
            return cachedProduct; // Cache Hit
        }

        // 2. Cache Miss -> DB에서 조회
        Product productFromDb = productRepository.findById(id)
                .orElseThrow(() -> new ProductNotFoundException());
        
        // 3. DB 결과를 캐시에 저장
        redisTemplate.opsForValue().set(cacheKey, productFromDb, Duration.ofMinutes(10));
        
        return productFromDb;
    }

    @Transactional
    public void updateProductPrice(Long id, Money newPrice) {
        // 1. DB에 먼저 업데이트
        Product product = productRepository.findById(id).orElseThrow();
        product.changePrice(newPrice); 
        // @Transactional에 의해 DB 커밋
        
        // 2. 캐시 데이터 삭제
        String cacheKey = "product:" + id;
        redisTemplate.delete(cacheKey);
    }
}
```

-   **장점**:
    -   **요청된 데이터만 캐싱**: 실제로 요청되는 데이터만 캐시에 저장되므로, 캐시 메모리를 효율적으로 사용할 수 있습니다.
    -   **장애 대응력**: 캐시 서버에 장애가 발생해도, DB에서 직접 데이터를 읽어올 수 있어 서비스 전체가 중단되지는 않습니다. (성능은 저하됨)
-   **단점**:
    -   **Cache Miss 레이턴시**: 처음 데이터를 조회할 때는 캐시 미스가 발생하므로, DB 조회 + 캐시 쓰기 과정에서 응답 지연이 발생합니다.
    -   **데이터 불일치 가능성**: 읽기 요청이 많은 경우, 캐시가 삭제된 직후 다른 스레드가 DB에서 이전 데이터를 읽어와 캐시에 다시 쓰는 경쟁 상태(Race Condition)가 발생할 수 있습니다.

---

### 2. **Write-through Pattern: 항상 최신 상태 유지 ✍️**

**Write-through**는 데이터를 쓸 때 **항상 캐시를 거쳐서 DB에 쓰도록** 만드는 전략입니다. 캐시와 DB의 데이터 동기화를 캐시 시스템에 위임합니다.

-   **데이터 흐름**:
    1.  **Read**: 읽기 흐름은 Cache-Aside와 동일합니다. (캐시 확인 -> 없으면 DB 조회 -> 캐시에 저장)
    2.  **Write**:
        -   애플리케이션은 **항상 캐시에만** 데이터를 씁니다.
        -   **캐시 시스템**이 동기적으로 **DB에 해당 데이터를 쓰는 작업까지 완료**한 후, 애플리케이션에 응답을 반환합니다.



-   **장점**:
    -   **강력한 데이터 일관성**: 데이터가 항상 캐시와 DB에 동시에 업데이트되므로, 캐시의 데이터는 항상 최신 상태를 유지합니다.
    -   **단순한 애플리케이션 로직**: 데이터 쓰기 로직이 캐시에만 의존하므로 애플리케이션 코드가 단순해집니다.
-   **단점**:
    -   **쓰기 지연 시간(Latency) 증가**: 쓰기 작업이 캐시와 DB 양쪽에 모두 완료되어야 응답하므로, 쓰기 속도가 느립니다.
    -   **불필요한 데이터 캐싱**: 잘 읽히지 않는 데이터도 쓸 때마다 무조건 캐시에 저장되므로, 캐시 공간이 낭비될 수 있습니다.

---

### 3. **어떤 전략을 선택해야 할까?**

| 구분 | **Cache-Aside (Look-aside)** | **Write-through** |
| :--- | :--- | :--- |
| **데이터 흐름 주체** | **애플리케이션** | **캐시 시스템** |
| **적합한 워크로드** | **읽기 위주 (Read-heavy)** | **읽기와 쓰기가 혼합**되고, **데이터 일관성**이 매우 중요할 때 |
| **장점** | 캐시 효율성, 장애 대응력 | 강력한 데이터 일관성, 단순한 코드 |
| **단점** | Cache Miss 지연, 데이터 불일치 가능성 | 높은 쓰기 지연, 캐시 낭비 가능성 |

---

## 💡 배운 점

1.  **캐시는 '은탄환(Silver Bullet)'이 아니다**: 단순히 캐시를 도입한다고 모든 성능 문제가 해결되는 것이 아니라는 점을 다시 한번 깨달았습니다. 우리 서비스의 데이터 읽기/쓰기 패턴을 정확히 분석하고, 그에 맞는 최적의 캐시 전략을 선택하는 것이 핵심입니다.
2.  **Cache-Aside는 실용적인 선택지다**: 대부분의 웹 애플리케이션은 쓰기보다 읽기 요청이 훨씬 많기 때문에, Cache-Aside 패턴이 가장 널리 쓰이는 이유를 이해하게 되었습니다. 구현이 비교적 간단하고, 캐시와 DB 간의 의존성이 낮아 유연하게 대처할 수 있다는 점이 큰 장점입니다.
3.  **데이터 일관성의 비용**: Write-through 패턴은 강력한 데이터 일관성을 보장해주지만, 그 대가로 쓰기 성능을 희생합니다. 데이터의 정합성이 비즈니스적으로 얼마나 중요한지에 따라, 이 비용을 감수할 것인지 결정해야 합니다.

---

## 🔗 참고 자료

-   [Caching Strategies and How to Choose the Right One (AWS)](https://aws.amazon.com/caching/caching-strategies/)
-   [Cache-Aside Pattern (Microsoft Docs)](https://docs.microsoft.com/en-us/azure/architecture/patterns/cache-aside)
-   [An Introduction to Caching (DigitalOcean)](https://www.digitalocean.com/community/tutorials/an-introduction-to-caching)