---
title: "Scale-out 환경의 @Scheduled 중복 실행 문제: ShedLock으로 분산 스케줄링 제어하기"
date: 2026-01-10
categories: [Spring, Architecture, Distributed System]
tags: [Spring Boot, ShedLock, Scheduled, Distributed Lock, Scale-out, Cron, TIL]
excerpt: "서버를 여러 대로 확장(Scale-out)했을 때, Spring의 @Scheduled 작업이 모든 서버에서 중복 실행되는 문제를 해결합니다. 별도의 스케줄러 서버를 구축하지 않고, ShedLock 라이브러리와 DB를 활용하여 클러스터 내에서 단 하나의 인스턴스만 작업을 수행하도록 제어하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Scale-out 환경의 @Scheduled 중복 실행 문제: ShedLock으로 분산 스케줄링 제어하기

## 📚 오늘 학습한 내용

단일 서버에서 잘 돌던 `@Scheduled` 배치 작업이, 트래픽 대응을 위해 서버를 3대로 증설(Scale-out)하자마자 **3번씩 중복 실행되는 사고**가 발생했습니다. 이로 인해 이메일이 3통씩 발송되고, 정산 데이터가 꼬이는 문제가 생겼습니다.

Quartz 같은 무거운 스케줄러 프레임워크나 별도의 배치 서버를 구축하기에는 오버엔지니어링인 상황. 오늘은 가볍게 애노테이션 하나로 **분산 환경에서 스케줄 중복 실행을 방지**해주는 **ShedLock** 라이브러리를 적용했습니다.

---

### 1. **ShedLock이란? 🔒**

ShedLock은 예정된 작업이 동시에 여러 번 실행되지 않도록 **잠금(Lock)**을 관리하는 라이브러리입니다.
-   **동작 원리**: 작업 시작 전 DB(혹은 Redis, Mongo)의 특정 테이블에 "내가 이 작업 시작했음"이라고 깃발(Lock)을 꽂습니다. 다른 서버가 깃발을 보고 "아, 이미 누가 하고 있네" 하고 실행을 건너뜁니다(Skip).
-   **특징**: **Quartz**는 클러스터링과 Fail-over, 미실행 작업 재실행 등을 지원하지만 무겁습니다. **ShedLock**은 단순히 **"중복 실행 방지"**에만 초점을 맞춘 가벼운 도구입니다.

---

### 2. **Spring Boot에 적용하기 (JDBC 기반)**

#### **Step 1: 의존성 추가**
ShedLock 코어와 Lock Provider(여기서는 JDBC)가 필요합니다.

```groovy
implementation 'net.javacrumbs.shedlock:shedlock-spring:5.10.0'
implementation 'net.javacrumbs.shedlock:shedlock-provider-jdbc-template:5.10.0'
```

#### **Step 2: Lock 테이블 생성**
ShedLock이 잠금 정보를 기록할 테이블을 DB에 만들어야 합니다.

```sql
CREATE TABLE shedlock (
    name VARCHAR(64) NOT NULL, -- 락 이름 (Primary Key)
    lock_until TIMESTAMP(3) NOT NULL, -- 언제까지 잠글 것인가
    locked_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    locked_by VARCHAR(255) NOT NULL, -- 누가 잠갔는가 (hostname 등)
    PRIMARY KEY (name)
);
```

#### **Step 3: 설정 클래스 (`@EnableSchedulerLock`)**
`LockProvider`를 빈으로 등록하고 스케줄러 락을 활성화합니다.

```java
@Configuration
@EnableScheduling
@EnableSchedulerLock(defaultLockAtMostFor = "10m") // 기본 락 유지 시간 (서버 다운 대비)
public class SchedulerConfig {

    @Bean
    public LockProvider lockProvider(DataSource dataSource) {
        return new JdbcTemplateLockProvider(
            JdbcTemplateLockProvider.Configuration.builder()
                .withJdbcTemplate(new JdbcTemplate(dataSource))
                .usingDbTime() // DB 시간 기준 (서버 간 시간 동기화 문제 해결)
                .build()
        );
    }
}
```

#### **Step 4: 스케줄 메서드에 적용 (`@SchedulerLock`)**

