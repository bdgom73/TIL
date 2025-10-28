---
title: "Spring @Transactional의 전파 속성(Propagation)과 함정"
date: 2025-10-14
categories: [Spring, Transaction]
tags: [Transactional, Propagation, Spring Transaction, AOP, TIL]
excerpt: "Spring @Transactional의 핵심 기능이지만 종종 오해를 부르는 전파 속성(Propagation)을 학습합니다. REQUIRED와 REQUIRES_NEW의 차이점을 알아보고, 프록시 방식으로 인해 발생하는 '자기 호출(self-invocation)' 문제와 그 해결 방법을 탐구합니다."
author_profile: true
---

# Today I Learned: Spring @Transactional의 전파 속성(Propagation)과 함정

## 📚 오늘 학습한 내용

Spring에서 `@Transactional` 애노테이션은 데이터베이스 트랜잭션을 선언적으로 관리해주는 매우 편리한 기능입니다. 하지만 여러 서비스 메서드가 서로를 호출하는 복잡한 상황이 되면, 트랜잭션이 어떻게 동작할지 예측하기 어려워집니다.

오늘은 `@Transactional`의 **전파 속성(Propagation Level)**이 무엇이며, 특히 가장 흔하게 마주치는 **자기 호출(Self-invocation) 문제**가 왜 발생하는지, 그리고 어떻게 해결해야 하는지 깊이 있게 학습했습니다.

---

### 1. **트랜잭션 전파(Transaction Propagation)란? 🌊**

**전파**란, 하나의 트랜잭션이 진행 중인 상태에서 다른 트랜잭션이 필요한 메서드를 호출할 때, **기존 트랜잭션을 어떻게 처리할지** 결정하는 규칙입니다.

예를 들어, `주문 서비스`의 `placeOrder()` 메서드(트랜잭션 A)가 내부적으로 `로그 서비스`의 `log()` 메서드(트랜잭션 B)를 호출한다고 가정해 봅시다. 이때 `log()` 메서드는 `placeOrder()`의 트랜잭션에 합류해야 할까요, 아니면 완전히 새로운 트랜잭션을 시작해야 할까요? 이를 정의하는 것이 바로 전파 속성입니다.

-   **`Propagation.REQUIRED` (기본값)**
    -   **"부모 트랜잭션이 있으면 합류하고, 없으면 새로 시작한다."**
    -   가장 널리 사용되는 기본 전략입니다. 위 예시에서 `log()` 메서드는 `placeOrder()`의 트랜잭션 A에 그대로 합류합니다. 따라서 `placeOrder()`가 롤백되면 `log()`의 작업도 함께 롤백됩니다.

-   **`Propagation.REQUIRES_NEW`**
    -   **"항상 새로운 트랜잭션을 시작한다."**
    -   부모 트랜잭션의 존재 여부와 상관없이, 자신만의 독립적인 트랜잭션을 시작합니다. 부모 트랜잭션은 이 새로운 트랜잭션이 끝날 때까지 일시 중단됩니다.
    -   **주요 사용 사례**: 주된 비즈니스 로직의 성공/실패 여부와 관계없이, **반드시 별도로 커밋되어야 하는 작업**(e.g., 로그 기록, 사용자 활동 이력 저장)에 사용됩니다.

#### **코드 예시**
```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final PaymentService paymentService;
    private final LogService logService;

    @Transactional // (propagation = Propagation.REQUIRED)
    public void processOrder() {
        // ... 주문 로직 ...
        paymentService.pay(); // 부모 트랜잭션에 합류
        
        try {
            logService.logSuccess("Order successful"); // 새로운 트랜잭션 시작
        } catch (Exception e) {
            // 로그 저장 실패가 주문 전체에 영향을 주지 않도록 처리
            System.err.println("Log saving failed, but order process continues.");
        }
    }
}

@Service
public class LogService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void logSuccess(String message) {
        // 이 메서드의 DB 작업은 호출한 쪽의 트랜잭션이 롤백되더라도
        // 독립적으로 커밋된다.
        // ... 로그 저장 로직 ...
    }
}
```

---

### 2. **가장 흔한 함정: 자기 호출(Self-invocation) 문제 늪**

많은 개발자들이 `@Transactional`을 사용하며 겪는 가장 큰 혼란은 바로 **같은 클래스 내의 메서드 호출 시 트랜잭션이 적용되지 않는 문제**입니다.

