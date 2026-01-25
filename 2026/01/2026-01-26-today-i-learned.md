---
title: "서비스 간 강결합 끊기: Spring Events와 @TransactionalEventListener의 트랜잭션 위상(Phase) 제어"
date: 2026-01-26
categories: [Spring, Architecture, Design Pattern]
tags: [Spring Events, EventListener, TransactionalEventListener, Decoupling, Async, Transaction, TIL]
excerpt: "회원 가입 로직에 환영 이메일 발송, 쿠폰 지급, 통계 집계 등 부가 기능이 덕지덕지 붙어 비대해진 서비스 클래스를 리팩토링합니다. Spring Event를 통해 로직을 분리(Decoupling)하고, 트랜잭션 커밋 전/후 시점을 제어하여 '롤백되었는데 이메일이 발송되는' 문제를 해결하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: 서비스 간 강결합 끊기: Spring Events와 @TransactionalEventListener의 트랜잭션 위상(Phase) 제어

## 📚 오늘 학습한 내용

회원 가입(`join`) 메서드 하나에 `이메일 발송`, `가입 축하 쿠폰 지급`, `GA 통계 전송` 로직이 모두 들어있어 코드가 100줄이 넘어가고 있었습니다. 문제는 쿠폰 지급 서버가 잠깐 죽었는데, **핵심 기능인 회원 가입까지 같이 실패(Rollback)**하는 현상이 발생했습니다.

오늘은 **Spring Event**를 도입하여 핵심 로직과 부가 로직의 강결합을 끊어내고, 특히 **트랜잭션 성공 여부에 따라 이벤트 실행 여부를 결정**하는 방법을 학습했습니다.

---

### 1. **기존 코드의 문제점: 강결합(Tight Coupling) 🔗**

```java
@Service
@Transactional
public class MemberService {
    
    // 의존성이 너무 많음
    private final MemberRepository memberRepository;
    private final EmailService emailService;
    private final CouponService couponService;
    private final StatService statService;

    public void join(MemberDto dto) {
        // 1. 핵심 로직
        Member member = memberRepository.save(dto.toEntity());
        
        // 2. 부가 로직 (여기서 에러나면 1번도 롤백됨)
        couponService.issueWelcomeCoupon(member.getId());
        emailService.sendWelcomeMail(member.getEmail());
        statService.recordJoinLog(member.getId());
    }
}
```

---

### 2. **해결책: Spring Event 발행 📢**

서비스는 오직 "회원 가입이 발생했다"라는 사실(Event)만 던지고, 누가 그걸 받아서 처리하는지는 신경 쓰지 않게 만듭니다.

#### **Step 1: 이벤트 클래스 정의**
```java
@Getter
@AllArgsConstructor
public class MemberJoinedEvent {
    private Long memberId;
    private String email;
}
```

#### **Step 2: 이벤트 발행 (`ApplicationEventPublisher`)**
```java
@Service
@Transactional
@RequiredArgsConstructor
public class MemberService {

    private final MemberRepository memberRepository;
    private final ApplicationEventPublisher eventPublisher; // 의존성 하나로 축소

    public void join(MemberDto dto) {
        Member member = memberRepository.save(dto.toEntity());
        
        // 이벤트 발행
        eventPublisher.publishEvent(new MemberJoinedEvent(member.getId(), member.getEmail()));
    }
}
```

---

### 3. **심화: `@EventListener` vs `@TransactionalEventListener`**

이벤트를 받는 리스너를 구현할 때, 단순히 `@EventListener`를 쓰면 **동기(Synchronous)**로 동작하며 **같은 트랜잭션**으로 묶입니다. 즉, 이메일 발송에서 에러가 나면 여전히 회원 가입이 롤백됩니다.

이때 **`@TransactionalEventListener`**를 사용하면 트랜잭션 단계(Phase)에 따라 실행 시점을 정밀하게 제어할 수 있습니다.

