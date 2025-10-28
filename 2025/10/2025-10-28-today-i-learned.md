---
title: "MySQL 데이터베이스 복제(Replication)와 읽기/쓰기 분리"
date: 2025-10-28
categories: [Database, DevOps]
tags: [MySQL, Replication, Read/Write Splitting, High Availability, Performance Tuning, TIL]
excerpt: "애플리케이션의 읽기 성능을 스케일 아웃(Scale-out)하기 위한 데이터베이스 복제(Replication)의 기본 원리를 학습합니다. MySQL의 Primary-Secondary(Master-Slave) 복제 구성과 Spring Boot에서 읽기/쓰기(Read/Write) 트래픽을 분리하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: MySQL 데이터베이스 복제(Replication)와 읽기/쓰기 분리

## 📚 오늘 학습한 내용

서비스 규모가 커지면서 데이터베이스(DB)에 가해지는 부하가 증가하면, 가장 먼저 병목 현상이 발생하는 지점은 대부분 **읽기(SELECT) 작업**입니다. 쓰기(INSERT, UPDATE, DELETE) 작업보다 읽기 작업이 압도적으로 많기 때문입니다.

서버(WAS)는 수평 확장(Scale-out)하기 쉽지만, DB는 수평 확장이 매우 까다롭습니다. 오늘은 이 문제를 해결하는 가장 보편적이고 강력한 기술인 **데이터베이스 복제(Replication)**와 이를 활용한 **읽기/쓰기 분리(Read/Write Splitting)**에 대해 학습했습니다.

---

### 1. **데이터베이스 복제(Replication)란? 🔄**

**복제**는 하나의 데이터베이스(원본, **Primary**)의 데이터를 다른 여러 데이터베이스(복제본, **Secondary**)로 실시간으로 복사하는 기술입니다.

-   **Primary (Master)**: **쓰기** 작업을 처리하는 원본 DB. 모든 데이터 변경은 반드시 Primary를 통해서만 이루어집니다.
-   **Secondary (Slave/Replica)**: Primary로부터 변경 사항을 복제받아 데이터를 동기화하는 복제본 DB. **읽기** 작업을 전담합니다.



#### **MySQL 복제 동작 원리 (Async)**
1.  **[Primary]**: 데이터에 `UPDATE`나 `INSERT` 같은 변경이 발생하면, 이 변경 이력을 **Binary Log (Binlog)**라는 파일에 기록합니다.
2.  **[Secondary]**: Secondary 서버의 **I/O 스레드**가 Primary 서버에 접속하여, Binlog의 변경 사항을 요청하고 자신의 **Relay Log**라는 파일에 복사해옵니다.
3.  **[Secondary]**: Secondary 서버의 **SQL 스레드**가 Relay Log를 순차적으로 읽어, 자신의 데이터베이스에 똑같이 적용(실행)합니다.

이 과정을 통해 Secondary 서버는 Primary 서버의 데이터를 거의 실시간으로 따라가게 됩니다.

---

### 2. **읽기/쓰기 분리 (Read/Write Splitting) ↔️**

복제 구성을 마쳤다면, 애플리케이션은 이 환경을 어떻게 활용해야 할까요? 바로 **애플리케이션 레벨에서 쿼리를 분리**하는 것입니다.

-   **쓰기 작업 (`@Transactional`)**: `INSERT`, `UPDATE`, `DELETE` 등 데이터 변경이 발생하는 모든 작업은 **Primary DB**로 보내야 합니다.
-   **읽기 작업 (`@Transactional(readOnly = true)`)**: 단순 조회(`SELECT`) 작업은 **Secondary DB**로 보내어 부하를 분산시킵니다.

#### **Spring Boot에서 구현하기**
Spring은 `AbstractRoutingDataSource`라는 추상 클래스를 제공하여, 트랜잭션의 속성(e.g., `readOnly`)에 따라 동적으로 다른 `DataSource`를 선택할 수 있게 해줍니다.

**1. `DataSource` 설정**
`application.yml`에 Primary와 Secondary DB의 접속 정보를 모두 정의합니다.

```yaml
spring:
  datasource:
    primary:
      driver-class-name: com.mysql.cj.jdbc.Driver
      jdbc-url: jdbc:mysql://primary-db-host:3306/mydb
      username: user
      password: pw
    secondary:
      driver-class-name: com.mysql.cj.jdbc.Driver
      jdbc-url: jdbc:mysql://secondary-db-host:3306/mydb
      username: user
      password: pw
```

**2. `RoutingDataSource` 구현**
현재 트랜잭션이 `readOnly`인지 확인하여 적절한 DB를 선택(Route)하는 로직을 구현합니다.

```java
public class RoutingDataSource extends AbstractRoutingDataSource {

    @Override
    protected Object determineCurrentLookupKey() {
        // 현재 트랜잭션이 'readOnly' 속성을 가지고 있는지 확인
        boolean isReadOnly = TransactionSynchronizationManager.isCurrentTransactionReadOnly();
        
        if (isReadOnly) {
            log.info("Routing to Secondary DB (ReadOnly)");
            return "secondary";
        } else {
            log.info("Routing to Primary DB (ReadWrite)");
            return "primary";
        }
    }
}
```

