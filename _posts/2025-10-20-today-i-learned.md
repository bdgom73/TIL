---
title: "Spring Batch: 대용량 데이터 처리를 위한 핵심 개념"
date: 2025-10-20
categories: [Spring, Batch]
tags: [Spring Batch, Batch Processing, Job, Step, ItemReader, ItemProcessor, ItemWriter, TIL]
excerpt: "대용량 데이터를 안정적으로 처리하기 위한 Spring Batch의 핵심 아키텍처를 학습합니다. Job, Step, JobRepository의 역할을 이해하고, 청크(Chunk) 기반 처리 모델의 중요성과 트랜잭션 관리 방식을 탐구합니다."
author_profile: true
---

# Today I Learned: Spring Batch: 대용량 데이터 처리를 위한 핵심 개념

## 📚 오늘 학습한 내용

매일 밤 수백만 건의 데이터를 집계하여 리포트를 생성하거나, 다른 시스템의 데이터를 마이그레이션해야 할 때, 단순히 `@Scheduled`와 `for`문을 사용하는 것은 위험합니다. 메모리 부족(OOM)으로 애플리케이션이 멈출 수도 있고, 중간에 작업이 실패했을 때 어디서부터 다시 시작해야 할지 막막해집니다.

오늘은 이러한 **대용량 배치(Batch) 처리**를 위해 탄생한 프레임워크인 **Spring Batch**의 핵심 아키텍처와 동작 원리에 대해 학습했습니다.

---

### 1. **Spring Batch의 핵심 구성 요소 🏛️**

Spring Batch는 '배치 작업'을 정의하고 실행하기 위한 명확한 구조를 가지고 있습니다.

-   **`Job`**: 하나의 '배치 작업'을 의미하는 최상위 단위입니다. (e.g., "일일 사용자 정산 작업")
-   **`Step`**: `Job`을 구성하는 실질적인 작업 단계입니다. 하나의 `Job`은 하나 이상의 `Step`으로 구성될 수 있습니다. (e.g., 1단계: "사용자 데이터 파일 읽기", 2단계: "데이터 정산", 3단계: "정산 결과 DB 저장")
-   **`JobRepository`**: `Job`과 `Step`의 실행 상태, 시작 시간, 종료 시간, 실패 여부 등 모든 **메타데이터**를 저장하는 저장소입니다. 이 정보가 있기 때문에, 작업이 중간에 실패하더라도 이전에 성공한 지점부터 **다시 시작(Restart)**하는 것이 가능해집니다.

---

### 2. **핵심 원리: 청크(Chunk) 기반 처리**

Spring Batch가 대용량 데이터를 안정적으로 처리하는 비결은 **청크(Chunk) 기반 처리**에 있습니다.

데이터 100만 건을 한 번에 읽어서(Read), 한 번에 처리(Process)하고, 한 번에 쓰는(Write) 것은 100% 메모리 오류를 유발합니다. Spring Batch는 이 작업을 작은 '덩어리(Chunk)' 단위로 나누어 처리합니다.

-   **청크(Chunk)**: 데이터를 한 번에 처리하는 묶음 단위.
-   **`ItemReader`**: 데이터 소스(DB, 파일, 큐 등)에서 데이터를 **하나씩** 읽어옵니다.
-   **`ItemProcessor`**: 읽어온 데이터를 **하나씩** 가공합니다. (e.g., 데이터 변환, 필터링) - *Optional*
-   **`ItemWriter`**: 가공된 데이터를 **청크 단위(e.g., 100개씩)**로 묶어서 DB나 파일에 **한 번에** 씁니다.



#### **청크 기반 트랜잭션**
가장 중요한 점은 **트랜잭션이 청크 단위를 기준으로 동작**한다는 것입니다.

1.  트랜잭션을 시작합니다.
2.  `ItemReader`가 청크 크기(e.g., 100)만큼 데이터를 하나씩 읽어 메모리에 모읍니다. (e.g., 100번 Read)
3.  `ItemProcessor`가 100개의 아이템을 하나씩 처리합니다.
4.  `ItemWriter`가 100개의 처리된 아이템을 **한 번에 DB에 씁니다.**
5.  트랜잭션을 커밋합니다.

