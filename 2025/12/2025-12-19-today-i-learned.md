---
title: "Redis 분산 락(Distributed Lock): Redisson으로 동시성 문제 해결하고 스핀 락 부하 줄이기"
date: 2025-12-19
categories: [Spring, Redis, Concurrency]
tags: [Redis, Redisson, Distributed Lock, AOP, SpEL, Concurrency Control, TIL]
excerpt: "분산 환경에서 동시성 제어를 위해 Java의 synchronized 대신 Redis 분산 락을 도입합니다. 스핀 락 방식인 Lettuce 대신 Pub/Sub 기반의 Redisson을 사용하여 Redis 부하를 줄이고, AOP를 활용해 비즈니스 로직과 락 처리 로직을 깔끔하게 분리하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Redis 분산 락(Distributed Lock): Redisson으로 동시성 문제 해결하고 스핀 락 부하 줄이기

## 📚 오늘 학습한 내용

단일 서버에서는 `synchronized` 키워드로 스레드 동시성을 제어할 수 있지만, 서버가 여러 대로 늘어나는 순간(Scale-out) 이 방법은 무용지물이 됩니다.

이를 해결하기 위해 Redis를 활용한 분산 락을 도입하게 되는데, Spring Data Redis의 기본 클라이언트인 **Lettuce**를 사용하면 락을 획득할 때까지 계속 Redis에 요청을 보내는 **스핀 락(Spin Lock)** 구조 때문에 Redis에 엄청난 트래픽 부하를 줄 수 있습니다.

오늘은 이러한 문제를 해결하는 **Redisson** 라이브러리와, 이를 **AOP**로 추상화하여 비즈니스 로직 침투 없이 깔끔하게 적용하는 방법을 학습했습니다.

---

### 1. **Lettuce vs. Redisson**

| 특징 | **Lettuce (Spin Lock)** | **Redisson (Pub/Sub)** |
| :--- | :--- | :--- |
| **방식** | 락을 얻을 때까지 `SETNX` 명령어를 무한 반복 전송 (Polling) | 락이 해제되면 채널을 통해 알림을 받아 그때 락 획득 시도 (Event-Driven) |
| **장점** | 별도 라이브러리 없이 Spring Data Redis 기본 포함 | Redis 부하가 적고, 타임아웃/자동 만료 등 기능 강력함 |
| **단점** | Redis에 부하를 줌, 재시도 로직 직접 구현 필요 | 별도 의존성 추가 필요, 구현 난이도 약간 있음 |

> 실무에서는 동시 요청이 많은 선착순 이벤트나 재고 차감 로직에는 **Redisson**이 사실상의 표준입니다.

---

### 2. **Spring Boot에 Redisson 적용하기**

#### **Step 1: 의존성 추가**
```groovy
implementation 'org.redisson:redisson-spring-boot-starter:3.27.0'
```

#### **Step 2: 커스텀 애노테이션 정의 (`@DistributedLock`)**
비즈니스 로직마다 `rLock.tryLock()`... `finally { rLock.unlock() }` 코드를 반복하는 것은 지저분합니다. AOP로 묶어내기 위해 애노테이션을 만듭니다.

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface DistributedLock {
    
    // 락의 키값 (SpEL 지원, 예: "#orderId")
    String key();

    // 락 획득 대기 시간 (기본 5초)
    long waitTime() default 5000L;

    // 락 점유 시간 (기본 3초)
    long leaseTime() default 3000L;
    
    // 시간 단위
    TimeUnit timeUnit() default TimeUnit.MILLISECONDS;
}
```

#### **Step 3: AOP Aspect 구현**
핵심은 **트랜잭션과의 순서**입니다. 반드시 **"락 획득 -> 트랜잭션 시작 -> 트랜잭션 커밋 -> 락 해제"** 순서가 되어야 동시성 이슈가 없습니다.

```java
@Aspect
@Component
@RequiredArgsConstructor
@Slf4j
public class DistributedLockAop {

    private final RedissonClient redissonClient;
    private final AopForTransaction aopForTransaction; // 별도 클래스로 분리 (Self-invocation 방지)