**3. `DataSource` 빈 설정**
Primary, Secondary `DataSource` 빈을 생성하고, 이 둘을 `RoutingDataSource`로 감싸서 최종 `DataSource` 빈으로 등록합니다.
```java
@Configuration
public class DataSourceConfig {

    @Bean
    @ConfigurationProperties(prefix = "spring.datasource.primary")
    public DataSource primaryDataSource() {
        return DataSourceBuilder.create().build();
    }

    @Bean
    @ConfigurationProperties(prefix = "spring.datasource.secondary")
    public DataSource secondaryDataSource() {
        return DataSourceBuilder.create().build();
    }

    @Bean
    public DataSource routingDataSource() {
        RoutingDataSource routingDataSource = new RoutingDataSource();
        
        Map<Object, Object> dataSources = new HashMap<>();
        dataSources.put("primary", primaryDataSource());
        dataSources.put("secondary", secondaryDataSource());
        
        routingDataSource.setTargetDataSources(dataSources);
        routingDataSource.setDefaultTargetDataSource(primaryDataSource()); // 기본값은 Primary
        
        return routingDataSource;
    }

    // JPA가 routingDataSource를 사용하도록 설정
    @Bean
    @Primary
    public DataSource dataSource() {
        // 'lazyConnectionDataSourceProxy'로 감싸서 
        // 트랜잭션이 시작될 때 룩업 키(primary/secondary)가 결정되도록 지연시킴
        return new LazyConnectionDataSourceProxy(routingDataSource());
    }
}
```

**4. 서비스 레이어에서 활용**
이제 서비스 레이어에서 `@Transactional`의 `readOnly` 속성만으로 쿼리 분기가 가능해집니다.

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;

    // readOnly = true -> Secondary DB로 요청
    @Transactional(readOnly = true) 
    public UserDto findUserById(Long id) {
        User user = userRepository.findById(id).orElseThrow();
        return UserDto.from(user);
    }

    // readOnly = false (기본값) -> Primary DB로 요청
    @Transactional 
    public void updateUserEmail(Long id, String newEmail) {
        User user = userRepository.findById(id).orElseThrow();
        user.changeEmail(newEmail); // Dirty Checking
    }
}
```

---

### 3. **주의사항: 복제 지연 (Replication Lag)**

복제는 비동기(Async)로 동작하는 경우가 많아, Primary에서 발생한 변경이 Secondary에 반영되기까지 아주 짧은 **지연 시간(Lag)**이 발생할 수 있습니다.

-   **시나리오**:
    1.  사용자가 글을 작성 (`INSERT`, Primary DB)
    2.  성공 응답을 받고, 즉시 '내 글 목록' 페이지로 이동 (`SELECT`, Secondary DB)
    3.  **문제**: 1번의 `INSERT`가 아직 Secondary DB에 복제되기 전이라면, 2번의 `SELECT`는 빈 목록을 반환합니다. (사용자: "방금 쓴 내 글 어디 갔지?")

-   **해결책**:
    -   이런 경우(CQS - Command Query Separation), '내 글 목록' 조회는 `readOnly=true`를 걸지 않고 Primary DB에서 직접 읽어오도록 강제하여 데이터 정합성을 맞춥니다.
    -   혹은, CQRS 패턴을 도입하여 쓰기/조회 모델을 더 명확히 분리합니다.

---

## 💡 배운 점

1.  **Scale-Up vs. Scale-Out**: DB 성능 문제에 부딪혔을 때, 무작정 더 비싼 서버로 교체(Scale-Up)하는 것에는 한계가 있습니다. 복제를 통해 DB를 수평 확장(Scale-Out)하고 읽기 부하를 분산시키는 것이 더 근본적이고 유연한 해결책임을 깨달았습니다.
2.  **`@Transactional(readOnly = true)`의 진정한 의미**: 이 옵션이 단순히 "나는 쓰기 안 할 거야"라는 선언이 아니라, JPA에게는 '변경 감지(Dirty Checking) 스킵', DB에게는 '읽기 전용 모드'임을 알려 성능을 최적화하고, 나아가 라우팅의 '키'가 되어 읽기 전용 DB로 쿼리를 보낼 수 있게 하는 매우 중요한 스위치임을 알게 되었습니다.
3.  **데이터 정합성은 공짜가 아니다**: 읽기/쓰기 분리는 강력한 성능을 제공하지만, '복제 지연'이라는 트레이드오프를 가져옵니다. 모든 조회 쿼리를 무조건 Secondary로 보내는 것이 아니라, 비즈니스 로직상 '방금 쓴 데이터'를 바로 읽어야 하는지를 판단하여 적절히 Primary/Secondary를 선택하는 설계가 필요합니다.

---

## 🔗 참고 자료

-   [MySQL Docs - Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
-   [Spring Blog - Read-Write Splitting with Spring](https://spring.io/blog/2007/01/23/dynamic-datasource-routing)
-   [Spring Data JPA and Read-Only Transactions (Baeldung)](https://www.baeldung.com/spring-data-jpa-read-only-transactions)