---
title: "JPA 낙관적 락(@Version)으로 '마지막 커밋 우선' 문제 해결하기"
date: 2025-11-11
categories: [Java, Spring, Database]
tags: [JPA, Optimistic Lock, @Version, Concurrency, Spring Boot, TIL]
excerpt: "단순한 @Transactional만으로는 해결할 수 없는 'Lost Update(갱신 손실)' 동시성 문제를 학습합니다. DB에 락을 걸지 않고, @Version 애노테이션을 사용한 JPA의 낙관적 락(Optimistic Lock)으로 데이터 정합성을 확보하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: JPA 낙관적 락(@Version)으로 '마지막 커밋 우선' 문제 해결하기

## 📚 오늘 학습한 내용

`@Transactional`을 사용하여 데이터의 원자성을 보장하는 데 익숙합니다. 하지만, **트랜잭션이 보장하는 원자성만으로는 동시성 문제를 모두 해결할 수 없다**는 것을 깨달았습니다.

-   **문제 상황: 갱신 손실 (Lost Update)**
    1.  사용자 A가 ID가 1인 게시글(조회수 10)을 조회합니다.
    2.  동시에 사용자 B가 ID가 1인 동일한 게시글(조회수 10)을 조회합니다.
    3.  사용자 A가 게시글을 수정하고 커밋합니다. (DB 조회수: 11)
    4.  *잠시 후*, 사용자 B가 게시글을 수정하고 커밋합니다. B는 자신이 조회했던 10을 기준으로 로직을 수행했으므로, DB 조회수는 **11로 덮어쓰여집니다.**
    5.  **결과**: 조회수가 2번 증가해야 하지만, A의 수정 내역이 B에 의해 **유실(Lost)**되었습니다.

이 문제는 `synchronized`로 해결할 수 없습니다 (인스턴스가 여러 대이므로). Redis 분산 락을 쓸 수도 있지만, 단순히 데이터 정합성을 확인하는 용도로는 너무 무겁습니다. 오늘은 이 문제를 **JPA의 `@Version`**을 이용한 **낙관적 락(Optimistic Lock)**으로 해결하는 방법을 학습했습니다.

---

### 1. **낙관적 락(Optimistic Lock)이란?  optimistic_lock**

-   **철학**: "충돌은 거의 일어나지 않을 거야. 그러니 일단 DB에 락(Lock)을 걸지 말고 편하게 작업하자. 대신, 내가 작업을 완료하고 **커밋하는 시점에** 혹시 누군가 먼저 데이터를 수정했는지 **그때 가서 확인**하자."
-   **비관적 락(Pessimistic Lock)과의 차이**: 비관적 락(`SELECT ... FOR UPDATE`)은 "충돌은 무조건 일어날 거야"라고 가정하고, 데이터를 읽는 시점부터 DB에 배타적 락을 걸어 다른 접근을 막습니다. 이는 성능 저하를 유발할 수 있습니다.
-   낙관적 락은 DB에 락을 걸지 않으므로 성능 이점이 크며, 읽기 작업이 빈번한 웹 애플리케이션에 매우 적합합니다.

---

### 2. **JPA에서 `@Version` 적용하기**

JPA에서 낙관적 락을 구현하는 것은 놀랍도록 간단합니다. 엔티티에 `@Version` 애노테이션이 붙은 필드 하나만 추가하면 됩니다.

```java
@Entity
@Getter
public class Post {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String title;
    private String content;

    // 1. (핵심) 버전 관리용 필드 추가
    //    long 또는 Integer 타입을 사용
    @Version
    private Long version; 

    // (JPA가 관리하므로 Setter는 만들지 않는 것이 좋음)

    public void updateContent(String title, String content) {
        this.title = title;
        this.content = content;
    }
}
```

---

### 3. **@Version의 마법: 내부 동작 원리 ⚙️**

`@Version` 필드를 추가하면, JPA(Hibernate)는 이 엔티티를 다룰 때 다음과 같이 동작합니다.

**1. `SELECT` 시 (데이터 조회)**
-   JPA가 엔티티를 조회할 때, `@Version` 필드(e.g., `version = 1`)의 값도 함께 가져와 영속성 컨텍스트에 보관합니다.

**2. `UPDATE` 시 (데이터 수정)**
-   사용자 A가 내용을 수정하고 트랜잭션을 커밋하면, JPA는 변경 감지(Dirty Checking)를 통해 UPDATE 쿼리를 생성합니다.
-   **(핵심)** 이때, `WHERE` 절에 **`id`뿐만 아니라 `version`까지** 포함시키고, `SET` 절에서 `version`을 1 증가시킵니다.

    ```sql
    /* 사용자 A의 커밋 */
    UPDATE post 
    SET title = 'A의 수정본', content = '...', version = 2 
    WHERE id = 1 AND version = 1; 
    ```