만약 `ItemWriter`가 100개를 쓰는 도중 80번째 아이템에서 오류가 발생하면, 해당 트랜잭션 전체가 롤백됩니다. 즉, 그 청크(100개)의 작업만 롤백되고, 다음 작업은 실패한 청크부터 다시 시작할 수 있습니다.

---

### 3. **Spring Batch Job 설정 예제**

Spring Batch는 `@EnableBatchProcessing` 애노테이션과 `JobBuilderFactory`, `StepBuilderFactory`를 통해 Job을 쉽게 설정할 수 있습니다.

```java
@Configuration
@EnableBatchProcessing // Spring Batch 기능 활성화
@RequiredArgsConstructor
public class MyBatchJobConfiguration {

    private final JobBuilderFactory jobBuilderFactory;
    private final StepBuilderFactory stepBuilderFactory;
    private final DataSource dataSource; // DB 연결 정보

    // Job 정의
    @Bean
    public Job processUserDataJob() {
        return jobBuilderFactory.get("processUserDataJob")
                .start(processUserDataStep()) // 이 Job은 하나의 Step으로 구성됨
                .build();
    }

    // Step 정의 (Chunk 기반)
    @Bean
    public Step processUserDataStep() {
        return stepBuilderFactory.get("processUserDataStep")
                .<User, ProcessedUser>chunk(100) // 청크 크기 = 100
                .reader(userItemReader())       // 1. Reader
                .processor(userItemProcessor()) // 2. Processor
                .writer(userItemWriter())       // 3. Writer
                .build();
    }

    // ItemReader: DB에서 User 데이터를 100개씩 Paging하여 읽음
    @Bean
    public JpaPagingItemReader<User> userItemReader() {
        return new JpaPagingItemReaderBuilder<User>()
                .name("userItemReader")
                .entityManagerFactory(entityManagerFactory)
                .pageSize(100)
                .queryString("SELECT u FROM User u ORDER BY u.id")
                .build();
    }

    // ItemProcessor: User 객체를 ProcessedUser 객체로 변환
    @Bean
    public ItemProcessor<User, ProcessedUser> userItemProcessor() {
        return user -> new ProcessedUser(user.getName().toUpperCase(), user.getAge() + 10);
    }

    // ItemWriter: 처리된 ProcessedUser 데이터를 DB에 100개씩 저장
    @Bean
    public JpaItemWriter<ProcessedUser> userItemWriter() {
        return new JpaItemWriterBuilder<ProcessedUser>()
                .entityManagerFactory(entityManagerFactory)
                .build();
    }
}
```

---

## 💡 배운 점

1.  **배치 작업은 '안정성'이 핵심이다**: Spring Batch의 진정한 가치는 단순히 `for`문을 대신해주는 것이 아니라, `JobRepository`를 통한 **메타데이터 관리**에 있다는 것을 깨달았습니다. 작업이 새벽 4시에 실패했을 때, 원인을 파악하고 실패한 지점부터 정확히 재시작할 수 있게 해주는 것이 핵심입니다.
2.  **Chunk와 트랜잭션**: 대용량 데이터를 '청크' 단위로 쪼개고, 이 청크를 하나의 트랜잭션 단위로 묶어 처리하는 방식이 메모리 효율성과 데이터 정합성을 동시에 잡는 매우 영리한 설계임을 이해했습니다.
3.  **관심사의 분리(SoC)**: `Reader`, `Processor`, `Writer`로 역할이 명확하게 분리되어 있어, 각 컴포넌트의 책임을 명확히 하고 독립적으로 테스트하기에 매우 용이한 구조입니다. 이는 유지보수성을 크게 향상시킵니다.

---

## 🔗 참고 자료

-   [Spring Batch 공식 문서](https://docs.spring.io/spring-batch/docs/current/reference/html/)
-   [Spring Batch - Core Concepts](https://spring.io/projects/spring-batch)
-   [Spring Batch (Baeldung)](https://www.baeldung.com/introduction-to-spring-batch)