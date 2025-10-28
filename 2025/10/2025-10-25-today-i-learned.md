---
title: "Redis(Redisson)를 활용한 분산 락(Distributed Lock) 구현하기"
date: 2025-10-25
categories: [Architecture, Concurrency]
tags: [Redis, Redisson, Distributed Lock, Concurrency, MSA, Spring Boot, TIL]
excerpt: "Java의 'synchronized'가 통하지 않는 분산 환경(MSA)에서 동시성 문제를 해결하는 방법인 분산 락(Distributed Lock)의 개념을 학습합니다. Redisson 클라이언트를 사용하여 Redis 기반의 분산 락을 구현하고, 'Lease Time'의 중요성을 알아봅니다."
author_profile: true
---

# Today I Learned: Redis(Redisson)를 활용한 분산 락(Distributed Lock) 구현하기

## 📚 오늘 학습한 내용

Spring 애플리케이션을 단일 인스턴스로 운영할 때는 **`synchronized`** 키워드나 `ReentrantLock`을 사용하여 임계 영역(Critical Section)의 동시성 문제를 제어할 수 있었습니다. 하지만 애플리케이션을 수평 확장(Scale-out)하여 여러 인스턴스(e.g., 여러 Docker 컨테이너)로 실행하는 분산 환경에서는, 이 방식이 더 이상 동작하지 않습니다. 각 인스턴스는 자신만의 JVM 위에서 동작하므로, 한 서버의 락이 다른 서버의 스레드를 막을 수 없기 때문입니다.

오늘은 이처럼 **여러 서버 인스턴스에 걸쳐 동시성을 제어**해야 할 때 사용하는 **분산 락(Distributed Lock)**의 개념과, 이를 Redis와 **Redisson** 클라이언트로 구현하는 방법에 대해 학습했습니다.

---

### 1. **왜 분산 락이 필요한가? 🌍**

"선착순 100명 한정 상품"의 재고를 차감하는 로직을 생각해 봅시다.

1.  사용자 A의 요청이 서버 1번 (`Instance A`)에 도착.
2.  사용자 B의 요청이 서버 2번 (`Instance B`)에 도착.
3.  `Instance A`가 DB에서 재고(100개)를 조회합니다.
4.  동시에 `Instance B`도 DB에서 재고(100개)를 조회합니다.
5.  `Instance A`가 재고를 99개로 차감하고 `synchronized` 블록을 통과합니다.
6.  `Instance B`는 `Instance A`의 `synchronized` 락과 아무 관계가 없으므로, 자신도 재고를 99개로 차감하고 DB에 씁니다.

**결과**: 재고는 99개가 되었어야 하지만, 두 요청이 모두 성공하여 99개로 덮어쓰여지고 상품 2개가 팔렸는데 재고는 1개만 줄어드는 **데이터 불일치(Race Condition)**가 발생합니다.

이 문제를 해결하려면 `Instance A`와 `Instance B`가 모두 공유하고 동의할 수 있는 **중앙의 잠금 장치**가 필요하며, 이것이 바로 **분산 락**입니다.

---

### 2. **Redis를 분산 락으로 사용하는 이유**

-   **Atomic 명령어 지원**: Redis는 `SETNX` (SET if Not eXists)와 같이 "존재하지 않을 때만 값을 설정한다"는 원자적(Atomic) 명령어를 지원합니다. 이를 통해 "락 획득" 과정을 원자적으로 처리할 수 있습니다.
-   **빠른 속도**: In-memory 기반으로 동작하여 락을 획득하고 해제하는 과정이 매우 빠릅니다.
-   **단순함**: Redis는 대부분의 백엔드 개발자에게 이미 익숙한 기술 스택입니다.

---

### 3. **Redisson: 분산 락을 쉽게 구현해주는 Java 클라이언트**

단순히 `SETNX`만으로는 락을 획득한 클라이언트가 장애로 죽었을 때 락이 영원히 해제되지 않는(Deadlock) 문제가 있습니다. **Redisson**은 이러한 복잡한 문제들을 해결하고 `java.util.concurrent.locks.Lock` 인터페이스를 구현하여 Java 개발자에게 매우 친숙한 방식으로 분산 락을 제공하는 고수준 Redis 클라이언트입니다.

#### **1. 의존성 추가 (`build.gradle`)**
```groovy
implementation 'org.redisson:redisson-spring-boot-starter:3.27.2'
```

#### **2. `application.yml` 설정**
```yaml
spring:
  data:
    redis:
      host: localhost
      port: 6379
```
> `redisson-spring-boot-starter`가 `spring-boot-starter-data-redis`의 `host`, `port` 설정을 자동으로 읽어 RedissonClient 빈을 등록해줍니다.

