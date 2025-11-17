---
title: "Spring Events: ApplicationEventPublisher로 서비스 결합도 낮추기"
date: 2025-11-17
categories: [Spring, Architecture]
tags: [Spring Events, ApplicationEventPublisher, @EventListener, @TransactionalEventListener, Decoupling, TIL]
excerpt: "@Transactional 메서드 내에서 이메일 발송 등 외부 API를 호출할 때 발생하는 문제점을 알아봅니다. Spring의 내장 이벤트 시스템을 통해 서비스 로직을 분리(Decoupling)하고, 트랜잭션과 이벤트를 안전하게 동기화하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Events: ApplicationEventPublisher로 서비스 결합도 낮추기

## 📚 오늘 학습한 내용

서비스 로직을 구현할 때, 하나의 핵심 작업(e.g., '회원 가입')에 여러 부가적인 작업(e.g., '가입 축하 이메일 발송', '추천인 쿠폰 지급')이 따라붙는 경우가 많습니다.

`UserService`의 `signUp()` 메서드 내부에서 `EmailService`와 `CouponService`를 직접 호출하는 것은 **단일 책임 원칙(SRP)**을 위배하고, 서비스 간의 **결합도(Coupling)**를 높입니다.

오늘은 이 문제를 해결하기 위해, Spring 프레임워크에 내장된 **Application Event** 시스템을 사용하여 서비스들을 느슨하게 연결하는 방법에 대해 학습했습니다.

---

### 1. **문제점: 트랜잭션 내의 외부 호출 😥**

가장 흔히 발생하는 문제는 `@Transactional` 메서드 내에서 외부 API(이메일, 슬랙 등)를 직접 호출하는 경우입니다.

```java
@Service
@RequiredArgsConstructor
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;

    @Transactional
    public void signUp(String email, String password) {
        // 1. 핵심 로직: 사용자 저장 (DB 트랜잭션 시작)
        User user = new User(email, password);
        userRepository.save(user);

        // 2. 부가 로직: 이메일 발송
        try {
            emailService.sendWelcomeEmail(email); // (느림, 실패 가능)
        } catch (Exception e) {
            // 이메일 발송 실패 시 어떻게 할 것인가?
            // 1. 트랜잭션을 롤백? -> 회원가입 자체가 실패함 (X)
            // 2. 예외를 무시? -> 트랜잭션은 커밋되지만 사용자는 메일을 못 받음
        }
        // 3. 트랜잭션 커밋
    }
}
```
-   **성능 문제**: `emailService`가 3초간 지연되면, DB 커넥션도 3초간 불필요하게 점유됩니다.
-   **트랜잭션 문제**: `emailService`에서 예외가 발생하면, 이미 성공한 `userRepository.save()`까지 **롤백**되어 회원가입 자체가 취소될 수 있습니다.

---

### 2. **해결책: Spring Application Event 💡**

Spring의 이벤트 시스템은 **옵저버 패턴(Observer Pattern)**의 구현체입니다.
-   **`ApplicationEventPublisher`**: 이벤트를 발행(Publish)하는 '발행자'.
-   **Event (POJO)**: 발행된 '이벤트' 자체. 필요한 데이터를 담고 있습니다.
-   **`@EventListener`**: 이벤트를 구독(Subscribe)하여 처리하는 '구독자'.

#### **Step 1: Event 클래스 정의 (POJO)**
이벤트로 전달할 데이터를 담은 간단한 POJO(또는 Record)를 만듭니다.

```java
// UserSignedUpEvent.java
// 회원가입이 완료되었음을 알리는 이벤트
public record UserSignedUpEvent(
    Long userId,
    String email
) {
    // 과거에는 ApplicationEvent를 상속해야 했으나,
    // Spring 4.2부터는 POJO로도 가능.
}
```

#### **Step 2: Publisher - 이벤트 발행 (Service)**
핵심 로직(UserService)은 이벤트를 '발행'만 하고, 이메일 발송에 대해서는 알지 못하게 합니다.

```java
@Service
@RequiredArgsConstructor
public class UserService {
    private final UserRepository userRepository;
    private final ApplicationEventPublisher eventPublisher; // 1. 발행자 주입

    @Transactional
    public void signUp(String email, String password) {
        User user = new User(email, password);
        userRepository.save(user);

        // 2. 이메일 서비스를 직접 호출하는 대신, '이벤트'를 발행
        //    "회원가입 끝났으니, 관심 있는 사람들은 이 정보 받아가!"
        eventPublisher.publishEvent(new UserSignedUpEvent(user.getId(), user.getEmail()));
        
        // 트랜잭션은 여기서 즉시 커밋됨
    }
}
```

