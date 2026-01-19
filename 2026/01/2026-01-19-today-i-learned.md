---
title: "데이터 삭제는 신중하게: JPA Soft Delete(논리 삭제) 구현과 Unique Index 충돌 해결"
date: 2026-01-19
categories: [Spring, JPA, Database]
tags: [Soft Delete, Hibernate, SQLDelete, Unique Constraint, JPA, Database Design, TIL]
excerpt: "데이터를 물리적으로 삭제하지 않고 상태만 변경하는 Soft Delete 패턴을 Hibernate 애노테이션(@SQLDelete)으로 우아하게 구현하는 방법을 학습합니다. 더불어 Soft Delete 적용 시 발생하는 Unique Constraint(중복 가입 방지) 충돌 문제와 이를 해결하기 위한 DB 인덱스 설계 전략을 정리합니다."
author_profile: true
---

# Today I Learned: 데이터 삭제는 신중하게: JPA Soft Delete 구현과 Unique Index 충돌 해결

## 📚 오늘 학습한 내용

회원 탈퇴 기능을 구현하면서 `repository.delete(user)`를 호출하면 데이터가 영구적으로 사라져, 나중에 "실수로 탈퇴했다"는 CS 문의가 왔을 때 복구가 불가능한 문제가 있었습니다. 또한, 데이터 분석을 위해서라도 이력은 남겨야 했습니다.

오늘은 데이터를 물리적으로 지우지 않고 `deleted = true` 마킹만 하는 **Soft Delete(논리 삭제)**를 비즈니스 로직 수정 없이 JPA 레벨에서 처리하는 방법과, 이때 발생하는 **Unique Index 충돌** 문제를 해결했습니다.

---

### 1. **Hibernate 애노테이션으로 Soft Delete 자동화**

모든 삭제 로직(`deleteById` 등)을 찾아서 `user.setDeleted(true)`로 바꾸는 것은 실수할 여지가 많습니다. Hibernate의 `@SQLDelete`와 `@Where`를 사용하면 이를 자동화할 수 있습니다.

* **`@SQLDelete`**: JPA의 `delete` 명령이 실행될 때, 실제로는 지정한 `UPDATE` 쿼리를 실행하도록 가로챕니다.
* **`@Where`**: 조회 쿼리(`select`)가 실행될 때, 자동으로 `where` 조건을 붙여 삭제된 데이터는 조회되지 않게 합니다.

```java
@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
// 1. delete 실행 시 update 쿼리로 바꿔치기
@SQLDelete(sql = "UPDATE users SET deleted = true, deleted_at = NOW() WHERE id = ?")
// 2. 조회 시 자동으로 삭제 안 된 것만 필터링 (Global Filter)
@Where(clause = "deleted = false") 
public class User {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true)
    private String email;

    private boolean deleted = false; // 삭제 여부 플래그

    private LocalDateTime deletedAt; // 삭제 일시
}
```

이제 `userRepository.deleteById(1L)`을 호출하면 `DELETE` 쿼리 대신 `UPDATE` 쿼리가 나갑니다. `findAll()`을 해도 삭제된 유저는 나오지 않습니다.

> **참고**: Hibernate 6.4 이상부터는 `@SoftDelete`라는 전용 애노테이션이 추가되어 더 간결하게 구현 가능합니다. (하지만 내부 동작 원리는 유사합니다.)

---

### 2. **치명적 문제: Unique Constraint 충돌 💥**

Soft Delete를 적용하면 데이터가 DB에 계속 남아있게 됩니다. 여기서 **Unique Key(이메일 중복 방지)**와 충돌이 발생합니다.

**시나리오:**
1.  `test@example.com` 유저가 가입함.
2.  이 유저가 탈퇴함 (Soft Delete -> DB에는 `deleted=true` 상태로 row가 남아있음).
3.  **동일한 이메일(`test@example.com`)로 재가입 시도.**
4.  **에러 발생 (`DataIntegrityViolationException`)**: DB Unique Index 입장에서는 이미 해당 이메일이 존재하기 때문입니다.

