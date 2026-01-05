---
title: "Spring Batch 성능 튜닝: JpaPagingItemReader의 함정과 Zero Offset 전략"
date: 2026-01-06
categories: [Spring, Batch, Performance]
tags: [Spring Batch, JPA, Performance Tuning, Chunk Oriented, Batch Processing, TIL]
excerpt: "대용량 데이터를 처리하는 배치 작업에서 발생하는 성능 저하 원인을 분석합니다. Chunk 지향 처리의 기본 개념부터, JPA Paging Reader 사용 시 발생하는 '데이터 누락' 문제와 이를 해결하기 위한 Zero Offset 전략, 그리고 Cursor 방식과의 차이점을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Batch 성능 튜닝: JpaPagingItemReader의 함정과 Zero Offset 전략

## 📚 오늘 학습한 내용

매일 밤 수백만 건의 정산 데이터를 처리해야 하는 배치 Job이 점점 느려지더니 급기야 OOM(Out Of Memory)으로 뻗는 현상이 발생했습니다. 단순히 `Chunk Size`만 늘린다고 해결될 문제가 아니라는 것을 깨닫고, Spring Batch의 **Chunk 지향 처리(Chunk-oriented Processing)** 구조와 **ItemReader의 동작 방식**을 깊이 있게 파고들었습니다.

특히, 수정이 일어나는 배치에서 **PagingItemReader**를 사용할 때 발생하는 치명적인 데이터 누락 버그와 해결책을 정리했습니다.

---

### 1. **Chunk 지향 처리란? 📦**

데이터를 한 번에 메모리에 올리지 않고, 설정한 크기(Chunk Size)만큼 끊어서 **"읽기(Read) -> 가공(Process) -> 쓰기(Write)"**를 반복하는 방식입니다.



-   **Transaction**: Chunk 단위로 트랜잭션이 커밋됩니다. (Chunk Size가 1000이면 1000개 처리 후 커밋)
-   **Page Size vs Chunk Size**: `PagingItemReader`를 쓸 때는 성능을 위해 **Page Size와 Chunk Size를 일치시키는 것**이 권장됩니다. (한 번 페이징 쿼리를 날릴 때 가져오는 양과, 트랜잭션 커밋 단위 맞춤)

---

### 2. **치명적 함정: Paging Reader와 Update 쿼리 ⚠️**

`JpaPagingItemReader`를 사용하여 데이터를 조회하고, 상태를 변경(Update)하는 배치를 짤 때 가장 많이 하는 실수가 있습니다.

**시나리오**: "미승인(STATUS='N')" 주문을 조회하여 "승인(STATUS='Y')"으로 변경한다. Page Size는 10.

1.  **첫 번째 쿼리 (Page 0)**: `SELECT * FROM orders WHERE status='N' LIMIT 10 OFFSET 0`
    -   10개를 가져와서 상태를 'Y'로 바꿈.
    -   이제 DB에는 상태가 'N'인 데이터가 10개 줄어듬.
2.  **두 번째 쿼리 (Page 1)**: `SELECT * FROM orders WHERE status='N' LIMIT 10 OFFSET 10`
    -   **문제 발생**: 앞에서 10개가 'Y'로 바뀌어서 조건에서 빠졌으므로, DB 입장에서는 11번째 데이터가 1번째 데이터로 당겨짐.
    -   그런데 쿼리는 `OFFSET 10`부터 가져오라고 하니, **중간의 10개 데이터는 조회되지 않고 건너뜀(Skip)**.

#### **해결책: Zero Offset 전략**

조회 조건에 포함된 컬럼을 수정하는 경우에는 **항상 Page 0만 조회**하도록 `setPageSize`를 오버라이딩하거나 커스텀 리더를 만들어야 합니다.