#### **Step 3: Listener - 이벤트 구독 (Subscriber)**
부가 로직(EmailService)은 `@EventListener`를 통해 이벤트를 구독하여 처리합니다.

```java
@Service
@Slf4j
@RequiredArgsConstructor
public class EmailNotificationListener {

    private final EmailService emailService;

    // 3. UserSignedUpEvent가 발행되면 이 메서드가 실행됨
    @EventListener
    public void handleUserSignUp(UserSignedUpEvent event) {
        log.info("Sending welcome email to: {}", event.email());
        try {
            emailService.sendWelcomeEmail(event.email());
        } catch (Exception e) {
            log.error("Failed to send email", e);
            // ... (재시도 로직 등) ...
        }
    }
}
```

---

### 3. **3~4년차의 핵심: 이벤트와 트랜잭션의 동기화 🔄**

위의 코드는 여전히 심각한 문제가 있습니다.

-   **`@EventListener`는 기본적으로 동기(Synchronous) 실행**입니다.
-   `eventPublisher.publishEvent()`가 호출되면, `handleUserSignUp` 메서드의 **실행이 끝날 때까지** `signUp` 메서드가 대기(Block)합니다.
-   즉, `handleUserSignUp`은 `signUp`의 **트랜잭션에 그대로 합류**하게 됩니다.

결국, `EmailService`에서 예외가 발생하면 `UserService`의 트랜잭션이 **똑같이 롤백**되는 원래의 문제로 돌아갑니다.

#### **진짜 해결책: `@TransactionalEventListener`**
Spring은 이 문제를 해결하기 위해 **트랜잭션의 상태**에 따라 이벤트를 처리할 수 있는 `@TransactionalEventListener`를 제공합니다.

```java
@Service
@Slf4j
@RequiredArgsConstructor
public class EmailNotificationListener {

    private final EmailService emailService;

    // (BEFORE) -> @EventListener
    // (AFTER) -> @TransactionalEventListener
    @TransactionalEventListener(
        phase = TransactionPhase.AFTER_COMMIT // (핵심!)
    )
    @Async // (선택) 별도 스레드에서 비동기 실행 (메인 스레드 반환)
    public void handleUserSignUpAfterCommit(UserSignedUpEvent event) {
        
        log.info("Transaction committed. Sending welcome email to: {}", event.email());
        
        // 이 로직은 UserService의 트랜잭션이 '성공적으로 커밋된 후에만' 실행됨
        emailService.sendWelcomeEmail(event.email());
    }
}
```
> (참고: `@Async`를 사용하려면 메인 클래스에 `@EnableAsync`가 필요합니다.)

-   **`phase = TransactionPhase.AFTER_COMMIT`**: `signUp` 메서드의 `@Transactional`이 성공적으로 **커밋**되었을 때만 이 리스너를 실행합니다.
-   **`@Async`**: 이메일 발송 작업을 별도의 스레드에서 수행하도록 하여, 회원가입 API의 응답 속도에 영향을 주지 않도록 합니다.

---

## 💡 배운 점

1.  **관심사의 분리 (SoC)**: Spring 이벤트를 사용함으로써, '회원 가입'이라는 핵심 로직과 '알림 발송'이라는 부가 로직을 완벽하게 분리했습니다. 이제 `UserService`는 `EmailService`의 존재 자체를 알 필요가 없어졌습니다.
2.  **트랜잭션과 이벤트는 동기화되어야 한다**: `@EventListener`를 무심코 사용하면, 트랜잭션 경계가 의도치 않게 확장되어 장애 전파를 막을 수 없습니다. `@TransactionalEventListener`와 `AFTER_COMMIT` 옵션이야말로, 데이터 정합성(회원가입 성공)을 보장하면서 부가 기능을 안전하게 실행하는 핵심임을 깨달았습니다.
3.  **Kafka vs. Spring Events**: MSA 간의 통신처럼 시스템 외부와의 비동기 통신은 Kafka가 적합하지만, **단일 애플리케이션 내부**의 모듈 간 결합도를 낮추는 데는 Spring Events가 훨씬 가볍고 효과적인 솔루션임을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Docs - Standard and Custom Events](https://docs.spring.io/spring-framework/reference/core/beans/context-events.html)
-   [Spring Docs - @TransactionalEventListener](https://docs.spring.io/spring-framework/reference/data-access/transaction/events.html)
-   [Spring Events (Baeldung)](https://www.baeldung.com/spring-events)