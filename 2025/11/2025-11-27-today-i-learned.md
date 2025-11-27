---
title: "Hibernate Envers: 데이터 변경 이력(Audit Log) 자동화하기"
date: 2025-11-27
categories: [Java, Spring, JPA]
tags: [Hibernate Envers, JPA, Auditing, History, Spring Data Envers, TIL]
excerpt: "단순한 생성/수정 시간 기록(@CreatedDate)을 넘어, 데이터가 변경될 때마다 과거 상태를 스냅샷으로 저장하여 완벽한 이력을 관리하는 Hibernate Envers의 사용법을 학습합니다. @Audited 애노테이션 적용부터 커스텀 RevisionEntity를 이용해 수정자 정보를 기록하는 방법까지 알아봅니다."
author_profile: true
---

# Today I Learned: Hibernate Envers: 데이터 변경 이력(Audit Log) 자동화하기

## 📚 오늘 학습한 내용

서비스를 운영하다 보면 "이 데이터, 어제는 값이 뭐였지?", "누가 이 주문 상태를 변경했지?"와 같은 질문에 답해야 할 때가 많습니다. 단순히 `created_at`, `updated_at` 컬럼만으로는 **'변경 전의 값'**을 알 수 없습니다.

이를 위해 별도의 히스토리 테이블(`order_history`)을 만들고 비즈니스 로직마다 `insert` 코드를 추가하는 것은 매우 번거롭고 실수하기 쉬운 작업입니다. 오늘은 이 문제를 해결하기 위해 JPA 스펙의 구현체인 Hibernate가 제공하는 강력한 도구, **Hibernate Envers**를 적용하는 방법을 학습했습니다.

---

### 1. **Hibernate Envers란? 🕰️**

Envers는 엔티티의 **모든 변경 이력(버전)**을 자동으로 추적하고 기록해주는 Hibernate의 모듈입니다.

-   **동작 방식**: `@Audited`가 붙은 엔티티에 변경(INSERT, UPDATE, DELETE)이 발생하면, Hibernate가 자동으로 해당 엔티티의 변경 시점 데이터를 **Audit 테이블(`_AUD` 접미사)**에 저장합니다.
-   **장점**: 비즈니스 로직에 히스토리 저장 코드를 단 한 줄도 작성할 필요가 없습니다.

---

### 2. **Spring Boot에 적용하기**

#### **Step 1: 의존성 추가**
`spring-data-envers`를 추가하면 Spring Data JPA와 통합된 기능을 사용할 수 있습니다.

```groovy
implementation 'org.springframework.data:spring-data-envers'
```

#### **Step 2: `@EnableJpaRepositories` 설정**
Spring Data JPA가 Envers 리포지토리 구현체를 사용하도록 설정해야 합니다.

```java
@Configuration
@EnableJpaRepositories(
    basePackages = "com.example.repository",
    repositoryFactoryBeanClass = EnversRevisionRepositoryFactoryBean.class // 핵심 설정
)
public class JpaConfig { }
```

#### **Step 3: 엔티티에 `@Audited` 적용**
이력을 관리하고 싶은 엔티티나 필드에 애노테이션을 붙입니다.

```java
@Entity
@Getter
@Audited // 이 엔티티의 모든 필드 변경 이력을 'member_AUD' 테이블에 저장
public class Member {
    @Id @GeneratedValue
    private Long id;

    private String name;

    @NotAudited // 이 필드는 이력 관리에서 제외
    private String password;
}
```
> 애플리케이션을 실행하면, Hibernate가 자동으로 `member_aud` 테이블과 이력 정보(버전 번호, 시간)를 관리하는 `revinfo` 테이블을 생성합니다.

---

### 3. **"누가" 바꿨는지 기록하기: Custom RevisionEntity**

기본 설정만으로는 "언제(Timestamp)" 바뀌었는지는 알 수 있지만, **"누가(User ID)"** 바꿨는지는 알 수 없습니다. 이를 위해 `RevisionEntity`를 커스텀해야 합니다.

