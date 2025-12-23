---
title: "Spring Events로 서비스 간 강결합 끊기: @TransactionalEventListener의 활용"
date: 2025-12-23
categories: [Spring, Architecture]
tags: [Spring Events, ApplicationEventPublisher, TransactionalEventListener, Decoupling, Observer Pattern, Async, TIL]
excerpt: "도메인 간의 강한 결합을 느슨하게 만들기 위해 Spring Event를 도입합니다. 단순히 이벤트를 발행하는 것을 넘어, 트랜잭션 커밋 시점을 보장하는 @TransactionalEventListener의 동작 원리와 비동기 처리(@Async)를 조합하여 안정적인 이벤트 기반 아키텍처를 구축하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Events로 서비스 간 강결합 끊기: @TransactionalEventListener의 활용

## 📚 오늘 학습한 내용

회원 가입 로직(`MemberService`)에 가입 환영 이메일 발송(`EmailService`)과 쿠폰 지급(`CouponService`) 로직이 섞여 있어 코드가 비대해지고 의존성이 복잡해졌습니다. "이메일 발송이 실패했다고 회원 가입까지 롤백되어야 하는가?"라는 질문에 "아니오"라는 결론을 내렸고, 이를 해결하기 위해 **Spring Event**를 도입하여 결합도를 낮추는 리팩토링을 진행했습니다.

특히, 트랜잭션의 성공 여부에 따라 이벤트를 처리해야 하는 요구사항을 만족시키기 위해 **`@TransactionalEventListener`**를 집중적으로 학습했습니다.

---

### 1. **문제 상황: 강결합(Tight Coupling) 🔗**

```java
@Service
@RequiredArgsConstructor
public class MemberService {
    private final MemberRepository memberRepository;
    private final EmailService emailService; // 외부 서비스 의존성
    private final CouponService couponService; // 외부 서비스 의존성

    @Transactional
    public void join(MemberDto dto) {
        Member member = memberRepository.save(dto.toEntity());
        
        // 1. 회원 가입 본연의 로직과 상관없는 코드가 섞임
        // 2. 이메일 서버가 죽으면 회원 가입도 같이 실패함 (트랜잭션이 묶여있거나 예외 전파)
        emailService.sendWelcomeEmail(member.getEmail());
        couponService.issueWelcomeCoupon(member.getId());
    }
}
```

---

### 2. **해결책: Spring Event 도입**

Spring의 `ApplicationEventPublisher`를 사용하면 옵저버 패턴을 아주 쉽게 구현할 수 있습니다.

#### **Step 1: 이벤트 클래스 정의**
순수 POJO로 정의합니다.
```java
@Getter
@AllArgsConstructor
public class MemberJoinedEvent {
    private Long memberId;
    private String email;
}
```

#### **Step 2: 이벤트 발행 (Publisher)**
`MemberService`는 이제 이메일이나 쿠폰 서비스를 알 필요가 없습니다. 단지 "회원 가입이 발생했다"라고 외치기만 하면 됩니다.

```java
@Service
@RequiredArgsConstructor
public class MemberService {
    private final MemberRepository memberRepository;
    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public void join(MemberDto dto) {
        Member member = memberRepository.save(dto.toEntity());
        
        // 이벤트 발행
        eventPublisher.publishEvent(new MemberJoinedEvent(member.getId(), member.getEmail()));
    }
}
```

---

### 3. **핵심: `@EventListener` vs `@TransactionalEventListener`**

이벤트를 구독(Listener)하는 방식에는 두 가지가 있으며, 그 차이를 명확히 아는 것이 중요합니다.

#### **1. `@EventListener` (동기 실행)**
```java
@Component
public class EmailEventListener {
    @EventListener
    public void handle(MemberJoinedEvent event) {
        // MemberService의 join 트랜잭션 범위 안에서 동기적으로 실행됨
        emailService.send(event.getEmail()); 
    }
}
```
-   **문제점**: 이메일 전송 중 예외가 터지면 `MemberService`의 트랜잭션도 같이 롤백됩니다. (원치 않는 상황)
-   **문제점 2**: 만약 리스너에서 DB 조회를 하는데, `MemberService`가 아직 커밋되지 않은 상태라면 데이터를 찾지 못할 수 있습니다.

