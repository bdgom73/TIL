---
title: "JPA saveAll()의 배신? 대량 데이터 입력 시 JdbcTemplate으로 성능 10배 올리기"
date: 2025-12-26
categories: [Spring, Database, Performance]
tags: [JPA, JdbcTemplate, Bulk Insert, MySQL, Performance Tuning, Batch Update, TIL]
excerpt: "MySQL에서 GenerationType.IDENTITY 전략 사용 시 JPA의 Batch Insert가 비활성화되는 문제를 파악합니다. 수만 건의 데이터를 빠르게 적재하기 위해 JPA를 우회하여 JdbcTemplate.batchUpdate를 활용하는 방법과 필수 JDBC URL 설정(rewriteBatchedStatements)을 학습합니다."
author_profile: true
---

# Today I Learned: JPA saveAll()의 배신? 대량 데이터 입력 시 JdbcTemplate으로 성능 10배 올리기

## 📚 오늘 학습한 내용

데이터 마이그레이션이나 초기 더미 데이터 적재를 위해 `JpaRepository.saveAll()`을 사용하여 10만 건의 데이터를 넣으려다, 생각보다 너무 느린 속도에 당황했습니다. 로그를 확인해보니 `INSERT` 쿼리가 한 방에 나가는 게 아니라 10만 번 따로 나가고 있었습니다.

오늘은 JPA(Hibernate)가 **MySQL의 Identity 전략**을 만났을 때 발생하는 Batch Insert 제약 사항과, 이를 해결하기 위해 **JDBC 레벨**로 내려가 성능을 극대화하는 방법을 학습했습니다.

---

### 1. **문제의 원인: IDENTITY 전략과 Batch 비활성화 🐢**

MySQL에서 PK 생성 전략으로 주로 사용하는 `GenerationType.IDENTITY`(`AUTO_INCREMENT`)에는 치명적인 단점이 있습니다.

-   **매커니즘**: DB에 `INSERT`를 수행해야만 PK 값을 알 수 있습니다.
-   **JPA의 딜레마**: 영속성 컨텍스트(1차 캐시)에 엔티티를 저장하려면 PK가 필수인데, Batch Insert(쿼리를 모아서 전송)를 하려면 PK를 모른 채로 쿼리를 지연시켜야 합니다.
-   **결과**: Hibernate는 충돌을 피하기 위해 `IDENTITY` 전략 사용 시 **Batch Insert 기능을 비활성화**하고, 단건으로 `INSERT`를 날립니다.

```properties
# 아무리 이 설정을 해도 MySQL IDENTITY 전략에서는 무시됩니다.
spring.jpa.properties.hibernate.jdbc.batch_size=1000
```

---

### 2. **해결책 1: JDBC URL 설정 (`rewriteBatchedStatements`)**

JDBC 드라이버 레벨에서 쿼리를 재작성하도록 옵션을 켜야 합니다. 이 설정이 없으면 코드에서 Batch 기능을 써도 실제로는 개별 쿼리로 전송됩니다.

**application.yml**
```yaml
spring:
  datasource:
    # rewriteBatchedStatements=true 필수
    url: jdbc:mysql://localhost:3306/mydb?rewriteBatchedStatements=true&profileSQL=true&logger=Slf4JLogger
```
-   이 옵션을 켜면 드라이버가 여러 개의 `INSERT INTO table VALUES (...);` 쿼리를 `INSERT INTO table VALUES (...), (...), (...);` 형태의 **Multi-row Insert** 쿼리로 변환해서 전송합니다.

---

### 3. **해결책 2: `JdbcTemplate.batchUpdate` 구현**

JPA를 거치지 않고 Spring JDBC를 직접 사용하여 쿼리를 날립니다. Entity 객체가 아닌 POJO나 DTO 상태에서 바로 밀어넣기 때문에 오버헤드가 훨씬 적습니다.

#### **Repository 구현**

```java
@Repository
@RequiredArgsConstructor
public class ItemJdbcRepository {

    private final JdbcTemplate jdbcTemplate;

    @Transactional
    public void saveAllBatch(List<Item> items) {
        String sql = "INSERT INTO item (name, price, category, created_at) VALUES (?, ?, ?, ?)";

        jdbcTemplate.batchUpdate(sql,
            items,
            1000, // batchSize: 한 번에 묶어서 보낼 단위
            (PreparedStatement ps, Item item) -> {
                ps.setString(1, item.getName());
                ps.setLong(2, item.getPrice());
                ps.setString(3, item.getCategory());
                ps.setTimestamp(4, Timestamp.valueOf(LocalDateTime.now()));
            });
    }
}
```

---

### 4. **성능 비교 (10,000건 기준)**

직접 테스트해본 결과 압도적인 차이가 발생했습니다.

| 방식 | 소요 시간 | 동작 방식 |
| :--- | :--- | :--- |
| **JPA `saveAll()`** | 약 **12.5초** | Insert 쿼리 10,000번 실행 (Network I/O 10,000번) |
| **JdbcTemplate** | 약 **0.4초** | Multi-row Insert 쿼리 10번 실행 (batchSize=1000) |

---

### 5. **주의사항: Bulk Insert의 한계**

`JdbcTemplate`을 사용하면 빠르지만, JPA의 영속성 컨텍스트를 거치지 않으므로 다음과 같은 점을 주의해야 합니다.

1.  **영속성 컨텍스트 무시**: 저장 직후 해당 엔티티를 다시 조회하거나 수정해야 한다면, 영속성 컨텍스트에 없으므로 문제가 될 수 있습니다. (Bulk Insert는 보통 단순 적재용으로 사용)
2.  **PK 생성 불가**: `AUTO_INCREMENT`로 들어간 ID 값을 애플리케이션에서 즉시 알기 어렵습니다. ID가 필요하다면 별도 조회를 하거나, 채번 테이블 전략 등 다른 방식을 고려해야 합니다.

---

## 💡 배운 점

1.  **기술의 Trade-off**: JPA는 개발 편의성과 패러다임 일치를 제공하지만, 대량 처리에 있어서는 JDBC 직접 사용이 훨씬 효율적임을 체감했습니다. "무조건 JPA만 쓴다"는 고집을 버리고 적재적소에 JDBC를 섞어 쓰는 유연함이 필요합니다.
2.  **드라이버 옵션의 중요성**: 코드를 아무리 잘 짜도 `rewriteBatchedStatements=true` 옵션 하나를 몰라서 성능 최적화에 실패할 수 있다는 점이 소름 돋았습니다. DB 드라이버의 스펙을 꼼꼼히 읽어보는 습관을 가져야겠습니다.
3.  **CQRS의 시초**: 조회나 단건 수정은 JPA(Command/Query)로, 대량 입력은 JDBC(Command)로 나누어 처리하는 방식이 자연스럽게 CQRS 패턴의 기초가 됨을 알게 되었습니다.

---

## 🔗 참고 자료

-   [MySQL JDBC Driver Configuration Properties](https://dev.mysql.com/doc/connector-j/8.0/en/connector-j-reference-configuration-properties.html)
-   [Spring Boot Batch Insert Optimization](https://www.baeldung.com/spring-jdbc-batch-inserts)
-   [Hibernate Identity Generator and Batch Insert](https://vladmihalcea.com/hibernate-identity-sequence-and-table-sequence-generator/)