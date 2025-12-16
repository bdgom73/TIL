---
title: "JPA 동시성 제어: 낙관적 락(Optimistic Lock)과 Spring Retry로 데이터 정합성 지키기"
date: 2025-12-16
categories: [Spring, JPA, Database]
tags: [Concurrency, JPA, Optimistic Lock, Pessimistic Lock, Spring Retry, AOP, TIL]
excerpt: "동시성 이슈(Race Condition)로 인한 데이터 손실(Lost Update) 문제를 해결하기 위해 JPA의 낙관적 락(@Version)을 적용합니다. 락 충돌 발생 시 ObjectOptimisticLockingFailureException을 처리하고, Spring Retry를 통해 자동으로 재시도하는 우아한 방법을 학습합니다."
author_profile: true
---

# Today I Learned: JPA 동시성 제어: 낙관적 락(Optimistic Lock)과 Spring Retry로 데이터 정합성 지키기

## 📚 오늘 학습한 내용

티켓 예매나 재고 차감 같은 기능을 개발할 때, **"두 명의 사용자가 동시에 마지막 남은 1개의 상품을 구매하려고 하면 어떻게 될까?"**라는 문제는 백엔드 개발자의 영원한 숙제입니다.

단순히 트랜잭션(`@Transactional`)만으로는 이 **갱신 손실(Lost Update)** 문제를 막을 수 없습니다. 오늘은 DB 락(Lock)을 직접 걸지 않고 애플리케이션 레벨에서 버전을 관리하여 성능 저하를 최소화하는 **낙관적 락(Optimistic Lock)**과, 충돌 발생 시 **자동 재시도(Retry)** 메커니즘을 구현하는 방법을 학습했습니다.

---

### 1. **비관적 락(Pessimistic) vs 낙관적 락(Optimistic)**

| 특징 | **비관적 락 (Pessimistic Lock)** | **낙관적 락 (Optimistic Lock)** |
| :--- | :--- | :--- |
| **원리** | "충돌이 날 거야"라고 가정하고 미리 DB에 락을 겁니다. (`SELECT ... FOR UPDATE`) | "충돌이 안 날 거야"라고 가정하고 락을 걸지 않습니다. 대신 **버전(Version)** 정보를 확인합니다. |
| **장점** | 데이터 무결성이 확실하게 보장됩니다. | DB 락을 잡지 않으므로 성능이 좋고 처리량이 높습니다. |
| **단점** | 데드락(Deadlock) 위험이 있고, 대기 시간이 길어져 성능이 저하될 수 있습니다. | 충돌 발생 시 **예외가 발생**하므로, 개발자가 **재시도 로직**을 직접 구현해야 합니다. |
| **선택** | 돈, 정산 등 충돌이 잦고 정합성이 매우 중요한 경우 | 대부분의 일반적인 웹 애플리케이션 (충돌 빈도가 낮은 경우) |

---

### 2. **낙관적 락 적용하기: `@Version`**

JPA는 `@Version` 애노테이션 하나로 낙관적 락을 매우 쉽게 지원합니다.

#### **Step 1: 엔티티에 버전 필드 추가**
```java
@Entity
@Getter
public class Product {
    @Id @GeneratedValue
    private Long id;

    private Long stockQuantity;

    @Version // 낙관적 락을 위한 버전 관리 필드
    private Long version;

    public void decreaseStock(Long quantity) {
        if (this.stockQuantity - quantity < 0) {
            throw new IllegalArgumentException("재고 부족");
        }
        this.stockQuantity -= quantity;
    }
}
```

이제 JPA가 `UPDATE` 쿼리를 날릴 때 다음과 같이 동작합니다.
```sql
UPDATE product
SET stock_quantity = ?, version = version + 1
WHERE id = ? AND version = ? -- 읽어왔을 때의 버전과 일치하는지 확인
```
만약 누군가 먼저 수정해서 버전이 올라갔다면, `WHERE` 조건에 맞지 않아 `Row count`가 0이 되고, JPA는 **`ObjectOptimisticLockingFailureException`**을 발생시킵니다.

---

### 3. **Spring Retry로 재시도 자동화하기 🔄**

낙관적 락의 핵심은 **"실패했을 때 어떻게 할 것인가?"**입니다. 사용자에게 "에러가 났으니 다시 버튼을 누르세요"라고 하는 것보다, 시스템이 알아서 0.1초 뒤에 다시 시도하는 것이 경험상 좋습니다.