```java
@Component
@Slf4j
public class SettlementTask {

    @Scheduled(cron = "0 0 0 * * *") // 매일 자정 실행
    @SchedulerLock(
        name = "DailySettlementTask", // 락 이름 (shedlock 테이블의 PK)
        lockAtMostFor = "10m",    // (필수) 최대 잠금 시간: 작업이 죽어도 10분 뒤엔 락 해제
        lockAtLeastFor = "1m"     // (선택) 최소 잠금 시간: 작업이 1초 만에 끝나도 1분간은 락 유지
    )
    public void runSettlement() {
        log.info("정산 작업 시작 - 이 로그는 클러스터 중 한 서버에서만 찍혀야 함");
        // ... 비즈니스 로직 ...
    }
}
```

---

### 3. **핵심 파라미터: `lockAtMostFor` vs `lockAtLeastFor`**

ShedLock 설정에서 가장 헷갈리고 중요한 두 가지 옵션입니다.

1.  **`lockAtMostFor` (Deadlock 방지용 안전장치)**
    -   서버 A가 락을 잡고 작업을 수행하다가 **갑자기 전원이 꺼져버렸습니다(Crash).**
    -   락을 해제하는 코드가 실행되지 않았으므로, DB에는 영원히 락이 걸려있게 됩니다.
    -   이를 막기 위해 "작업이 안 끝나도 이 시간이 지나면 강제로 락을 푼다"는 설정입니다.
    -   **주의**: 반드시 **예상되는 작업 소요 시간보다 길게** 잡아야 합니다.

2.  **`lockAtLeastFor` (아주 짧은 작업 방지용)**
    -   서버 A와 서버 B의 시계가 미세하게 다를 수 있습니다.
    -   서버 A가 0.1초 만에 작업을 끝내고 락을 풀어버리면, 시계가 약간 느린 서버 B가 "어? 락 없네?" 하고 또 실행할 수 있습니다.
    -   이를 막기 위해 "작업이 아무리 빨리 끝나도 최소 이 시간 동안은 락을 쥐고 있어라"는 설정입니다.

---

### 4. **Redis Provider와의 차이점**

JDBC 대신 Redis를 사용할 수도 있습니다. (`shedlock-provider-redis-spring`)
-   **장점**: DB에 부하를 주지 않고 빠릅니다. TTL(Time To Live) 기능을 활용해 관리가 쉽습니다.
-   **단점**: Redis 데이터가 휘발되면 락 정보도 날아갈 수 있습니다. (물론 스케줄 락은 잠깐 날아가도 치명적이지 않은 경우가 많음)
-   **결론**: 스케줄 작업이 DB 트랜잭션과 강하게 엮여있다면 JDBC, 그 외 가벼운 작업이나 DB 부하가 걱정된다면 Redis가 유리합니다.

---

## 💡 배운 점

1.  **멱등성의 중요성**: ShedLock을 쓴다고 100% 중복 실행이 방지되는 것은 아닙니다(DB 연결 끊김 등 예외 상황). 따라서 배치 로직 자체도 "두 번 실행되어도 결과는 같도록(Idempotent)" 설계하는 것이 최후의 보루임을 잊지 말아야 합니다.
2.  **서버 시간 동기화**: 분산 환경에서 시간(Clock)은 믿을 수 없는 존재입니다. `usingDbTime()` 옵션을 사용하여 애플리케이션 서버 시간이 아닌 **DB 서버 시간을 기준**으로 락을 관리하는 것이 훨씬 안전하다는 것을 배웠습니다.
3.  **간결함의 미학**: 별도의 배치 서버(Jenkins, Airflow 등)를 구축하면 관리 포인트가 늘어납니다. 비즈니스 로직과 스케줄링이 밀접하게 연관된 간단한 작업은 ShedLock으로 코드 레벨에서 해결하는 것이 유지보수성과 복잡도 관리 면에서 효율적입니다.

---

## 🔗 참고 자료

-   [ShedLock GitHub Repository](https://github.com/lukas-krecan/ShedLock)
-   [Spring Boot Scheduling Guide](https://spring.io/guides/gs/scheduling/)
-   [Distributed Locks with Redis](https://redis.io/docs/manual/patterns/distributed-locks/)