#### **3. 분산 락 적용 (Redisson `RLock`)**
Redisson은 `RLock`이라는 객체를 통해 락을 제공합니다.
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class StockService {

    private final RedissonClient redissonClient;
    private final StockRepository stockRepository;

    @Transactional
    public void decreaseStock(Long productId, int quantity) {
        // 1. 락 키(Key) 정의
        String lockKey = "product_lock:" + productId;
        
        // 2. 락 객체 가져오기
        RLock lock = redissonClient.getLock(lockKey);

        try {
            // 3. 락 획득 시도 (Wait Time, Lease Time 설정)
            //    - waitTime: 락을 획득하기 위해 대기하는 시간 (10초)
            //    - leaseTime: 락을 자동으로 해제하는 시간 (5초)
            //    - 10초간 락을 기다리다, 획득에 성공하면 5초간 락을 점유한다.
            boolean isLocked = lock.tryLock(10, 5, TimeUnit.SECONDS);

            if (!isLocked) {
                log.error("Failed to acquire lock for product: {}", productId);
                throw new IllegalStateException("Cannot acquire lock. Try again.");
            }

            // --- 임계 영역 (Critical Section) ---
            Stock stock = stockRepository.findById(productId)
                    .orElseThrow(() -> new EntityNotFoundException("Stock not found"));
            
            if (stock.getQuantity() < quantity) {
                throw new IllegalStateException("Stock is not enough.");
            }

            stock.decrease(quantity);
            // @Transactional에 의해 메서드 종료 시 DB 커밋
            // ------------------------------------

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Lock interrupted.", e);
        } finally {
            // 4. 락 해제 (반드시 finally에서 실행)
            if (lock.isLocked() && lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}
```
---

### 4. **핵심 개념: Lease Time (락 점유 시간)의 중요성**

-   `lock.tryLock()`의 세 번째 인자인 **`leaseTime`**은 분산 락의 핵심입니다.
-   만약 락을 획득한 서버(`Instance A`)가 비즈니스 로직을 수행하던 중 갑자기 **장애로 다운**되어 `lock.unlock()`을 호출하지 못하면 어떻게 될까요?
-   `leaseTime`이 없다면, 락은 영원히 해제되지 않아 다른 모든 서버가 해당 상품의 재고를 영원히 수정할 수 없는 **데드락(Deadlock)** 상태에 빠집니다.
-   Redisson은 `leaseTime`이 지나면 해당 락을 **자동으로 해제**하여 데드락을 방지합니다.

> **(주의)** `leaseTime`은 비즈니스 로직이 실행되는 최대 시간보다 길게 설정해야 합니다. 만약 로직 수행 시간(e.g., 6초)이 `leaseTime`(e.g., 5초)보다 길어지면, 로직이 끝나기 전에 락이 해제되어 다른 스레드가 임계 영역에 진입하는 문제가 발생할 수 있습니다. (Redisson은 이를 방지하기 위해 락을 연장하는 **Watchdog** 기능을 제공합니다.)

---

## 💡 배운 점

1.  **분산 환경에서의 `synchronized`는 무의미하다**: 여러 인스턴스가 뜨는 MSA 환경에서는 JVM 레벨의 락이 아닌, Redis와 같은 외부의 공유 저장소를 이용한 락이 필수적임을 명확히 이해했습니다.
2.  **Redisson은 복잡성을 숨겨준다**: `SETNX`와 만료 시간(EXPIRE)을 수동으로 조합하며 발생할 수 있는 원자성 문제나, 락을 획득한 클라이언트의 장애로 인한 데드락 문제를 Redisson이 `leaseTime`과 `Watchdog` 같은 메커니즘으로 우아하게 해결해준다는 것을 알게 되었습니다.
3.  **락은 항상 비용이다**: 분산 락은 동시성을 제어하는 강력한 도구이지만, Redis와의 네트워크 통신 비용과 락 경합(Lock Contention)으로 인한 대기 시간 등 시스템 전체의 성능을 저하시킬 수 있습니다. 정말 락이 필요한 로직인지, 혹은 락 없이(Lock-free) 문제를 해결할 방법은 없는지(e.g., 낙관적 락) 먼저 고민하는 습관이 중요함을 깨달았습니다.

---

## 🔗 참고 자료

-   [Redisson - Distributed Locks and Synchronizers](https://github.com/redisson/redisson/wiki/7.-Distributed-locks-and-synchronizers)
-   [Redis Docs - Distributed Locks](https://redis.io/topics/distlock)
-   [Spring Boot with Redisson (Baeldung)](https://www.baeldung.com/redisson)