#### **2. `@TransactionalEventListener` (트랜잭션 위상에 따른 실행)**
```java
@Component
public class CouponEventListener {
    // phase = TransactionPhase.AFTER_COMMIT (기본값)
    // 본문 트랜잭션이 성공적으로 '커밋된 후'에 실행됨
    @TransactionalEventListener 
    public void handle(MemberJoinedEvent event) {
        couponService.issue(event.getMemberId());
    }
}
```
-   **장점**: 회원 가입(DB 저장)이 확실히 성공한 뒤에만 쿠폰을 지급합니다. 가입이 롤백되면 이벤트 리스너는 실행되지 않습니다.

---

### 4. **비동기 처리 (`@Async`)로 성능 최적화 🚀**

`@TransactionalEventListener`를 써도 기본적으로는 **동기(Synchronous)** 방식입니다. 즉, 메인 스레드가 커밋 후 리스너 로직까지 다 실행하고 나서야 클라이언트에게 응답을 줍니다. 이메일 발송처럼 시간이 걸리는 작업은 **비동기**로 처리해야 합니다.

```java
@Component
@RequiredArgsConstructor
public class EmailEventListener {

    @Async // 별도의 스레드에서 실행
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleMemberJoined(MemberJoinedEvent event) {
        // 메인 트랜잭션은 이미 끝났고, 별도 스레드에서 이메일 발송
        emailService.send(event.getEmail());
    }
}
```
> **주의**: `@Async`를 사용하려면 `@EnableAsync` 설정이 필요합니다.

---

### 5. **주의사항: `AFTER_COMMIT`에서의 트랜잭션 전파**

`@TransactionalEventListener(phase = AFTER_COMMIT)` 안에서 JPA `save()` 같은 DB 작업을 수행하면 반영되지 않을 수 있습니다.

-   **이유**: 이미 메인 트랜잭션은 커밋되어 닫혔기 때문입니다.
-   **해결**: 리스너 메서드에 `@Transactional(propagation = Propagation.REQUIRES_NEW)`를 붙여서 새로운 트랜잭션을 열어야 합니다.

```java
@Async
@TransactionalEventListener
@Transactional(propagation = Propagation.REQUIRES_NEW) // 새 트랜잭션 필수
public void handleCouponIssue(MemberJoinedEvent event) {
    couponRepository.save(new Coupon(event.getMemberId()));
}
```

---

## 💡 배운 점

1.  **관심사의 분리**: Spring Event를 통해 `MemberService`는 오직 '회원 저장'에만 집중하게 되었고, 부가 기능(알림, 쿠폰)은 리스너로 격리되어 코드의 응집도가 비약적으로 높아졌습니다.
2.  **트랜잭션의 섬세한 제어**: 단순히 로직을 분리하는 것을 넘어, `@TransactionalEventListener`를 통해 **"원자성이 필요한지, 결과적 일관성(Eventual Consistency)으로 충분한지"**를 결정할 수 있다는 점이 매력적이었습니다.
3.  **이벤트 유실 가능성**: Kafka 같은 메시지 큐와 달리 Spring Event는 인메모리 방식입니다. 서버가 트랜잭션 커밋 직후(이벤트 처리 전)에 다운되면 이벤트가 유실될 수 있습니다. 정말 중요한 데이터라면 **Transactional Outbox Pattern**이나 메시지 큐를 고려해야 합니다.

---

## 🔗 참고 자료

-   [Spring Events Documentation](https://docs.spring.io/spring-framework/reference/core/beans/context-introduction.html#context-functionality-events)
-   [Better Application Events in Spring Framework 4.2](https://spring.io/blog/2015/02/11/better-application-events-in-spring-framework-4-2)
-   [Spring @TransactionalEventListener Deep Dive](https://www.baeldung.com/spring-events)