**❌ 잘못된 예시**
```java
@Service
@Slf4j
public class MyService {

    @Transactional
    public void outerMethod() {
        log.info("outerMethod tx active: {}", TransactionSynchronizationManager.isActualTransactionActive());
        
        // 같은 클래스의 @Transactional 메서드 호출
        this.innerMethod(); 
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void innerMethod() {
        log.info("innerMethod tx active: {}", TransactionSynchronizationManager.isActualTransactionActive());
        // ...
    }
}

// 실행 결과:
// outerMethod tx active: true
// innerMethod tx active: true  <- REQUIRES_NEW가 적용되지 않고, 여전히 바깥 트랜잭션에 속해있음!
```
`innerMethod`는 `REQUIRES_NEW` 속성 때문에 새로운 트랜잭션에서 실행될 것으로 기대했지만, 실제로는 `outerMethod`의 트랜잭션에 그대로 합류해버렸습니다. 왜 이런 일이 발생할까요?

-   **원인: 프록시(Proxy) 기반 AOP**
    1.  Spring의 `@Transactional`은 **AOP(관점 지향 프로그래밍)**를 통해 동작합니다.
    2.  Spring 컨테이너는 `@Transactional`이 붙은 빈(Bean)을 생성할 때, 실제 객체를 감싸는 **프록시(Proxy) 객체**를 만들어 등록합니다.
    3.  외부에서 `myService.outerMethod()`를 호출하면, 이 호출은 **프록시 객체**를 통해 가로채집니다. 프록시는 트랜잭션을 시작한 뒤, 실제 객체의 `outerMethod()`를 호출합니다.
    4.  **문제의 지점**: `outerMethod()` 내부에서 `this.innerMethod()`를 호출하는 것은, 프록시를 통하지 않고 **실제 객체(this) 내부에서 직접 다른 메서드를 호출**하는 것입니다. 프록시를 거치지 않았기 때문에, Spring AOP는 `innerMethod`에 `@Transactional`이 붙어있다는 사실조차 알지 못하고, 트랜잭션 관련 부가 기능(새로운 트랜잭션 시작 등)을 적용할 수 없습니다.



#### **해결 방법**
-   **가장 간단한 방법: 빈(Bean) 분리**: `innerMethod`를 별도의 클래스(`InnerService`)로 분리하고, `MyService`가 `InnerService`를 주입받아 호출하도록 구조를 변경합니다. 이렇게 하면 프록시를 통해 호출되므로 트랜잭션 전파가 정상적으로 동작합니다.
-   **자기 자신을 주입받기**: `MyService`가 `MyService` 자기 자신을 `ApplicationContext`를 통해 주입받아 호출하는 방법도 있지만, 순환 참조 문제가 발생할 수 있어 권장되지는 않습니다.

---

## 💡 배운 점

1.  **`@Transactional`은 마법이 아니다**: 이 애노테이션 뒤에는 AOP와 프록시라는 명확한 기술적 원리가 숨어있음을 이해했습니다. 이 원리를 모르면 '왜 안 되지?'와 같은 디버깅하기 어려운 문제에 직면할 수 있습니다.
2.  **트랜잭션 경계를 명확히 설계하라**: `REQUIRES_NEW`는 강력한 도구이지만, 남용하면 트랜잭션의 원자성을 해치고 데이터 일관성을 깨뜨릴 수 있습니다. "이 작업은 정말로 독립적인 트랜잭션이어야 하는가?"를 신중하게 고민하고, 트랜잭션의 경계를 명확히 설계하는 것이 중요합니다.
3.  **객체 내부 호출을 항상 의심하라**: 클래스 내부에서 `this`를 이용해 다른 메서드를 호출할 때, 만약 그 메서드가 AOP의 대상이 되는 애노테이션(`@Transactional`, `@Async`, `@Cacheable` 등)을 가지고 있다면, 의도대로 동작하지 않을 가능성이 높다는 것을 항상 염두에 두어야 합니다.

---

## 🔗 참고 자료

-   [Spring Framework Docs - Transaction Propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
-   [Spring @Transactional Self-Invocation (Baeldung)](https://www.baeldung.com/spring-transactional-propagation-isolation)
-   [스프링 AOP 내부 호출 문제 (인프런 김영한님)](https://www.inflearn.com/questions/15456)