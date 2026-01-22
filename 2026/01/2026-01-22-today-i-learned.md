---
title: "QueryDSL 성능 최적화: 수백만 건 데이터 페이징에서 Offset을 버려야 하는 이유 (No Offset 전략)"
date: 2026-01-22
categories: [Spring, Database, Performance]
tags: [QueryDSL, Pagination, No Offset, Performance Tuning, MySQL, Infinite Scroll, TIL]
excerpt: "대용량 테이블에서 페이징 번호가 뒤로 갈수록 쿼리 속도가 급격히 느려지는 원인을 데이터베이스 인덱스 스캔 관점에서 분석합니다. 기존의 'OFFSET + LIMIT' 방식의 한계를 극복하기 위해 QueryDSL을 활용한 'No Offset(Seek Method)' 페이징 전략을 구현하고, Page 대신 Slice를 반환하여 성능을 최적화하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: QueryDSL 성능 최적화: 수백만 건 데이터 페이징에서 Offset을 버려야 하는 이유 (No Offset 전략)

## 📚 오늘 학습한 내용

게시판의 데이터가 500만 건을 넘어가면서, 사용자가 "마지막 페이지" 근처로 이동하거나 모바일 앱에서 스크롤을 많이 내릴수록 API 응답 속도가 3초, 5초, 10초로 기하급수적으로 느려지는 현상을 발견했습니다.

원인은 DB가 `OFFSET`을 처리하기 위해 앞부분의 데이터를 모두 읽고 버리는 방식(`Full Scan`에 가까운 동작) 때문이었습니다. 오늘은 이를 해결하기 위해 **No Offset(무한 스크롤)** 방식으로 페이징 쿼리를 튜닝했습니다.

---

### 1. **기존 방식(Legacy Offset)의 문제점 🐢**

우리가 흔히 쓰는 페이징 쿼리는 다음과 같습니다.

```sql
SELECT * FROM orders 
ORDER BY id DESC 
LIMIT 10 OFFSET 1000000;
```

* **동작**: DB는 1,000,010개의 레코드를 읽은 뒤, 앞의 1,000,000개를 버리고 마지막 10개를 반환합니다.
* **비용**: 뒤로 갈수록(Offset이 커질수록) 읽어야 할 데이터가 많아져 디스크 I/O와 CPU 사용량이 폭증합니다.
* **인덱스**: 인덱스를 타더라도, 결국 인덱스를 100만 번째까지 순차적으로 훑어야 하는 건 변함이 없습니다.

---

### 2. **해결책: No Offset (Seek Method) 🚀**

"몇 번째 페이지인가"를 묻지 말고, **"마지막으로 본 항목(ID)의 다음부터 보여달라"**고 요청하는 방식입니다.

```sql
SELECT * FROM orders 
WHERE id < 1000000 -- 직전에 조회한 마지막 ID
ORDER BY id DESC 
LIMIT 10;
```

* **동작**: 클러스터드 인덱스(PK)를 타고 `id = 1000000` 위치로 **바로 점프**한 뒤, 거기서부터 10개만 읽습니다.
* **비용**: 1페이지를 조회하든 10,000페이지를 조회하든 **항상 일정한 속도**를 보장합니다.

---

### 3. **QueryDSL 구현**

Spring Data JPA의 `Pageable`을 그대로 쓰면 자동으로 Offset이 나가므로, 직접 조건을 걸어야 합니다.

#### **Step 1: 동적 쿼리 조건 (`BooleanExpression`)**

첫 페이지(마지막 ID가 없는 경우)와 두 번째 페이지(마지막 ID가 있는 경우)를 모두 처리하기 위해 동적 쿼리를 작성합니다.

```java
private BooleanExpression ltLastOrderId(Long lastOrderId) {
    if (lastOrderId == null) {
        return null; // 첫 페이지 조회 시 조건 없음
    }
    // id < lastOrderId
    return order.id.lt(lastOrderId); 
}
```

