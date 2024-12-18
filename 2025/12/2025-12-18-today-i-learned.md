---
title: "HikariCP Deadlock: 부하 테스트에서 멈춰버린 서버와 적절한 Pool Size 공식"
date: 2025-12-18
categories: [Spring, Database, Performance]
tags: [HikariCP, JDBC, Connection Pool, Deadlock, Performance Tuning, Transaction, TIL]
excerpt: "부하 테스트 중 서버가 응답을 멈추는 현상의 원인이 '데이터베이스 데드락'이 아닌 '애플리케이션 레벨의 커넥션 풀 데드락'일 수 있음을 학습합니다. Nested Transaction(@Transactional(REQUIRES_NEW)) 사용 시 발생하는 커넥션 고갈 문제와 이를 예방하기 위한 적절한 Maximum Pool Size 공식을 알아봅니다."
author_profile: true
---

# Today I Learned: HikariCP Deadlock: 부하 테스트에서 멈춰버린 서버와 적절한 Pool Size 공식

## 📚 오늘 학습한 내용

서비스 오픈 전 nGrinder로 부하 테스트를 진행하던 중, 특정 시점부터 서버가 요청을 전혀 처리하지 못하고 **Time out**만 뱉어내는 현상을 발견했습니다. DB CPU나 메모리는 여유로운데 애플리케이션만 멈춘 상황. 스레드 덤프를 분석해 보니 모든 스레드가 DB 커넥션을 얻기 위해 대기(`HikariCP getConnection()`)하고 있었습니다.

오늘은 Spring Boot의 기본 커넥션 풀인 **HikariCP**에서 발생할 수 있는 치명적인 **Deadlock** 시나리오와, 이를 방지하기 위한 **Pool Size 공식**을 학습했습니다.

---

### 1. **HikariCP Deadlock이란? 💀**

이 데드락은 DB 엔진(MySQL, Oracle) 내부의 Row Lock/Table Lock과는 다릅니다. 애플리케이션 내부에서 **제한된 자원(Connection Pool)을 서로 기다리다가** 발생하는 교착 상태입니다.

#### **발생 시나리오: Nested Transaction**
가장 흔한 원인은 부모 트랜잭션 안에서 자식 트랜잭션을 **`REQUIRES_NEW`**로 호출할 때 발생합니다.



1.  **Thread A**가 작업 시작. (커넥션 1개 점유 - **Parent Connection**)
2.  작업 중 `REQUIRES_NEW` 메서드 호출. (새로운 커넥션 필요)
3.  **Thread A**는 부모 커넥션을 쥔 채로, 풀에게서 두 번째 커넥션을 요청하고 대기합니다.
4.  만약 부하가 몰려 모든 스레드(Thread A~Z)가 1번 상태(부모 커넥션 점유)라면?
5.  풀에는 남은 커넥션이 없고, 모든 스레드는 두 번째 커넥션을 기다립니다. 아무도 커넥션을 반납하지 않으므로 **영원히 멈춥니다.**

---

### 2. **코드로 재현하기**

```java
@Service
@RequiredArgsConstructor
public class ParentService {

    private final ChildService childService;
    private final MemberRepository memberRepository;

    @Transactional // 1. 부모 트랜잭션 시작 (Connection A 획득)
    public void process() {
        memberRepository.save(new Member("parent"));
        
        // 2. 자식 트랜잭션 호출 (여기서 대기 발생 가능성)
        childService.processChild(); 
    }
}

@Service
@RequiredArgsConstructor
public class ChildService {

    private final LogRepository logRepository;

    @Transactional(propagation = Propagation.REQUIRES_NEW) // 3. 별도 커넥션 요구 (Connection B 필요)
    public void processChild() {
        logRepository.save(new Log("child log"));
    }
}
```

만약 `maximum-pool-size`가 **10**이고, 동시에 **10개**의 요청이 `ParentService.process()`에 들어오면?
-   10개의 스레드가 각각 Connection A를 하나씩 가져갑니다. (풀 잔여량: 0)
-   10개의 스레드가 동시에 `childService.processChild()`를 호출하며 Connection B를 요청합니다.
-   잔여량이 0이므로 무한 대기 -> **Deadlock 발생**.

