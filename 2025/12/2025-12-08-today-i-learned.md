---
title: "Spring Batch: 대용량 데이터 처리를 위한 Chunk 지향 처리와 성능 튜닝"
date: 2025-12-08
categories: [Spring, Batch]
tags: [Spring Batch, Chunk, JPA, Batch Processing, Performance Tuning, ETL, TIL]
excerpt: "대용량 데이터를 메모리 효율적으로 처리하기 위한 Spring Batch의 Chunk 지향 처리 방식을 학습합니다. Tasklet 방식과의 차이점을 이해하고, JpaPagingItemReader 사용 시 Page Size와 Chunk Size를 일치시켜야 하는 성능 최적화 원리를 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Batch: 대용량 데이터 처리를 위한 Chunk 지향 처리와 성능 튜닝

## 📚 오늘 학습한 내용

백엔드 시스템을 운영하다 보면 수십만, 수백만 건의 데이터를 매일 밤 정산하거나, 통계 리포트를 생성하고, 오래된 데이터를 아카이빙(이관)해야 하는 요구사항이 반드시 생깁니다. 이런 작업을 일반적인 웹 애플리케이션의 `@Transactional` 메서드 하나에서 `findAll()`로 처리하면 **OOM(Out Of Memory)**이 발생하거나 트랜잭션 타임아웃으로 실패하기 십상입니다.

오늘은 이러한 대용량 데이터 처리에 특화된 **Spring Batch** 프레임워크, 그중에서도 메모리 효율성을 극대화하는 **Chunk 지향 처리(Chunk-oriented Processing)** 모델과 핵심 튜닝 포인트를 학습했습니다.

---

### 1. **Tasklet vs. Chunk: 언제 무엇을 써야 할까?**

Spring Batch는 크게 두 가지 처리 방식을 제공합니다.

-   **Tasklet 방식**:
    -   `Step` 안에서 단 하나의 작업을 수행합니다. (단순 파일 삭제, 프로시저 호출 등)
    -   데이터 양이 적거나, 읽기/쓰기 구조가 단순할 때 사용합니다.
    -   대용량 데이터 처리에는 적합하지 않습니다 (한 번에 다 읽어야 함).

-   **Chunk 방식**:
    -   **"읽기(Read) -> 가공(Process) -> 쓰기(Write)"**의 흐름을 가집니다.
    -   **Chunk Size**만큼 데이터를 쪼개서 트랜잭션을 처리합니다.
    -   예: 10,000건의 데이터를 처리할 때 Chunk Size가 1,000이라면, 1,000개씩 읽고 가공한 뒤 **1,000개 단위로 커밋**합니다. (총 10번의 트랜잭션)
    -   **장점**: 메모리 사용량을 일정하게 유지할 수 있고, 중간에 실패해도 처리된 Chunk까지는 커밋되어 있으므로 복구(Recovery)가 용이합니다.



---

### 2. **Chunk 지향 처리 구현 (JPA 활용)**

가장 흔한 패턴인 **"DB에서 읽어서(Reader), 로직을 수행하고(Processor), 다시 DB에 저장(Writer)"**하는 배치를 구성해 봅니다.

```java
@Configuration
@RequiredArgsConstructor
public class UserGradeBatchConfig {

    private final JobRepository jobRepository;
    private final PlatformTransactionManager transactionManager;
    private final EntityManagerFactory entityManagerFactory;

    // Chunk Size와 Page Size는 일치시키는 것이 성능상 좋습니다.
    private static final int CHUNK_SIZE = 1000;

    @Bean
    public Job upgradeUserGradeJob() {
        return new JobBuilder("upgradeUserGradeJob", jobRepository)
                .start(upgradeUserGradeStep()) // Step 시작
                .build();
    }

    @Bean
    public Step upgradeUserGradeStep() {
        return new StepBuilder("upgradeUserGradeStep", jobRepository)
                .<User, User>chunk(CHUNK_SIZE, transactionManager) // 입력타입, 출력타입, 트랜잭션 단위
                .reader(userItemReader())
                .processor(userItemProcessor())
                .writer(userItemWriter())
                .build();
    }

    // 1. Reader: DB에서 1000개씩 퍼올리기 (Paging)
    @Bean
    public JpaPagingItemReader<User> userItemReader() {
        return new JpaPagingItemReaderBuilder<User>()
                .name("userItemReader")
                .entityManagerFactory(entityManagerFactory)
                .pageSize(CHUNK_SIZE) // 한 번 쿼리할 때 가져올 개수
                .queryString("SELECT u FROM User u WHERE u.totalAmount >= 100000") // 등급 상향 대상 조회
                .build();
    }

    // 2. Processor: 비즈니스 로직 (등급 상향)
    @Bean
    public ItemProcessor<User, User> userItemProcessor() {
        return user -> {
            user.upgradeLevel(); // User 엔티티 내부 로직 실행 (VIP 등급으로 변경)
            return user;
        };
    }

    // 3. Writer: 변경된 내용 DB 반영
    @Bean
    public JpaItemWriter<User> userItemWriter() {
        return new JpaItemWriterBuilder<User>()
                .entityManagerFactory(entityManagerFactory)
                .build();
    }
}
```