    @Around("@annotation(com.example.common.DistributedLock)")
    public Object lock(ProceedingJoinPoint joinPoint) throws Throwable {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        DistributedLock distributedLock = signature.getMethod().getAnnotation(DistributedLock.class);
        
        // SpEL 파서로 키값 생성 (생략: CustomSpringELParser 사용)
        String key = REDISSON_LOCK_PREFIX + CustomSpringELParser.getDynamicValue(signature.getParameterNames(), joinPoint.getArgs(), distributedLock.key());

        RLock rLock = redissonClient.getLock(key);

        try {
            // 1. 락 획득 시도 (waitTime 동안 대기, 획득 후 leaseTime 지나면 자동 해제)
            boolean available = rLock.tryLock(distributedLock.waitTime(), distributedLock.leaseTime(), distributedLock.timeUnit());
            
            if (!available) {
                log.warn("Failed to get lock: {}", key);
                return false; // 혹은 예외 발생
            }

            // 2. 비즈니스 로직 수행 (별도 트랜잭션으로 실행)
            return aopForTransaction.proceed(joinPoint);
            
        } catch (InterruptedException e) {
            throw new InterruptedException();
        } finally {
            // 3. 락 해제 (반드시 획득한 스레드만 해제 가능)
            if (rLock.isLocked() && rLock.isHeldByCurrentThread()) {
                rLock.unlock();
            }
        }
    }
}
```

#### **Step 4: 트랜잭션 분리 (`AopForTransaction`)**
락 내부에서 실행될 비즈니스 로직은 반드시 트랜잭션 커밋이 완료된 후에 락이 풀려야 합니다. 이를 위해 별도의 컴포넌트를 사용합니다.

```java
@Component
public class AopForTransaction {

    @Transactional(propagation = Propagation.REQUIRES_NEW) // 부모 트랜잭션 유무와 상관없이 새 트랜잭션
    public Object proceed(ProceedingJoinPoint joinPoint) throws Throwable {
        return joinPoint.proceed();
    }
}
```

---

### 3. **실제 서비스 적용**

이제 서비스 코드에서는 복잡한 락 로직 없이 애노테이션 한 줄로 동시성을 제어할 수 있습니다.

```java
@Service
@RequiredArgsConstructor
public class TicketService {

    private final TicketRepository ticketRepository;

    // key에 SpEL 사용: 파라미터 ticketId를 락 키로 사용
    @DistributedLock(key = "#ticketId", waitTime = 3000, leaseTime = 2000)
    public void decreaseTicket(Long ticketId) {
        // 이미 락이 걸려있으므로, 안전하게 재고 조회 및 차감
        Ticket ticket = ticketRepository.findById(ticketId).orElseThrow();
        ticket.decrease();
    }
}
```

---

## 💡 배운 점

1.  **Redisson의 우아함**: Lettuce로 직접 구현할 때는 `while`문 돌면서 `Thread.sleep` 거는 등 코드가 지저분했는데, Redisson은 `tryLock` 메서드 하나로 대기/만료/획득을 깔끔하게 처리해주어 생산성이 크게 향상되었습니다.
2.  **트랜잭션 범위의 함정**: 가장 많이 하는 실수가 `@Transactional` 메서드 위에 AOP를 걸어서, **"DB 커밋보다 락 해제가 먼저 일어나는"** 상황입니다. 이 틈새 시간에 다른 스레드가 들어와서 변경 전 데이터를 읽으면 동시성 처리가 실패합니다. `AopForTransaction`처럼 계층을 나누어 **락 범위 > 트랜잭션 범위**를 보장하는 것이 핵심임을 깨달았습니다.
3.  **Lease Time의 중요성**: 만약 로직 수행 중에 서버가 죽어서 `finally` 블록의 `unlock()`이 실행되지 않는다면? `leaseTime` 설정을 통해 일정 시간 후 Redis가 알아서 락을 풀어주도록 안전장치를 걸어두는 것이 필수적입니다.

---

## 🔗 참고 자료

-   [Redisson Official Docs](https://github.com/redisson/redisson/wiki/8.-Distributed-locks-and-synchronizers)
-   [Spring Boot AOP Guide](https://docs.spring.io/spring-framework/reference/core/aop.html)
-   [Concurrency Control in Distributed Systems](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)