-   이 쿼리는 `version = 1`이므로 성공하고, 1개 행이 업데이트됩니다. DB의 `version`은 이제 `2`가 됩니다.

**3. `UPDATE` 시 (충돌 발생!)**
-   잠시 후, 사용자 B가 이전에 조회했던 `version = 1`을 기반으로 내용을 수정하고 커밋합니다. JPA는 동일한 방식의 쿼리를 생성합니다.

    ```sql
    /* 사용자 B의 커밋 */
    UPDATE post 
    SET title = 'B의 수정본', content = '...', version = 2 
    WHERE id = 1 AND version = 1;
    ```
-   **(충돌 감지)** 이 쿼리는 실패합니다! `id = 1`인 로우는 이미 `version = 2`가 되었기 때문에, `WHERE` 절의 조건(`version = 1`)을 만족하는 데이터가 없습니다. 따라서 0개 행이 업데이트됩니다.

**4. 예외 발생**
-   JPA는 쿼리 결과로 업데이트된 행이 0개인 것을 확인하고, **"아, 낙관적 락 충돌이 발생했구나!"**라고 인지합니다.
-   즉시 트랜잭션을 롤백시키고, **`ObjectOptimisticLockingFailureException`** (또는 유사한 예외)를 발생시킵니다.

---

### 4. **3~4년차 개발자의 대응: 예외 처리**

JPA가 예외를 발생시켜주는 것만으로는 부족합니다. 3~4년차 개발자는 이 예외를 애플리케이션 레벨에서 '우아하게' 처리해야 합니다.

```java
@Service
@RequiredArgsConstructor
public class PostService {

    private final PostRepository postRepository;

    @Transactional
    public void updatePost(Long postId, PostUpdateRequest request) {
        try {
            Post post = postRepository.findById(postId)
                    .orElseThrow(() -> new EntityNotFoundException("게시글 없음"));

            // 비즈니스 로직 수행
            post.updateContent(request.getTitle(), request.getContent());
            
            // @Transactional 종료 시 Dirty Checking으로 UPDATE 실행
            
        } catch (ObjectOptimisticLockingFailureException e) {
            // (핵심) 낙관적 락 예외를 잡아서
            // 사용자에게 명확한 비즈니스 예외로 변환하여 알려준다.
            log.warn("Optimistic Lock Conflict occurred for post: {}", postId);
            throw new BusinessException("데이터 충돌이 발생했습니다. 페이지를 새로고침한 후 다시 시도해주세요.");
        }
    }
}
```
> `ObjectOptimisticLockingFailureException`을 잡아서, 사용자에게 "새로고침 후 다시 시도"하라는 명확한 피드백을 주는 것이 중요합니다.

---

## 💡 배운 점

1.  **데이터 정합성은 '비즈니스'의 영역이다**: `@Transactional`은 기술적인 원자성을 보장할 뿐, "갱신 손실"과 같은 비즈니스 레벨의 동시성 문제는 막아주지 못합니다. `@Version`은 이러한 비즈니스 정합성을 코드 한 줄로 우아하게 해결해줍니다.
2.  **'락' 없는 '락'**: DB에 실제 락을 걸지 않고도(Pessimistic) 락을 구현(Optimistic)할 수 있다는 점이 매우 인상적이었습니다. 이는 읽기가 대부분인 웹 서비스에서 성능 저하 없이 데이터 무결성을 지킬 수 있는 훌륭한 전략입니다.
3.  **예외 처리가 완성이다**: 단순히 `@Version`을 추가하는 것에서 끝나는 것이 아니라, `ObjectOptimisticLockingFailureException`을 예측하고, 이를 `try-catch`로 잡아 사용자에게 적절한 안내(e.g., "다시 시도하세요")를 하는 것까지가 3~4년차 개발자가 책임져야 할 '완성된' 기능임을 깨달았습니다.

---

## 🔗 참고 자료

-   [JPA Docs - Versioning and Optimistic Locking](https://docs.oracle.com/javaee/7/api/javax/persistence/Version.html)
-   [Spring Data JPA - Optimistic Locking](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#locking.optimistic)
-   [Optimistic Locking with @Version (Baeldung)](https://www.baeldung.com/jpa-optimistic-locking)