---

### 3. **핵심 튜닝: Page Size와 Chunk Size의 관계 ⚙️**

`JpaPagingItemReader`를 사용할 때 가장 중요한 튜닝 포인트는 **Page Size와 Chunk Size를 일치시키는 것**입니다.

-   **Chunk Size**: "몇 개의 아이템을 모아서 한 번에 커밋(트랜잭션)할 것인가?" (Spring Batch의 설정)
-   **Page Size**: "한 번의 쿼리로 몇 개의 로우를 DB에서 가져올 것인가?" (JPA/SQL의 설정)

만약 **Chunk Size(100) / Page Size(10)**라면?
-   1번의 트랜잭션(커밋)을 위해 100개를 모아야 하는데, DB 쿼리는 10개씩 가져오므로 **10번의 쿼리**가 실행됩니다. 불필요한 네트워크 통신이 발생하여 성능이 저하됩니다.

만약 **Chunk Size(10) / Page Size(100)**라면?
-   10개를 처리하고 커밋했지만, 이미 읽어온 나머지 90개는 메모리에 남아있거나 낭비됩니다. 또한, JPA 영속성 컨텍스트 관리 측면에서도 복잡해질 수 있습니다.

**결론**: `PagingItemReader`를 쓸 때는 **`Page Size = Chunk Size`**로 맞추는 것이 성능과 효율 면에서 가장 이상적입니다.

---

### 4. **주의사항: 페이징 쿼리의 함정 (Zero Offset)**

`JpaPagingItemReader`는 기본적으로 `LIMIT x OFFSET y` 방식을 사용합니다. 여기서 데이터를 **수정(Update)**할 때 치명적인 문제가 발생할 수 있습니다.

-   **시나리오**: `WHERE status = 'PENDING'`인 데이터를 조회해서 `status = 'DONE'`으로 변경하는 배치.
-   **1번째 쿼리**: `OFFSET 0 LIMIT 10` -> 10개를 가져와서 DONE으로 변경. (이제 PENDING은 90개 남음)
-   **2번째 쿼리**: `OFFSET 10 LIMIT 10` -> **문제 발생!**
    -   앞서 10개가 DONE으로 바뀌어서 조회 조건에서 빠졌으므로, 전체 데이터셋이 앞으로 당겨졌습니다.
    -   하지만 Reader는 `OFFSET 10`부터 읽으므로, **중간의 10개 데이터를 건너뛰고(Skip)** 읽게 됩니다.

**해결책**:
1.  **Cursor 기반 Reader 사용**: `JdbcCursorItemReader` 등을 사용하여 DB 커서를 유지하며 읽습니다. (JPA는 지원 미비)
2.  **정렬 기준 고정**: PK 기준으로 정렬하여 처리합니다.
3.  **(가장 추천) `Zero Offset` 전략**: 조건절이 변경되는 배치라면, Reader를 오버라이딩하여 **항상 `Page 0 (OFFSET 0)`**만 읽도록 설정해야 누락 없이 처리할 수 있습니다.

---

## 💡 배운 점

1.  **배치는 웹과 다르다**: 웹 요청은 응답 속도(Latency)가 중요하지만, 배치는 처리량(Throughput)과 안정성이 핵심입니다. Chunk 지향 처리는 트랜잭션을 쪼개서 긴 작업을 안정적으로 수행하게 해주는 배치의 심장과도 같습니다.
2.  **영속성 컨텍스트 관리**: `JpaItemWriter`는 Chunk 단위로 `flush()`를 수행하고 `entityManager.clear()`를 호출하여 영속성 컨텍스트를 비워줍니다. 덕분에 수백만 건을 처리해도 메모리가 넘치지 않습니다. 직접 구현하려면 이 모든 것을 수동으로 해야 했을 것입니다.
3.  **쿼리 튜닝은 필수**: 배치 애플리케이션은 필연적으로 Full Scan이나 대량의 데이터를 다룹니다. `Page Size` 튜닝과 `Zero Offset` 문제는 배치 개발자가 모르면 반드시 사고(데이터 누락)로 이어지는 중요한 포인트임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Batch Reference Documentation](https://docs.spring.io/spring-batch/docs/current/reference/html/)
-   [Spring Batch Chunk-Oriented Processing](https://docs.spring.io/spring-batch/docs/current/reference/html/step.html#chunkOrientedProcessing)
-   [Spring Batch Performance Tuning (Baeldung)](https://www.baeldung.com/spring-batch-performance-tuning)