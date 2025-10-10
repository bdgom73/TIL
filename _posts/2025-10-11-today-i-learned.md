---
title: "QueryDSL을 활용한 동적 쿼리와 Projection 최적화"
date: 2025-10-11
categories: [Java, Spring]
tags: [QueryDSL, JPA, Spring Data, Dynamic Query, Projection, TIL]
excerpt: "Spring Data JPA의 한계를 넘어, QueryDSL을 사용하여 복잡한 검색 조건에 대응하는 동적 쿼리(Dynamic Query)를 타입-세이프(Type-Safe)하게 작성하는 방법을 학습합니다. 또한, DTO 프로젝션을 통해 조회 성능을 최적화하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: QueryDSL을 활용한 동적 쿼리와 Projection 최적화

## 📚 오늘 학습한 내용

Spring Data JPA의 메서드 이름 기반 쿼리 생성 기능은 매우 편리하지만, 검색 조건이 다양해지고 복잡해지는 실무 환경에서는 한계에 부딪힙니다. 예를 들어, 사용자의 이름, 나이, 도시 등 여러 조건이 선택적으로(optional) 들어오는 검색 API를 구현할 때, 모든 경우의 수에 대한 메서드를 만들거나 복잡한 JPQL 문자열을 조립하는 것은 매우 비효율적이고 오류 발생 가능성이 높습니다.

오늘은 이러한 **동적 쿼리(Dynamic Query)** 문제를 해결하고, 조회 성능까지 최적화할 수 있는 강력한 도구인 **QueryDSL**에 대해 학습했습니다.

---

### 1. **왜 QueryDSL이 필요한가?**

-   **타입-세이프(Type-Safe)**: JPQL은 단순한 문자열이기 때문에, 컴파일 시점에는 오타나 문법 오류를 잡을 수 없고 런타임에러로 이어집니다. QueryDSL은 자바 코드로 쿼리를 작성하므로, 컴파일 시점에 모든 오류를 발견할 수 있어 안정성이 매우 높습니다.
-   **동적 쿼리 작성의 용이성**: `if`문과 같은 자바 코드를 활용하여 조건에 따라 동적으로 쿼리의 `where` 절을 손쉽게 구성할 수 있습니다.
-   **직관적인 코드와 자동 완성**: 복잡한 쿼리도 마치 자바 코드를 짜듯이 술술 작성할 수 있으며, IDE의 자동 완성 기능을 100% 활용할 수 있어 생산성이 향상됩니다.

---

### 2. **QueryDSL을 이용한 동적 쿼리 구현**

사용자 검색 기능 예시: 이름(username)과 나이(age)를 선택적으로 입력받아 검색

**1. Q-Type 클래스 생성**
QueryDSL을 사용하려면 먼저 엔티티를 기반으로 한 Q-Type 클래스가 필요합니다. Gradle의 `annotationProcessor` 설정을 통해 컴파일 시점에 자동으로 생성할 수 있습니다. (`QUser.java` 등)

**2. Repository 커스텀 구현**
Spring Data JPA 리포지토리에서 QueryDSL을 사용하기 위해 커스텀 리포지토리 인터페이스와 구현체를 만듭니다.