#### **Step 2: Repository 구현 (`Slice` 반환)**

No Offset 방식에서는 "전체 페이지 수(Total Count)"를 계산하는 것이 의미가 없거나 불가능하므로, `Page` 대신 **`Slice`**를 반환하여 "다음 페이지가 있는지" 여부만 알려주는 것이 효율적입니다.

```java
public Slice<OrderDto> findAllNoOffset(Long lastOrderId, int limit) {
    List<OrderDto> content = queryFactory
            .select(new QOrderDto(
                    order.id,
                    order.title,
                    order.amount,
                    order.createdAt
            ))
            .from(order)
            .where(
                    ltLastOrderId(lastOrderId), // 핵심: No Offset 조건
                    order.memberId.eq(1L)       // 기타 비즈니스 조건
            )
            .orderBy(order.id.desc())
            .limit(limit + 1) // 핵심: 요청한 것보다 1개 더 조회해서 다음 페이지 존재 여부 확인
            .fetch();

    boolean hasNext = false;
    if (content.size() > limit) {
        hasNext = true;
        content.remove(limit); // 확인용으로 가져온 마지막 1개는 제거하고 반환
    }

    return new SliceImpl<>(content, PageRequest.of(0, limit), hasNext);
}
```

---

### 4. **API 요청/응답 설계**

프론트엔드와의 약속도 변경되어야 합니다. 페이지 번호(`page`) 대신 마지막 식별자(`lastId`)를 주고받아야 합니다.

* **요청**: `GET /orders?size=10` (첫 요청)
* **응답**:
    ```json
    {
        "content": [ {"id": 100}, ..., {"id": 91} ],
        "hasNext": true,
        "lastId": 91 // 프론트엔드는 다음 요청 때 이 값을 보냄
    }
    ```
* **다음 요청**: `GET /orders?size=10&lastId=91`

---

### 5. **단점과 극복**

* **단점**: "3페이지로 점프", "10페이지로 점프" 같은 기능을 구현할 수 없습니다. 오직 "더 보기(Infinite Scroll)"나 "다음" 버튼만 가능합니다.
* **정렬 조건**: 정렬 기준이 PK(Unique)가 아니라면(`ORDER BY price DESC`), 중복된 가격이 있을 때 데이터가 누락되거나 중복될 수 있습니다.
    * **해결**: 정렬 기준에 PK를 반드시 포함시켜야 합니다. (`ORDER BY price DESC, id DESC`)

---

## 💡 배운 점

1.  **인덱스의 효율적 사용**: DB 인덱스는 '찾아가는 것(Seek)'은 빠르지만, '훑는 것(Scan)'은 비용이 든다는 기본 원리를 다시 깨달았습니다. Offset은 Scan 비용을 유발하는 주범입니다.
2.  **UX와 성능의 타협**: 무한 스크롤(No Offset)은 성능상 압도적이지만, 사용자가 특정 페이지 위치를 기억할 수 없다는 UX 단점이 있습니다. 어드민 페이지처럼 번호 이동이 필수인 곳과, 모바일 피드처럼 스크롤이 자연스러운 곳을 구분해서 전략을 적용해야 함을 배웠습니다.
3.  **Count 쿼리의 해악**: `Page` 객체를 반환하려면 반드시 `count()` 쿼리가 동반되는데, 데이터가 많으면 이 카운트 쿼리 하나가 전체 목록 조회보다 더 느릴 때가 많습니다. `Slice`를 활용해 카운트 쿼리를 제거하는 것만으로도 엄청난 성능 향상이 있었습니다.

---

## 🔗 참고 자료

-   [Faster Pagination in MySQL (SlideShare)](https://www.slideshare.net/Eweaver/efficient-pagination-using-mysql)
-   [QueryDSL Dynamic Query Documentation](http://querydsl.com/static/querydsl/latest/reference/html/ch03.html#d0e1906)
-   [Spring Data JPA Slice vs Page](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#repositories.special-parameters)