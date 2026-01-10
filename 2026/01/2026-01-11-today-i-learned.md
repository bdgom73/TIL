---
title: "@Transactional의 전파 속성(Propagation): REQUIRES_NEW와 예외처리의 미묘한 관계"
date: 2026-01-11
categories: [Spring, Database, Transaction]
tags: [Spring Boot, Transaction, Propagation, REQUIRES_NEW, Rollback, JPA, TIL]
excerpt: "부모 트랜잭션과 독립적으로 실행되어야 하는 자식 트랜잭션(예: 실패해도 되는 로그 저장)을 구현할 때, 단순히 @Transactional(propagation = REQUIRES_NEW)만 붙이면 부모까지 롤백되는 현상을 분석합니다. 물리 트랜잭션 분리와 예외 처리(Try-Catch)의 필수적인 관계를 학습합니다."
author_profile: true
---

# Today I Learned: @Transactional의 전파 속성(Propagation): REQUIRES_NEW와 예외처리의 미묘한 관계

## 📚 오늘 학습한 내용

"주문은 성공했는데, 알림 발송 이력 저장이 실패해서 주문까지 롤백되어 버렸다."
실무에서 흔히 겪는 이 문제를 해결하기 위해 **트랜잭션 전파 속성(Propagation)**을 건드렸다가, 예상치 못한 롤백 현상으로 고생했습니다.

오늘은 단순히 `REQUIRES_NEW`를 쓴다고 만사형통이 아니며, **예외 전파(Exception Propagation)**를 막지 않으면 물리 트랜잭션이 분리되어도 소용없다는 사실을 깊이 있게 학습했습니다.

---

### 1. **문제 상황: 논리 트랜잭션 vs 물리 트랜잭션 🔄**

기본적으로 Spring의 `@Transactional`은 `REQUIRED`가 디폴트입니다. 이는 부모와 자식이 하나의 **물리 트랜잭션(DB Connection)**을 공유함을 의미합니다.

-   **시나리오**: `OrderService`(부모) -> `LogService`(자식)
-   **문제**: `LogService`에서 예외(`RuntimeException`)가 발생하면, 부모-자식이 한 배를 탔기 때문에 `rollback-only` 마크가 찍히고, 부모 트랜잭션이 끝날 때 전체가 롤백됩니다.

이를 막기 위해 `LogService`에 `REQUIRES_NEW`를 붙여 **트랜잭션을 분리**하기로 했습니다.

---

### 2. **함정: REQUIRES_NEW를 썼는데 왜 부모도 롤백될까?**

`REQUIRES_NEW`를 사용하면 `LogService`는 별도의 DB 커넥션을 맺고 독립적인 물리 트랜잭션을 시작합니다. 하지만 코드를 아래와 같이 짜면 부모도 여전히 롤백됩니다.

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final LogService logService;
    private final OrderRepository orderRepository;

    @Transactional
    public void createOrder(OrderDto dto) {
        Order order = orderRepository.save(dto.toEntity());
        
        // 여기서 예외가 터지면?
        logService.saveLog(order.getId()); 
    }
}

@Service
public class LogService {
    @Transactional(propagation = Propagation.REQUIRES_NEW) // 새 트랜잭션 시작
    public void saveLog(Long orderId) {
        throw new RuntimeException("로그 저장 실패"); // 강제 예외 발생
    }
}
```

**원인 분석:**
1.  `LogService` 트랜잭션은 예외 발생으로 롤백됩니다. (정상 동작)
2.  하지만 발생한 `RuntimeException`이 **메서드 밖으로 던져져서(Throw)** `OrderService`로 전파됩니다.
3.  `OrderService`의 트랜잭션 AOP가 이 예외를 감지하고, "어? 예외가 발생했네?" 하고 본인 트랜잭션도 롤백시킵니다.

즉, **트랜잭션은 분리되었지만, 예외는 분리되지 않았기 때문**입니다.

---

### 3. **해결책: 트랜잭션 분리 + 예외 캐치 (Try-Catch)**

부모 트랜잭션을 보호하려면 자식 트랜잭션 호출부를 반드시 **`try-catch`**로 감싸서 예외가 부모 트랜잭션 AOP까지 도달하지 못하게 막아야 합니다.

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final LogService logService;

    @Transactional
    public void createOrder(OrderDto dto) {
        orderRepository.save(dto.toEntity());
        
        try {
            // 별도 트랜잭션으로 실행
            logService.saveLog(dto.toEntity().getId());
        } catch (Exception e) {
            // [중요] 예외를 여기서 먹어버림 (Swallow Exception)
            // 로그만 남기고 부모 트랜잭션은 정상 진행하도록 함
            log.warn("로그 저장 실패했습니다. 하지만 주문은 계속 진행합니다. error={}", e.getMessage());
        }
    }
}
```

---

### 4. **심화: Checked Exception과 Rollback Rule**

트랜잭션 롤백의 기본 규칙도 다시 한번 정리했습니다.

-   **Unchecked Exception (`RuntimeException`, `Error`)**: 기본적으로 **롤백**됩니다.
-   **Checked Exception (`Exception`, `IOException` 등)**: 기본적으로 **롤백되지 않습니다(커밋됨).**

만약 비즈니스 로직상 "잔액 부족" 같은 상황을 Checked Exception으로 만들었다면, `@Transactional(rollbackFor = Exception.class)` 옵션을 주지 않는 한 데이터가 커밋되어버리는 대참사가 일어날 수 있음을 주의해야 합니다.

---

## 💡 배운 점

1.  **REQUIRES_NEW의 진정한 의미**: 단순히 "독립적이다"라는 말만 믿으면 안 됩니다. 물리적인 커넥션만 독립적일 뿐, 자바의 예외 전파 메커니즘(`Call Stack`)까지 끊어주는 것은 아닙니다. **"구조 분리"와 "예외 처리"는 별개**임을 깨달았습니다.
2.  **커넥션 고갈 주의**: `REQUIRES_NEW`는 하나의 요청 스레드가 동시에 2개의 DB 커넥션을 점유하게 만듭니다. (부모 대기 중 + 자식 실행 중). 트래픽이 몰릴 때 커넥션 풀이 빠르게 고갈되어 **데드락**이나 **타임아웃**을 유발할 수 있으므로 신중하게 사용해야 합니다.
3.  **내부 호출(Self-invocation) 재확인**: 이 모든 설정도 같은 클래스 내의 메서드를 호출(`this.saveLog()`)하면 프록시가 동작하지 않아 `REQUIRES_NEW`가 무시됩니다. 반드시 외부 빈(`LogService`)으로 분리해서 주입받아야 합니다.

---

## 🔗 참고 자료

-   [Spring Transaction Management](https://docs.spring.io/spring-framework/reference/data-access/transaction.html)
-   [Understand Spring Transaction Propagation Rules](https://www.baeldung.com/spring-transactional-propagation-isolation)
-   [Best Practices for @Transactional](https://vladmihalcea.com/spring-transactional-annotation-best-practices/)