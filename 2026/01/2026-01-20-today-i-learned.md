---
title: "JPA 성능 최적화: Dirty Checking의 배신과 Bulk Update(@Modifying)의 영속성 컨텍스트 동기화"
date: 2026-01-20
categories: [Spring, JPA, Performance]
tags: [JPA, Dirty Checking, Bulk Update, Modifying, Persistence Context, Performance Tuning, TIL]
excerpt: "대량의 데이터를 수정할 때 JPA의 Dirty Checking(변경 감지) 방식이 유발하는 N번의 쿼리 문제를 해결하기 위해 JPQL Bulk Update를 도입합니다. 이때 발생하는 영속성 컨텍스트와 DB 간의 데이터 불일치 문제와 이를 @Modifying(clearAutomatically = true)로 해결하는 원리를 학습합니다."
author_profile: true
---

# Today I Learned: JPA 성능 최적화: Dirty Checking의 배신과 Bulk Update(@Modifying)의 영속성 컨텍스트 동기화

## 📚 오늘 학습한 내용

"오래된 알림 10,000개를 '읽음' 처리해달라"는 요구사항에 대해, 평소처럼 엔티티를 조회해서 `setter`로 값을 바꾸는 **Dirty Checking(변경 감지)** 방식을 사용했습니다. 기능은 잘 동작했지만, 로그를 보니 **Update 쿼리가 10,000번** 날아가면서 DB CPU가 튀는 현상을 발견했습니다.

오늘은 단건 처리에 최적화된 Dirty Checking의 한계를 인지하고, **Bulk Update(벌크 연산)**으로 쿼리를 1방으로 줄이는 방법과, 그 과정에서 발생하는 치명적인 **데이터 불일치 함정**을 해결했습니다.

---

### 1. **Dirty Checking의 성능 이슈 🐢**

JPA의 기본 수정 방식인 변경 감지는 다음과 같은 과정을 거칩니다.
1.  `findAll()`로 엔티티 10,000개를 영속성 컨텍스트에 로딩.
2.  루프를 돌며 `entity.read()` 호출 -> 스냅샷과 비교.
3.  트랜잭션 커밋 시점에 **변경된 건수(10,000개)만큼 Update 쿼리** 실행.

```java
@Transactional
public void readAllNotifications(Long userId) {
    List<Notification> notifications = notificationRepository.findAllByUserId(userId);
    // 최악의 경우: 1만 번의 Loop -> 1만 번의 Update Query
    for (Notification n : notifications) {
        n.changeReadStatus(true);
    }
}
```

---

### 2. **해결책: `@Modifying`을 이용한 Bulk Update 🚀**

JPQL을 사용하여 `UPDATE` 쿼리를 직접 작성하면, DB에 바로 쿼리를 날리므로 딱 **1번의 쿼리**로 수만 건을 처리할 수 있습니다. `INSERT`, `UPDATE`, `DELETE` 쿼리에는 반드시 **`@Modifying`** 애노테이션을 붙여야 합니다.

```java
public interface NotificationRepository extends JpaRepository<Notification, Long> {

    @Modifying // 필수: 이게 없으면 QueryExecutionRequestException 발생
    @Query("UPDATE Notification n SET n.isRead = true WHERE n.user.id = :userId")
    int bulkReadNotifications(@Param("userId") Long userId);
}
```

---

### 3. **치명적 함정: 영속성 컨텍스트 무시 ⚠️**

Bulk Update는 영속성 컨텍스트를 거치지 않고 **DB에 바로 쿼리를 꽂아버립니다.** 여기서 DB와 애플리케이션 메모리 간의 **데이터 불일치**가 발생합니다.

**문제 시나리오:**
1.  `findById(1L)`로 알림 조회 (1차 캐시에 저장됨, `isRead=false`).
2.  `bulkReadNotifications` 실행 (DB의 값은 `isRead=true`로 바뀜).
3.  다시 `findById(1L)`로 조회.
4.  **결과**: JPA는 1차 캐시에 있는 값을 우선하므로, DB가 바뀌었음에도 불구하고 **여전히 `isRead=false`인 과거 데이터를 반환**함.

```java
@Transactional
public void logic(Long userId) {
    // 1. 조회
    Notification noti = repository.findById(1L).get(); // false
    
    // 2. 벌크 업데이트 (DB는 true로 변함)
    repository.bulkReadNotifications(userId);
    
    // 3. 같은 트랜잭션 내에서 다시 조회 -> 망함
    // DB에서 안 가져오고 1차 캐시의 false 값을 그대로 줌
    Notification noti2 = repository.findById(1L).get(); 
    
    System.out.println(noti2.isRead()); // false (기대값은 true)
}
```

---

### 4. **해결책: `clearAutomatically = true`**

이 문제를 해결하려면 Bulk Update 실행 직후 **영속성 컨텍스트를 강제로 비워야(Clear)** 합니다. 그래야 다음 조회 때 1차 캐시가 비어있으니 DB에서 새로 긁어오기 때문입니다.

`@Modifying` 애노테이션에 옵션 하나만 켜주면 됩니다.

```java
// clearAutomatically = true: 쿼리 실행 후 em.clear()를 자동 호출
@Modifying(clearAutomatically = true) 
@Query("UPDATE Notification n SET n.isRead = true WHERE n.user.id = :userId")
int bulkReadNotifications(@Param("userId") Long userId);
```

이 옵션을 켜면, 벌크 연산 직후 영속성 컨텍스트가 초기화되어 이후 로직에서 안전하게 최신 데이터를 조회할 수 있습니다.

---

### 5. **Hibernate의 `flushAutomatically`**

추가로, 벌크 연산 전에 아직 DB에 반영되지 않은 `save()`나 `dirty checking` 변경분이 남아있다면 어떻게 될까요?
기본적으로 Hibernate는 JPQL 실행 전에 `flush`를 수행하지만, 명시적으로 제어하고 싶다면 `flushAutomatically = true` 옵션도 사용할 수 있습니다.

* **Default**: Hibernate는 쿼리 실행 전 관련된 엔티티에 대한 쓰기 지연 저장소의 쿼리를 먼저 flush 합니다. (안전함)

---

## 💡 배운 점

1.  **적재적소**: 단건 수정은 객체지향적인 `Dirty Checking`이 좋지만, 다건 수정은 SQL스러운 `Bulk Update`가 성능상 압도적입니다. 상황에 따라 두 방식을 적절히 섞어 써야 함을 느꼈습니다.
2.  **ORM의 추상화 누수**: JPA가 DB를 감춰주지만, Bulk Update처럼 직접 DB를 건드리는 순간 **영속성 컨텍스트와의 동기화**라는 ORM 내부 동작 원리를 모르면 심각한 버그를 만들 수 있음을 깨달았습니다.
3.  **MyBatis와의 차이**: MyBatis를 쓸 때는 쿼리를 날리면 당연히 DB가 바뀌고 끝이었는데, JPA는 '메모리 캐시'라는 계층이 하나 더 있어서 **"DB가 바뀌었다고 애플리케이션이 아는 것은 아니다"**라는 사실을 항상 인지해야겠습니다.

---

## 🔗 참고 자료

-   [Spring Data JPA @Modifying Documentation](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#jpa.modifying-queries)
-   [Persistence Context and Bulk Operations](https://vladmihalcea.com/spring-data-jpa-modifying-annotation/)
-   [JPA Dirty Checking vs Bulk Update](https://www.baeldung.com/spring-data-jpa-modifying-annotation)