#### **Case 1: 커밋 후에만 실행 (`AFTER_COMMIT`)**
"가입이 확실히 DB에 저장된 후에만 이메일을 보내고 싶다(가입 실패하면 이메일도 안 가야 함)"는 경우입니다.



```java
@Component
@RequiredArgsConstructor
@Slf4j
public class MemberEventListener {

    private final EmailService emailService;

    // phase 기본값은 AFTER_COMMIT (트랜잭션 성공 시에만 실행)
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void sendEmail(MemberJoinedEvent event) {
        log.info("회원 가입 커밋 완료. 이메일 발송 시작: {}", event.getEmail());
        emailService.sendWelcomeMail(event.getEmail());
    }
}
```

#### **Case 2: 커밋 전 실행 (`BEFORE_COMMIT`)**
"쿠폰 지급은 회원 가입과 한 몸이어야 한다(쿠폰 실패하면 가입도 취소)"는 경우입니다.

```java
@Component
@RequiredArgsConstructor
public class CouponEventListener {

    private final CouponService couponService;

    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
    public void issueCoupon(MemberJoinedEvent event) {
        couponService.issueWelcomeCoupon(event.getMemberId());
    }
}
```

---

### 4. **주의사항: `AFTER_COMMIT`에서의 DB 쓰기 ⚠️**

가장 많이 하는 실수 중 하나입니다. `AFTER_COMMIT` 단계에서는 이미 DB 커밋이 끝났기 때문에, 리스너 내부에서 `repository.save()`를 호출해도 **DB에 반영되지 않거나 에러**가 발생합니다.

* **해결책**: 리스너 메서드에 **`@Transactional(propagation = Propagation.REQUIRES_NEW)`**를 붙여서 새로운 트랜잭션을 시작해야 합니다.

```java
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
@Transactional(propagation = Propagation.REQUIRES_NEW) // 새 트랜잭션 필수
public void saveJoinLog(MemberJoinedEvent event) {
    // 커밋이 끝난 후 실행되므로, 여기서 insert 하려면 새 트랜잭션이 필요함
    historyRepository.save(new MemberHistory(event.getMemberId(), "JOIN"));
}
```

---

### 5. **비동기 처리 (`@Async`)**

이메일 발송처럼 시간이 오래 걸리는 작업은 `@Async`를 붙여서 아예 별도 스레드로 분리해야, 회원 가입 API 응답 속도를 늦추지 않습니다.

```java
@Async // 별도 스레드 실행
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
public void sendEmailAsync(MemberJoinedEvent event) {
    // ...
}
```

---

## 💡 배운 점

1.  **관심사의 분리**: 코드를 리팩토링하고 나니 `MemberService`에는 순수하게 회원 정보 저장 로직만 남았습니다. 코드가 깔끔해지고 테스트하기 훨씬 수월해졌습니다.
2.  **트랜잭션의 생명주기**: 단순히 `@Transactional`만 붙이는 게 아니라, "이 로직이 커밋 전에 실행되어야 하는가, 후에 실행되어야 하는가?"를 고민하게 되었습니다. 특히 `AFTER_COMMIT`에서 롤백된 데이터가 부활하지 않도록 제어하는 것이 중요함을 깨달았습니다.
3.  **확장성**: 나중에 "가입 시 SMS도 보내주세요"라는 요구사항이 와도, `MemberService`를 수정할 필요 없이 리스너 하나만 추가(`SmsEventListener`)하면 되는 구조가 되어 유지보수성이 비약적으로 상승했습니다.

---

## 🔗 참고 자료

-   [Spring Events Documentation](https://docs.spring.io/spring-framework/reference/core/beans/context-introduction.html#context-functionality-events)
-   [Better Application Events with @TransactionalEventListener](https://www.baeldung.com/spring-events)
-   [Spring Transaction Synchronization](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/support/TransactionSynchronization.html)