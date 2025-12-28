---
title: "DB 부하 분산의 정석: Spring Boot에서 Replication(Master/Slave) 동적 라우팅 구현하기"
date: 2025-12-28
categories: [Spring, Database, Architecture]
tags: [Replication, Master-Slave, RoutingDataSource, LazyConnectionDataSourceProxy, Spring Boot, Scalability, TIL]
excerpt: "DB의 쓰기(Write)와 읽기(Read) 부하를 분리하기 위해 Replication을 구성했을 때, Spring의 @Transactional(readOnly = true) 여부에 따라 자동으로 Master 또는 Slave DB로 연결을 전환하는 라우팅 전략과 LazyConnectionDataSourceProxy의 필수적인 역할을 학습합니다."
author_profile: true
---

# Today I Learned: DB 부하 분산의 정석: Spring Boot에서 Replication(Master/Slave) 동적 라우팅 구현하기

## 📚 오늘 학습한 내용

서비스 트래픽이 늘어나 DB CPU 점유율이 80%를 넘나들기 시작했습니다. 쿼리 튜닝만으로는 한계가 있어, AWS RDS의 **Read Replica(읽기 전용 복제본)**를 생성하여 부하를 분산하기로 결정했습니다.

하지만 애플리케이션 코드에서 "이건 읽기니까 Slave로, 이건 쓰기니까 Master로" 일일이 `DataSource`를 지정하는 것은 불가능합니다. 오늘은 Spring의 **`AbstractRoutingDataSource`**를 활용하여 트랜잭션의 속성(`readOnly`)에 따라 자동으로 DB 연결을 스위칭하는 방법을 학습했습니다.

---

### 1. **핵심 원리: `AbstractRoutingDataSource` 🔀**

Spring은 여러 `DataSource`를 등록해두고, 런타임에 특정 기준에 따라 타겟 `DataSource`를 결정할 수 있는 추상 클래스를 제공합니다.

-   **동작 방식**: `determineCurrentLookupKey()` 메서드를 오버라이딩하여, 현재 트랜잭션이 읽기 전용인지(`readOnly = true`) 아닌지를 판단하고 그에 맞는 Key(Master/Slave)를 반환하면 됩니다.

---

### 2. **구현 과정**

#### **Step 1: RoutingDataSource 구현**

```java
public class ReplicationRoutingDataSource extends AbstractRoutingDataSource {

    @Override
    protected Object determineCurrentLookupKey() {
        // 현재 트랜잭션이 Read Only인지 확인
        boolean isReadOnly = TransactionSynchronizationManager.isCurrentTransactionReadOnly();
        
        // 읽기 전용이면 "SLAVE", 아니면 "MASTER" 키 반환
        return isReadOnly ? "SLAVE" : "MASTER";
    }
}
```

#### **Step 2: DataSource 설정 (Configuration)**

여기서 가장 중요한 포인트는 **`LazyConnectionDataSourceProxy`**입니다. (이유는 아래 '주의사항'에서 설명)

```java
@Configuration
public class DataSourceConfig {

    @Bean
    @ConfigurationProperties(prefix = "spring.datasource.master")
    public DataSource masterDataSource() {
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }

    @Bean
    @ConfigurationProperties(prefix = "spring.datasource.slave")
    public DataSource slaveDataSource() {
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }

    @Bean
    public DataSource routingDataSource(
            @Qualifier("masterDataSource") DataSource master,
            @Qualifier("slaveDataSource") DataSource slave) {
        
        ReplicationRoutingDataSource routingDataSource = new ReplicationRoutingDataSource();
        
        Map<Object, Object> dataSourceMap = new HashMap<>();
        dataSourceMap.put("MASTER", master);
        dataSourceMap.put("SLAVE", slave);
        
        routingDataSource.setTargetDataSources(dataSourceMap);
        routingDataSource.setDefaultTargetDataSource(master); // 기본은 Master
        
        return routingDataSource;
    }

    @Bean
    @Primary // 실제 애플리케이션이 주입받아 사용할 메인 DataSource
    public DataSource dataSource(@Qualifier("routingDataSource") DataSource routingDataSource) {
        // [핵심] 트랜잭션 진입 시점이 아니라, 실제 쿼리가 실행될 때 커넥션을 가져오도록 지연시킴
        return new LazyConnectionDataSourceProxy(routingDataSource);
    }
}
```