```java
@Bean
public JpaPagingItemReader<Order> orderPagingReader() {
    return new JpaPagingItemReaderBuilder<Order>()
            .name("orderPagingReader")
            .entityManagerFactory(entityManagerFactory)
            .pageSize(1000)
            .queryString("SELECT o FROM Order o WHERE o.status = 'N'") // 조건절 컬럼이 수정 대상임
            .transacted(false) // 중요: 항상 새로운 트랜잭션에서 쿼리 실행해야 갱신된 데이터 반영
            .build();
}

// 위의 방식보다는 아래처럼 아예 Page 0을 고정하는 것이 안전함
public class ZeroOffsetJpaPagingItemReader<T> extends JpaPagingItemReader<T> {
    @Override
    protected void doReadPage() {
        if (results == null) {
            results = new CopyOnWriteArrayList<>();
        } else {
            results.clear();
        }
        
        // 부모 클래스의 페이지 읽기 로직을 호출하되, 페이지는 항상 0으로 고정
        // (단, JPA 구현체 내부적으로 offset 계산 로직 확인 필요, 
        // 보통은 setPage(0)을 호출해주는 별도의 커스텀 로직이 필요함)
    }
}
```

> **더 쉬운 해결책**: 가능하다면 `CursorItemReader`를 사용하거나, `PagingItemReader`를 쓰되 조회 조건에 수정되는 컬럼을 넣지 않고 전체를 읽어서 Processor에서 필터링하는 것이 안전합니다.

---

### 3. **Cursor vs Paging: 성능 승자는? 🏎️**

| 특징 | **CursorItemReader (JdbcCursor / HibernateCursor)** | **PagingItemReader (JdbcPaging / JpaPaging)** |
| :--- | :--- | :--- |
| **동작 방식** | DB 커넥션을 계속 유지한 채 스트리밍으로 데이터를 한 건씩 `fetch` | 페이지 단위로 커넥션을 맺고 끊으며 `limit/offset` 쿼리 실행 |
| **장점** | 속도가 매우 빠르고 데이터 누락 이슈가 없음 | 커넥션 유지 시간이 짧아 타임아웃 걱정이 덜함 |
| **단점** | 배치 수행 시간이 길어지면 DB 커넥션 타임아웃 발생 가능, 멀티 스레드 처리 어려움 | Offset이 커질수록 쿼리 성능이 급격히 저하됨 (`Deep Paging` 문제) |
| **선택 기준** | **단일 스레드**로 대량 데이터를 빨리 처리해야 할 때 | **멀티 스레드(Partitioning)** 환경이거나 DB 부하를 쪼개야 할 때 |

---

### 4. **JPA의 N+1 문제와 Batch**

일반 웹 애플리케이션과 마찬가지로, 배치에서도 `Reader`에서 엔티티를 읽을 때 연관 관계가 `Lazy Loading` 되어 있다면 `Processor`에서 접근할 때마다 쿼리가 나갑니다. 배치에서는 처리량이 많으므로 이게 수만 번의 쿼리로 이어집니다.

-   **해결**: `Fetch Join`을 사용한 쿼리를 JPQL로 직접 작성하여 Reader에 주입해야 합니다.

```java
.queryString("SELECT o FROM Order o JOIN FETCH o.orderItems WHERE ...")
```

---

## 💡 배운 점

1.  **Offset의 배신**: 게시판 페이징 구현하듯이 배치를 짜면 데이터가 누락될 수 있다는 사실을 알았습니다. 조건 컬럼을 업데이트하는 배치는 반드시 Cursor 방식을 쓰거나 Zero Offset 전략을 써야 합니다.
2.  **Fetch Size 튜닝**: `CursorItemReader`를 쓸 때 `fetchSize`를 설정하지 않으면 기본값(보통 10)으로 동작해 네트워크 통신 비용이 증가합니다. 이를 Chunk Size만큼(예: 1000) 늘려주는 것만으로도 비약적인 성능 향상이 있었습니다.
3.  **적절한 Chunk Size**: 무조건 크다고 좋은 게 아니었습니다. 너무 크면 영속성 컨텍스트(1차 캐시)에 쌓이는 엔티티가 많아져 `Flush` 시간이 오래 걸리고 메모리를 많이 먹습니다. 보통 1,000 ~ 5,000 사이에서 테스트하며 최적값을 찾아야 합니다.

---

## 🔗 참고 자료

-   [Spring Batch Reference Guide](https://docs.spring.io/spring-batch/reference/)
-   [Spring Batch PagingItemReader Common Pitfalls](https://jojoldu.tistory.com/337)
-   [Memory Management in Spring Batch](https://www.baeldung.com/spring-batch-memory)