Spring Retry 라이브러리를 사용하면 이를 AOP로 깔끔하게 구현할 수 있습니다.

#### **Step 1: 의존성 추가**
```groovy
implementation 'org.springframework.retry:spring-retry'
implementation 'org.springframework:spring-aspects'
```

#### **Step 2: 재시도 활성화 및 적용**
메인 클래스나 설정 클래스에 `@EnableRetry`를 붙이고, 서비스 메서드에 `@Retryable`을 적용합니다.

```java
@Service
@RequiredArgsConstructor
public class StockService {

    private final ProductRepository productRepository;

    @Transactional
    @Retryable(
        retryFor = ObjectOptimisticLockingFailureException.class, // 이 예외가 발생하면
        maxAttempts = 3, // 최대 3번까지 재시도
        backoff = @Backoff(delay = 100) // 100ms 간격으로 시도
    )
    public void decreaseStock(Long productId, Long quantity) {
        Product product = productRepository.findById(productId)
                .orElseThrow();
        
        product.decreaseStock(quantity);
        // 트랜잭션 커밋 시점에 버전 체크 수행 -> 실패 시 예외 발생 -> @Retryable이 잡아서 재시도
    }

    // 모든 재시도가 실패했을 때 실행되는 메서드 (Fallback)
    @Recover
    public void recover(ObjectOptimisticLockingFailureException e, Long productId, Long quantity) {
        // e.g., 사용자에게 "주문 폭주로 인해 실패했습니다" 알림 발송
        throw new ServiceUnavailableException("재고 차감 실패");
    }
}
```

---

### 4. **심화: Facade 패턴으로 트랜잭션 분리**

`@Retryable`을 사용할 때 주의할 점은, **재시도 시 `@Transactional`도 새로 시작되어야 한다**는 점입니다. 하지만 같은 클래스 내에서의 호출이나, 트랜잭션 범위가 꼬이면 재시도가 제대로 동작하지 않을 수 있습니다.

실무에서는 더 확실한 제어를 위해 **Facade 패턴**을 사용하여 재시도 로직과 비즈니스 로직을 분리하기도 합니다.

```java
@Component
@RequiredArgsConstructor
public class StockFacade {

    private final StockService stockService;

    public void decreaseStock(Long id, Long quantity) throws InterruptedException {
        while (true) {
            try {
                stockService.decreaseStock(id, quantity); // 이 메서드는 @Transactional(requires_new) 권장
                break; // 성공하면 탈출
            } catch (ObjectOptimisticLockingFailureException e) {
                // 실패하면 50ms 대기 후 무한 재시도 (혹은 횟수 제한)
                Thread.sleep(50);
            }
        }
    }
}
```
> 이 방식은 Redis를 이용한 스핀 락(Spin Lock) 구현과도 유사한 구조를 가집니다.

---

## 💡 배운 점

1.  **은탄환은 없다**: 낙관적 락이 성능상 유리하지만, 충돌이 빈번하게 일어나는 선착순 이벤트 같은 상황에서는 재시도 횟수가 너무 많아져 오히려 비관적 락보다 성능이 떨어질 수 있음을 알게 되었습니다. 비즈니스 특성(충돌 빈도)에 따른 선택이 중요합니다.
2.  **JPA의 영속성 컨텍스트와 재시도**: 재시도를 할 때는 반드시 **새로운 트랜잭션**에서 데이터를 **새로 조회**해야 합니다. 이미 영속성 컨텍스트에 옛날 버전의 엔티티가 남아있다면 재시도를 해도 똑같이 실패하기 때문입니다.
3.  **Spring Retry의 편리함**: `try-catch`와 `while`문으로 지저분해질 수 있는 재시도 로직을 애노테이션 하나로 선언적으로 처리할 수 있어 비즈니스 로직의 가독성이 크게 향상되었습니다.

---

## 🔗 참고 자료

-   [JPA Locking Mechanisms](https://www.baeldung.com/jpa-pessimistic-locking)
-   [Spring Retry Guide](https://github.com/spring-projects/spring-retry)
-   [Handling Concurrency in Spring Boot](https://reflectoring.io/spring-boot-concurrency/)