---

### 3. **주의사항: `LazyConnectionDataSourceProxy`가 필수인 이유 ⚠️**

처음 설정할 때 `LazyConnectionDataSourceProxy` 없이 `routingDataSource`를 바로 `@Primary`로 등록했더니, **모든 요청이 Master로만 가는 문제**가 발생했습니다.

**원인 분석:**
1.  Spring의 트랜잭션 처리 순서:
    -   TransactionManager가 트랜잭션을 시작하려고 함.
    -   **JDBC Connection을 먼저 확보함.**
    -   그 후에 트랜잭션 동기화(`TransactionSynchronizationManager`)를 설정함 (readOnly 속성 세팅).
2.  문제점:
    -   `routingDataSource`는 Connection을 확보하는 시점(`determineCurrentLookupKey`)에 `isCurrentTransactionReadOnly()`를 체크합니다.
    -   하지만 Connection을 확보하는 시점은 **아직 트랜잭션 동기화 매니저에 readOnly 속성이 세팅되기 전**입니다.
    -   따라서 항상 `readOnly = false`로 인식되어 Master DB를 바라보게 됩니다.

**해결책:**
-   `LazyConnectionDataSourceProxy`는 Connection 획득을 **실제 쿼리가 실행되는 순간**까지 미룹니다.
-   이 시점에는 이미 트랜잭션 동기화가 완료되어 `readOnly` 속성이 정상적으로 세팅되어 있으므로, 올바르게 라우팅이 동작합니다.

---

### 4. **JPA(Hibernate)와 함께 쓸 때의 팁**

`@Transactional(readOnly = true)`를 잘 쓰면 Replication 효과뿐만 아니라, Hibernate 성능 최적화 효과도 덤으로 얻습니다.

-   **Flush 모드**: `MANUAL`로 설정되어, 트랜잭션 커밋 시점에 불필요한 `flush()`(Dirty Checking)를 하지 않습니다.
-   **스냅샷 저장 안 함**: 변경 감지를 위한 스냅샷을 메모리에 보관하지 않아 메모리 사용량이 줄어듭니다.

---

## 💡 배운 점

1.  **Spring의 추상화 깊이**: 단순히 설정만 복사 붙여넣기 하다가, 트랜잭션 프록시와 커넥션 획득 시점의 미묘한 타이밍 차이 때문에 라우팅이 실패하는 원리를 파헤치며 Spring 내부 동작(Transaction Synchronization)에 대해 깊이 이해하게 되었습니다.
2.  **물리적 분리와 논리적 통합**: DB는 물리적으로 2대(Master/Slave)로 나뉘었지만, 애플리케이션 코드는 이를 전혀 의식하지 않고 기존처럼 `@Transactional`만 잘 붙이면 된다는 점(투명성)이 아키텍처 설계의 묘미임을 느꼈습니다.
3.  **데이터 지연(Replication Lag)**: Slave DB는 Master의 데이터를 비동기로 복제하므로 미세한 지연이 발생할 수 있습니다. "방금 가입하고 바로 로그인" 같은 시나리오에서 Slave를 조회하면 "없는 사용자"라고 나올 수 있습니다. 이런 민감한 로직은 반드시 Master를 타도록(`readOnly = false`) 강제해야 함을 유의해야 합니다.

---

## 🔗 참고 자료

-   [Spring AbstractRoutingDataSource Javadoc](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/jdbc/datasource/lookup/AbstractRoutingDataSource.html)
-   [Replication DataSource Configuration Guide](https://www.baeldung.com/spring-abstract-routing-data-source)
-   [LazyConnectionDataSourceProxy Explained](https://supawer0728.github.io/2018/03/22/spring-multi-datasource-with-replication/)