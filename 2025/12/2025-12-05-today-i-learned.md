---
title: "ShedLock: 분산 환경에서 스케줄러(@Scheduled) 중복 실행 방지하기"
date: 2025-12-05
categories: [Spring, Architecture]
tags: [ShedLock, Distributed Scheduler, Spring Boot, Batch, Concurrency, JDBC, TIL]
excerpt: "서버를 여러 대(Scale-out)로 확장했을 때 Spring의 @Scheduled 작업이 모든 서버에서 동시에 실행되는 문제를 해결합니다. ShedLock을 도입하여 외부 저장소(DB, Redis)를 이용해 스케줄 작업을 '한 번만' 실행하도록 제어하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: ShedLock: 분산 환경에서 스케줄러(@Scheduled) 중복 실행 방지하기

## 📚 오늘 학습한 내용

단일 서버에서 잘 돌아가던 `@Scheduled` 작업(예: 매일 아침 정산 메일 발송)이, 트래픽 대응을 위해 서버를 **3대로 스케일 아웃(Scale-out)** 하자마자 **3번씩 실행되는 문제**가 발생했습니다.

Quartz 같은 무거운 스케줄러 프레임워크를 도입하기에는 오버엔지니어링 같고, 단순히 "여러 인스턴스 중 하나만 실행"되게 하고 싶을 때 사용하는 가장 가볍고 확실한 솔루션인 **ShedLock**에 대해 학습했습니다.

---

### 1. **문제 상황: `@Scheduled`의 한계 💣**

Spring의 기본 스케줄러는 애플리케이션 컨텍스트가 로드되면 메모리상에서 동작합니다. 즉, 동일한 애플리케이션이 3개의 컨테이너(Pod)에 배포되면, 3개의 스케줄러가 독립적으로 돌아갑니다.

-   **결과**: 중복 정산, 중복 메일 발송, DB 락 경합 등 심각한 부작용 발생.
-   **해결책**: 모든 서버가 공유하는 **외부 저장소(DB, Redis 등)**에 "내가 지금 이 작업을 하고 있어"라고 깃발(Lock)을 꽂아야 합니다.

---

### 2. **ShedLock이란? 🔒**

ShedLock은 **분산 환경에서 스케줄러가 동시에 실행되지 않도록 잠금(Lock)**을 관리해주는 라이브러리입니다.

-   **특징**:
    -   **Redisson 분산 락과의 차이**: Redisson은 "기다렸다가 락을 얻으면 실행"하는 동시성 제어 목적이지만, ShedLock은 "누가 이미 실행 중이면 **나는 실행하지 않고 건너뛴다(Skip)**"는 스케줄링 제어 목적이 강합니다.
    -   **Lock Provider**: JDBC(MySQL, PostgreSQL), Redis, Mongo, DynamoDB 등 다양한 저장소를 지원합니다.

---

### 3. **Spring Boot에 적용하기 (JDBC 기반)**

가장 일반적인 RDBMS(MySQL)를 잠금 저장소로 사용하는 방식을 구현했습니다.

#### **Step 1: 의존성 추가**
`shedlock-spring`과 Lock Provider인 `shedlock-provider-jdbc-template`을 추가합니다.

```groovy
implementation 'net.javacrumbs.shedlock:shedlock-spring:5.10.0'
implementation 'net.javacrumbs.shedlock:shedlock-provider-jdbc-template:5.10.0'
```

#### **Step 2: Lock 테이블 생성**
ShedLock이 잠금 상태를 기록할 테이블을 DB에 생성해야 합니다.

```sql
CREATE TABLE shedlock (
    name VARCHAR(64) NOT NULL,
    lock_until TIMESTAMP(3) NOT NULL,
    locked_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    locked_by VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
```

#### **Step 3: 설정(Configuration) 활성화**
`LockProvider` 빈을 등록하고 `@EnableSchedulerLock`을 설정합니다.