---

### 3. **해결책: 적절한 Pool Size 공식 📐**

HikariCP 공식 문서와 하이버네이트 전문가들은 이 문제를 피하기 위한 Pool Size 공식을 제시합니다.

$$
PoolSize = T_n \times (C_m - 1) + 1
$$

-   **$T_n$**: 전체 스레드 개수 (Tomcat의 `server.tomcat.threads.max`와는 다름, 동시에 DB 작업을 수행할 수 있는 최대 스레드 수)
-   **$C_m$**: 하나의 작업(Task)에서 동시에 필요한 최대 커넥션 수

#### **계산 예시**
-   Tomcat Max Threads: 200 (무의미, DB 동시 접근 스레드가 중요)
-   하나의 요청에서 `REQUIRES_NEW`를 한 번 써서, 동시에 최대 **2개**의 커넥션을 쓴다면? ($C_m = 2$)
-   현재 서버가 감당할 동시 트랜잭션 처리량 목표가 **10개**라면? ($T_n = 10$)

$$
PoolSize = 10 \times (2 - 1) + 1 = 11
$$

즉, 최소 **11개** 이상의 커넥션 풀을 확보해야 10개의 요청이 동시에 와도 데드락에 걸리지 않습니다. (최악의 경우 10명이 1개씩 가져가도 1개가 남아서, 누군가는 자식 트랜잭션을 완료하고 반납할 수 있기 때문입니다.)

---

### 4. **`application.yml` 튜닝**

데드락 방지뿐만 아니라 성능 최적화를 위한 설정입니다.

```yaml
spring:
  datasource:
    hikari:
      # 1. Pool Size 설정 (공식에 따라 넉넉하게 산정)
      maximum-pool-size: 20 
      
      # 2. 커넥션 획득 대기 시간 (기본 30초 -> 3~5초 권장)
      # 너무 오래 기다리게 하느니 빨리 에러를 뱉고 Fail-fast 하는 게 나음
      connection-timeout: 3000 
      
      # 3. 커넥션 유효성 검사 쿼리 (MySQL 등 JDBC 4 지원 드라이버는 생략 가능하지만 명시 권장)
      # connection-test-query: SELECT 1
      
      # 4. 커넥션 최대 수명 (기본 30분)
      # DB의 wait_timeout보다 2~3분 짧게 설정하여 DB가 끊기 전에 먼저 갱신
      max-lifetime: 1800000 
```

---

## 💡 배운 점

1.  **커넥션 풀은 "다다익선"이 아니다**: 커넥션이 많으면 메모리를 많이 먹고, DB 입장에서 컨텍스트 스위칭 비용이 증가합니다. 하지만 `REQUIRES_NEW`를 쓴다면 **"최소한의 안전마진"** 밑으로 설정했을 때 시스템이 멈출 수 있다는 사실을 알게 되었습니다.
2.  **`REQUIRES_NEW` 사용의 대가**: 로그 저장 등을 위해 독립 트랜잭션을 사용할 때, 단순히 트랜잭션이 분리된다는 논리적 관점뿐만 아니라 **"물리적 커넥션을 하나 더 먹는다"**는 인프라적 관점을 반드시 고려해야 합니다.
3.  **Fail Fast**: `connection-timeout` 기본값인 30초는 웹 서비스에서 영겁의 시간입니다. 사용자에게 30초 동안 뱅글뱅글 도는 화면을 보여주느니, 3초 만에 "접속량이 많습니다"를 띄워주는 것이 훨씬 나은 UX이자 시스템 보호 전략임을 튜닝하며 깨달았습니다.

---

## 🔗 참고 자료

-   [HikariCP Deadlock Simulation](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing)
-   [Hypersistence - Pooling Sizing](https://vladmihalcea.com/pool-size-calculation-connection-pool/)
-   [Spring Boot HikariCP Configuration](https://docs.spring.io/spring-boot/docs/current/reference/html/howto.html#howto.data-access.configure-custom-datasource)