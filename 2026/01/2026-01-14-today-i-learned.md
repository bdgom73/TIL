---
title: "데이터 변경 이력 자동화: Hibernate Envers로 '누가, 언제, 무엇을' 바꿨는지 추적하기"
date: 2026-01-14
categories: [Spring, JPA, Database]
tags: [Hibernate Envers, Auditing, JPA, History, RevisionEntity, Data Tracking, TIL]
excerpt: "운영 툴이나 CS 처리를 위해 데이터의 변경 이력(History)을 남겨야 할 때, 직접 히스토리 테이블을 설계하고 로직을 짜는 대신 Hibernate Envers를 도입합니다. 엔티티 버전 관리 자동화부터, SecurityContext와 연동하여 '수정한 사람'까지 기록하는 심화 설정 방법을 학습합니다."
author_profile: true
---

# Today I Learned: 데이터 변경 이력 자동화: Hibernate Envers로 '누가, 언제, 무엇을' 바꿨는지 추적하기

## 📚 오늘 학습한 내용

서비스를 운영하다 보면 "이 데이터 갑자기 왜 바뀌었어?", "지난주 금요일 기준으로는 값이 뭐였어?"라는 질문을 자주 받습니다.
기존에는 `Member` 테이블과 `MemberHistory` 테이블을 따로 만들고, 비즈니스 로직에서 `save()` 할 때마다 히스토리 객체도 같이 저장하는 노가다성 코드를 짰습니다.

오늘은 JPA 표준 구현체인 Hibernate가 제공하는 **Envers** 모듈을 사용하여, 애노테이션 하나로 **데이터 변경 이력을 자동으로 적재하고 조회하는 방법**을 학습했습니다.

---

### 1. **Hibernate Envers란? 🕰️**

Hibernate Envers는 엔티티의 영속성 생명주기(Insert, Update, Delete)를 감지하여, 별도의 이력 테이블(Audit Table)에 변경 내역을 자동으로 저장해주는 모듈입니다.

-   **동작 방식**: `Member` 엔티티에 `@Audited`를 붙이면, DB에 `member_aud` 테이블을 자동으로 생성하고, 원본 데이터가 변경될 때마다 스냅샷을 저장합니다.
-   **장점**: 비즈니스 로직에 히스토리 저장 코드가 섞이지 않아 **OCP(Open Closed Principle)**를 준수할 수 있습니다.

---

### 2. **Spring Boot 적용 및 커스터마이징**

단순히 시간(`timestamp`)만 저장하는 기본 설정은 실무에서 부족합니다. **"누가(userId)"** 변경했는지를 남기는 것이 핵심입니다.

#### **Step 1: 의존성 추가**

```groovy
implementation 'org.springframework.data:spring-data-envers'
```

#### **Step 2: 커스텀 RevisionEntity 정의**

Envers는 기본적으로 `REVINFO` 테이블에 `REV`(버전 ID), `REVTSTMP`(시간)을 저장합니다. 여기에 `operatorId` 컬럼을 확장합니다.

```java
@Entity
@RevisionEntity(UserRevisionListener.class) // 리스너 등록
@Getter
@Setter
@Table(name = "REVINFO_CUSTOM")
public class CustomRevisionEntity extends DefaultRevisionEntity {

    private String operatorId; // 변경한 사람 ID
}
```

#### **Step 3: RevisionListener 구현**

변경이 감지될 때 실행되는 리스너에서, Spring SecurityContext의 유저 정보를 꺼내 `operatorId`에 주입합니다.

```java
public class UserRevisionListener implements RevisionListener {

    @Override
    public void newRevision(Object revisionEntity) {
        CustomRevisionEntity customRevision = (CustomRevisionEntity) revisionEntity;
        
        // 현재 로그인한 사용자 정보 가져오기
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        
        if (auth != null) {
            customRevision.setOperatorId(auth.getName());
        } else {
            customRevision.setOperatorId("SYSTEM"); // 배치나 스케줄러에 의한 변경
        }
    }
}
```

#### **Step 4: 엔티티 적용**

```java
@Entity
@Audited // 이 클래스의 모든 필드를 이력 관리함
// @Audited(withModifiedFlag = true) // 어떤 컬럼이 바뀌었는지 boolean 플래그도 같이 저장
public class Product {
    
    @Id @GeneratedValue
    private Long id;
    
    private String name;
    
    @NotAudited // 이력 관리에서 제외하고 싶을 때
    private String simpleDescription;
}
```

---

### 3. **이력 조회하기 (Time Travel) ⏳**

단순히 쌓는 것뿐만 아니라, 특정 시점의 데이터를 복원하거나 변경 내역을 조회해야 합니다. `AuditReader`를 사용합니다.

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AuditService {

    private final EntityManager entityManager;

    public void getProductHistory(Long productId) {
        AuditReader reader = AuditReaderFactory.get(entityManager);

        // 1. 특정 ID의 모든 변경 이력 조회
        List<Number> revisions = reader.getRevisions(Product.class, productId);

        for (Number rev : revisions) {
            // 해당 리비전 당시의 엔티티 상태 조회
            Product oldProduct = reader.find(Product.class, productId, rev);
            
            // 해당 리비전의 메타데이터(시간, 작업자) 조회
            CustomRevisionEntity meta = reader.findRevision(CustomRevisionEntity.class, rev);
            
            System.out.println("Rev: " + rev + ", Worker: " + meta.getOperatorId() + ", Name: " + oldProduct.getName());
        }
    }
}
```

---

### 4. **주의사항 및 한계 ⚠️**

1.  **스키마 관리**: Envers는 `_AUD` 테이블을 자동으로 생성하려고 합니다. 운영 환경에서는 DDL Auto를 끄기 때문에, 반드시 `_AUD` 테이블(`REVTYPE`, `REV` 컬럼 포함)에 대한 DDL도 직접 작성해서 배포해야 합니다.
2.  **연관 관계**: `@OneToMany` 관계를 가진 엔티티를 Auditing 할 때, 연관된 엔티티도 `@Audited`가 붙어있지 않으면 에러가 발생할 수 있습니다. 불필요하게 많은 데이터가 쌓이지 않도록 `@NotAudited`를 적절히 섞어야 합니다.
3.  **대용량 트래픽**: 변경이 매우 빈번한 테이블(예: 조회수 카운트, 실시간 위치)에 Envers를 걸면 쓰기 성능이 2배로 느려지고 DB 용량이 폭발합니다. **중요한 설정 정보(Config)나 정산 데이터** 같은 곳에만 선별적으로 적용해야 합니다.

---

## 💡 배운 점

1.  **개발 생산성**: 히스토리 테이블을 위한 DTO 변환, INSERT 쿼리 작성 등 지루한 작업이 싹 사라졌습니다. 핵심 비즈니스 로직에만 집중할 수 있게 되었습니다.
2.  **디버깅의 신**: "어제 오후 2시에 누가 이 상품 가격을 0원으로 바꿨어?"라는 질문에 로그를 뒤질 필요 없이 DB 쿼리 한 번으로 범인(?)과 시점을 특정할 수 있어 운영 대응력이 비약적으로 상승했습니다.
3.  **데이터 복구 전략**: 잘못된 Update가 발생했을 때, `_AUD` 테이블의 직전 리비전 데이터를 조회해서 원복(Rollback)시키는 API를 만들기도 매우 수월해졌습니다.

---

## 🔗 참고 자료

-   [Hibernate Envers Documentation](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#envers)
-   [Spring Data Envers Reference](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#jpa.auditing)
-   [Tracking User with Envers (Baeldung)](https://www.baeldung.com/hibernate-envers)