```java
@Configuration
@EnableScheduling
@EnableSchedulerLock(defaultLockAtMostFor = "PT30S") // 기본 락 유지 시간 (30초)
public class SchedulerConfig {

    @Bean
    public LockProvider lockProvider(DataSource dataSource) {
        return new JdbcTemplateLockProvider(
            JdbcTemplateLockProvider.Configuration.builder()
                .withJdbcTemplate(new JdbcTemplate(dataSource))
                .usingDbTime() // DB 시간을 기준으로 동기화 (서버 간 시간 차이 방지)
                .build()
        );
    }
}
```

#### **Step 4: 스케줄러 메서드에 적용**
`@SchedulerLock` 애노테이션을 사용하여 락을 걸고 싶은 스케줄 작업에 적용합니다.

```java
@Component
@Slf4j
@RequiredArgsConstructor
public class BillingScheduler {

    private final BillingService billingService;

    @Scheduled(cron = "0 0 0 * * *") // 매일 자정 실행
    @SchedulerLock(
        name = "dailyBillingTask", // 1. 락 이름 (shedlock 테이블의 PK)
        lockAtLeastFor = "PT30S",  // 2. 최소 잠금 시간
        lockAtMostFor = "PT10M"    // 3. 최대 잠금 시간 (데드락 방지)
    )
    public void runDailyBilling() {
        log.info("정산 작업을 시작합니다...");
        billingService.process();
        log.info("정산 작업 완료.");
    }
}
```

---

### 4. **핵심 옵션: `lockAtLeastFor` vs `lockAtMostFor`**

ShedLock을 안전하게 쓰려면 이 두 옵션의 차이를 명확히 알아야 합니다.

1.  **`lockAtMostFor` (필수)**: **"혹시 서버가 죽더라도 이 시간이 지나면 락을 풀어줘."**
    -   작업 도중 서버가 비정상 종료(OOM, 배포 등)되어 락을 해제하지 못했을 때, 다른 서버가 영원히 작업을 못 하는 것을 방지하는 안전장치입니다.
    -   **설정 값**: 예상되는 작업 시간보다 훨씬 길게 잡아야 합니다.

2.  **`lockAtLeastFor` (선택, 권장)**: **"작업이 빨리 끝나도 이 시간 동안은 락을 유지해줘."**
    -   서버 간의 시계(Clock)가 미세하게 달라서 발생할 수 있는 중복 실행을 방지합니다.
    -   예를 들어, 작업이 0.1초 만에 끝났는데 서버 B의 시계가 1초 느리다면, 서버 B는 "아직 실행 안 됐네?" 하고 또 실행할 수 있습니다. 이를 막기 위해 최소한의 방어 시간을 둡니다.

---

## 💡 배운 점

1.  **분산 환경의 스케줄링은 공유 자원이 필요하다**: 메모리 기반의 `@Scheduled`는 스케일 아웃 환경에서 위험하며, 반드시 DB나 Redis 같은 외부의 **단일 진실 공급원(SSOT)**을 통해 실행 여부를 제어해야 함을 깨달았습니다.
2.  **ShedLock은 가볍고 강력하다**: Quartz는 기능이 많지만 설정이 복잡하고 무겁습니다. 단순한 cron 작업의 중복 방지 목적이라면 ShedLock이 코드 침투가 적고 훨씬 효율적인 선택지입니다.
3.  **`lockAtMostFor`는 생명선이다**: 만약 이 값을 너무 짧게 설정하면 작업 중에 락이 풀려 중복 실행될 수 있고, 너무 길게 설정하면 서버 다운 시 다음 주기까지 작업이 멈출 수 있습니다. 비즈니스 로직의 수행 시간을 모니터링하여 적절한 값을 튜닝하는 것이 운영 노하우임을 배웠습니다.

---

## 🔗 참고 자료

-   [ShedLock GitHub Repository](https://github.com/lukas-krecan/ShedLock)
-   [Spring Boot with ShedLock (Baeldung)](https://www.baeldung.com/spring-boot-shedlock)
-   [Guide to Spring Scheduled Tasks](https://spring.io/guides/gs/scheduling-tasks/)