```java
// 1. 커스텀 인터페이스 정의
public interface MemberRepositoryCustom {
    List<Member> findBySearchCondition(MemberSearchCondition condition);
}

// 2. 커스텀 구현체 작성
// 클래스 이름 끝에 'Impl'을 붙여야 Spring Data JPA가 자동으로 인식합니다.
@Repository
@RequiredArgsConstructor
public class MemberRepositoryCustomImpl implements MemberRepositoryCustom {
    
    private final JPAQueryFactory queryFactory;

    @Override
    public List<Member> findBySearchCondition(MemberSearchCondition condition) {
        return queryFactory
                .selectFrom(member) // QMember.member를 static import
                .where(
                    usernameEq(condition.getUsername()),
                    ageGoe(condition.getAgeGoe()),
                    ageLoe(condition.getAgeLoe())
                )
                .fetch();
    }
    
    // BooleanExpression을 사용하면 조건을 재사용하고 조합하기 용이하다.
    private BooleanExpression usernameEq(String username) {
        return hasText(username) ? member.username.eq(username) : null;
    }
    
    private BooleanExpression ageGoe(Integer ageGoe) {
        return ageGoe != null ? member.age.goe(ageGoe) : null;
    }
    
    private BooleanExpression ageLoe(Integer ageLoe) {
        return ageLoe != null ? member.age.loe(ageLoe) : null;
    }
}

// 3. 메인 리포지토리에 커스텀 인터페이스 상속
public interface MemberRepository extends JpaRepository<Member, Long>, MemberRepositoryCustom {
}
```
> `where` 절에 `null`이 전달되면 해당 조건은 무시됩니다. 이를 활용하여 `if`문 없이도 깔끔하게 동적 쿼리를 구성할 수 있습니다.

---

### 3. **성능 최적화: DTO 프로젝션(Projection)**

JPA로 엔티티를 조회하면, 영속성 컨텍스트가 관리하는 상태가 되므로 편리하지만, 단순히 화면에 보여줄 데이터만 필요한 경우에는 불필요한 오버헤드가 발생할 수 있습니다. QueryDSL의 프로젝션 기능을 사용하면 처음부터 **엔티티가 아닌 DTO로 직접 조회**하여 성능을 최적화할 수 있습니다.

```java
// MemberDto.java
@Data
public class MemberDto {
    private String username;
    private int age;

    @QueryProjection // 생성자에 애노테이션 추가 후 Q-Type 다시 생성
    public MemberDto(String username, int age) {
        this.username = username;
        this.age = age;
    }
}

// Repository 구현체
public List<MemberDto> findDtoBySearchCondition(MemberSearchCondition condition) {
    return queryFactory
            .select(new QMemberDto(member.username, member.age)) // DTO로 직접 조회
            .from(member)
            .where(...)
            .fetch();
}
```
> **장점**:
> - **영속성 컨텍스트를 거치지 않음**: 불필요한 스냅샷 생성 및 관리 비용이 없습니다.
> - **필요한 컬럼만 조회**: `select` 절에 명시된 컬럼만 DB에서 가져오므로 네트워크 I/O가 감소합니다.

---

## 💡 배운 점

1.  **문자열 쿼리의 시대는 끝났다**: JPQL이나 MyBatis의 XML에 쿼리 문자열을 작성하며 겪었던 수많은 런타임 에러와 `if` 태그의 향연을 생각하면, QueryDSL의 타입-세이프(Type-Safe)한 동적 쿼리 작성 방식은 개발 안정성과 생산성을 극적으로 향상시키는 혁신임을 깨달았습니다.
2.  **JPA와 QueryDSL은 최고의 파트너다**: 단순한 CRUD는 Spring Data JPA의 기본 기능으로 해결하고, 복잡한 조회 쿼리는 QueryDSL로 구현하는 것이 가장 이상적인 조합입니다. 커스텀 리포지토리를 통해 두 기술을 자연스럽게 함께 사용할 수 있습니다.
3.  **조회 성능은 프로젝션에서 시작된다**: 복잡한 조회 API일수록 엔티티 전체를 조회하는 것은 성능에 큰 부담을 줍니다. QueryDSL의 DTO 프로젝션은 DB와 애플리케이션 양쪽의 부하를 줄여주는 매우 효과적이고 실용적인 최적화 기법임을 알게 되었습니다.

---

## 🔗 참고 자료

-   [QueryDSL 공식 문서](http://querydsl.com/static/querydsl/latest/reference/html_single/)
-   [Spring Data JPA - Custom Implementations](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#repositories.custom-implementations)
-   [Querydsl 레퍼런스 가이드 (인프런 김영한님)](https://www.inflearn.com/product/querydsl)