---

### 3. **해결책: Unique Index 설계 변경**

이 문제를 해결하려면 "삭제되지 않은 데이터끼리만 유니크해야 한다"는 조건이 필요합니다. DB 벤더별로 해결책이 다릅니다.

#### **방법 1: 복합 유니크 인덱스 (MySQL/MariaDB 공용)**

`email` 단독 유니크가 아니라, `(email, deleted)` 혹은 `(email, deleted_at)`을 묶어서 유니크로 잡는 방법입니다.

* 하지만 `deleted`가 `boolean`이면 `true/false` 두 가지 값밖에 없어서, **탈퇴를 2번 이상 한 유저**가 생기면 또 중복 에러가 납니다.
* 따라서 `deletedAt` (삭제 시간 Timestamp)을 활용하거나, 삭제 시 `email` 값을 `deleted_1234_test@example.com` 처럼 변경하는 방식을 써야 합니다.

#### **방법 2: Partial Index (MySQL 8.0+ / PostgreSQL)**

가장 깔끔한 방법입니다. **"deleted = false 인 행에 대해서만 유니크 제약 조건을 건다"**는 부분 인덱스를 생성합니다.

**MySQL 8.0+**
```sql
CREATE UNIQUE INDEX uk_users_email 
ON users (email) 
WHERE deleted = false; -- MySQL 8.0.13부터 지원하는 Functional Index 활용 가능 여부 확인 필요, 안되면 (email, (CASE WHEN deleted = 1 THEN NULL ELSE 1 END)) 처럼 우회
```

**PostgreSQL (추천)**
```sql
CREATE UNIQUE INDEX uk_users_email 
ON users (email) 
WHERE deleted = false;
```
이렇게 하면 삭제된 데이터(`deleted=true`)는 인덱스핑에서 제외되므로, 같은 이메일로 무한정 재가입이 가능합니다.

---

### 4. **주의사항: `@Where`의 양면성 🎭**

`@Where(clause = "deleted = false")`는 너무 강력해서 문제입니다.
* **문제**: 관리자 페이지(Admin)에서는 **탈퇴한 회원도 조회**해야 하는데, `userRepository.findAll()`을 하면 무조건 필터링되어 버립니다.
* **해결**:
    1.  **Native Query 사용**: `@Where`는 JPQL/엔티티 조회에만 적용되므로, `nativeQuery = true`로 조회하면 무시하고 다 가져올 수 있습니다.
    2.  **별도 조회용 엔티티 분리**: `User` 엔티티 외에 `UserHistory`나 `AdminUserView` 같은 엔티티를 따로 만들어서 `@Where` 없이 매핑합니다.

---

## 💡 배운 점

1.  **지우는 척만 하기**: "데이터는 자산이다"라는 관점에서, 물리 삭제보다는 논리 삭제가 운영상 훨씬 안전함을 깨달았습니다. 하지만 그에 따른 스토리지 비용 증가는 감수해야 합니다.
2.  **DB 제약 조건의 디테일**: 단순히 애플리케이션 코드만 수정해서 끝날 일이 아니라, DB의 인덱스 구조까지 함께 고민해야 비즈니스 요구사항(재가입 허용)을 충족할 수 있다는 것을 알았습니다.
3.  **마법은 없다**: `@Where`가 편하긴 하지만, 전역적으로 적용되는 필터는 예외 케이스(관리자 기능)를 구현할 때 오히려 족쇄가 될 수 있음을 유의해야 합니다.

---

## 🔗 참고 자료

-   [Hibernate User Guide - Soft Delete](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#soft-delete)
-   [Implementing Soft Delete in Spring Boot](https://www.baeldung.com/spring-boot-hibernate-soft-delete)
-   [Unique Constraints with Soft Deletes](https://vladmihalcea.com/hibernate-soft-delete-unique-constraint/)