**1. Custom Revision Entity 정의**
```java
@Entity
@RevisionEntity(UserRevisionListener.class) // 리스너 연결
@Getter
@Setter
public class UserRevisionEntity extends DefaultRevisionEntity {
    // 기본 revinfo 테이블(id, timestamp)에 userId 컬럼을 추가
    private String userId;
}
```

**2. Revision Listener 구현**
변경이 발생할 때마다 현재 로그인한 사용자 정보를 가져와서 넣어주는 리스너입니다.

```java
public class UserRevisionListener implements RevisionListener {
    @Override
    public void newRevision(Object revisionEntity) {
        UserRevisionEntity entity = (UserRevisionEntity) revisionEntity;
        
        // Spring Security Context 등에서 현재 사용자 ID 추출
        String currentUserId = SecurityContextHolder.getContext().getAuthentication().getName();
        
        entity.setUserId(currentUserId);
    }
}
```

---

### 4. **이력 데이터 조회하기**

Spring Data Envers를 사용하면 리포지토리 인터페이스에서 손쉽게 이력을 조회할 수 있습니다.

```java
public interface MemberRepository extends JpaRepository<Member, Long>, 
                                          RevisionRepository<Member, Long, Integer> { // 상속 추가
}
```

**서비스 코드 사용 예시**
```java
@Service
@RequiredArgsConstructor
public class MemberService {
    private final MemberRepository memberRepository;

    @Transactional(readOnly = true)
    public void printHistory(Long memberId) {
        // 해당 멤버의 모든 변경 이력 조회
        Revisions<Integer, Member> revisions = memberRepository.findRevisions(memberId);

        for (Revision<Integer, Member> revision : revisions) {
            Member memberSnapshot = revision.getEntity(); // 그 당시의 데이터 스냅샷
            Integer revisionNumber = revision.getRevisionNumber().orElse(-1);
            LocalDateTime revisionDate = revision.getRevisionInstant()
                                                 .map(inst -> LocalDateTime.ofInstant(inst, ZoneId.systemDefault()))
                                                 .orElse(null);
            
            System.out.printf("Ver: %d, Date: %s, Name: %s\n", 
                              revisionNumber, revisionDate, memberSnapshot.getName());
        }
    }
}
```

---

## 💡 배운 점

1.  **생산성의 혁신**: 기존에 수동으로 히스토리 테이블을 만들고 `insert` 쿼리를 짜던 방식에 비해, 애노테이션 하나로 완벽한 스냅샷을 남길 수 있다는 점이 놀라웠습니다. 특히 **삭제된 데이터**까지도 추적할 수 있다는 점은 큰 장점입니다.
2.  **공간 복잡도와의 트레이드오프**: 모든 변경 사항을 스냅샷으로 저장하므로, 변경이 잦은 테이블에 적용하면 DB 용량이 급격히 증가할 수 있습니다. `@Audited`를 필요한 엔티티나 필드에만 선별적으로 적용하는 전략이 필수적입니다.
3.  **연관관계 매핑 주의**: `@Audited`가 붙은 엔티티가 다른 엔티티와 연관관계를 맺고 있다면, 연관된 엔티티도 `@Audited`가 붙어 있어야 오류가 나지 않습니다. (`RelationTargetAuditMode.NOT_AUDITED`로 회피 가능하지만 주의 필요). Envers는 단순한 감사 로그용이지, 복잡한 비즈니스 로직용으로 사용하기에는 조회 쿼리가 무거울 수 있음을 인지해야 합니다.

---

## 🔗 참고 자료

-   [Hibernate Envers Documentation](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#envers)
-   [Spring Data Envers Reference](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#jpa.envers)
-   [Auditing with JPA, Hibernate, and Spring Data JPA (Baeldung)](https://www.baeldung.com/database-auditing-jpa)