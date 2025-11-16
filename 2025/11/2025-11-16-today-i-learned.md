---
title: "Spring Data JPA Auditing: `@CreatedDate`와 `@LastModifiedBy`로 생성/수정자 자동화하기"
date: 2025-11-16
categories: [Java, Spring]
tags: [Spring Data JPA, Auditing, @CreatedDate, @MappedSuperclass, AuditorAware, TIL]
excerpt: "모든 JPA 엔티티에 반복적으로 들어가는 생성/수정 시간 및 생성/수정자 필드를 Spring Data JPA Auditing 기능으로 자동화하는 방법을 학습합니다. @EnableJpaAuditing, @EntityListeners, 그리고 AuditorAware 빈 등록의 원리를 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Data JPA Auditing: `@CreatedDate`와 `@LastModifiedBy`로 생성/수정자 자동화하기

## 📚 오늘 학습한 내용

대부분의 엔티티에 `createdAt`, `modifiedAt`, `createdBy` 같은 공통 필드를 선언해왔습니다. 하지만 이 필드들을 관리하는 방식은 늘 고민이었습니다.

-   **문제점**: `save()` 메서드를 호출할 때마다 서비스 로직에서 `entity.setCreatedAt(LocalDateTime.now())`나 `entity.setCreatedBy(SecurityUtil.getUserId())` 같은 코드를 반복적으로 작성해야 했습니다.
-   **결과**: 비즈니스 로직과 기술적인 감사(Auditing) 로직이 강하게 결합되고, 개발자가 이 코드를 누락할 경우 데이터 무결성이 깨지는 위험이 있었습니다.

오늘은 이 문제를 AOP 기반으로 우아하게 해결해주는 **Spring Data JPA Auditing** 기능에 대해 학습했습니다.

---

### 1. **JPA Auditing 이란?**

JPA Auditing은 엔티티가 생성되거나 수정될 때, 이를 **자동으로 감지**하여 **시간과 사용자 정보를 기록**해주는 기능입니다. Spring Data JPA는 이 기능을 `@EnableJpaAuditing`과 몇 가지 애노테이션으로 매우 간단하게 활성화할 수 있습니다.

---

### 2. **적용 단계 (Step-by-Step)**

#### **Step 1: `@EnableJpaAuditing` 활성화**
먼저, Spring Boot 메인 애플리케이션 클래스에 `@EnableJpaAuditing`을 추가하여 Auditing 기능을 활성화합니다.

```java
@EnableJpaAuditing // JPA Auditing 기능 활성화
@SpringBootApplication
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}
```

#### **Step 2: 공통 베이스 엔티티 생성 (`@MappedSuperclass`)**
반복되는 필드들을 담을 추상 클래스를 만듭니다. `@MappedSuperclass`를 사용하면, 이 클래스는 테이블로 매핑되지는 않지만, 이 클래스를 상속받는 자식 엔티티에게 필드들만 물려줄 수 있습니다.

```java
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import jakarta.persistence.Column;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.MappedSuperclass;
import java.time.LocalDateTime;

@Getter
@MappedSuperclass // 1. 공통 매핑 정보가 필요할 때 사용
@EntityListeners(AuditingEntityListener.class) // 2. Auditing 기능을 엔티티에 적용
public abstract class BaseTimeEntity {

    @CreatedDate // 3. 엔티티 생성 시 시간이 자동 저장
    @Column(updatable = false) // 생성 시간은 수정되면 안 됨
    private LocalDateTime createdAt;

    @LastModifiedDate // 4. 엔티티 수정 시 시간이 자동 저장
    private LocalDateTime modifiedAt;
}
```
> `BaseTimeEntity`만 상속받으면, `@CreatedDate`와 `@LastModifiedDate`가 붙은 필드는 `AuditingEntityListener`에 의해 자동으로 관리됩니다.

#### **Step 3: 생성/수정자 정보 추가 (`AuditorAware`)**
`@CreatedBy`, `@LastModifiedBy`는 누가 이 작업을 했는지(e.g., 사용자 ID)를 등록해야 합니다. 하지만 Spring은 현재 로그인한 사용자가 누구인지 알 수 없습니다.

**`AuditorAware<T>`** 인터페이스는 Spring Security 컨텍스트 등에서 **현재 사용자의 정보를 가져와 Auditing 기능에 제공**하는 '다리' 역할을 합니다.

```java
import org.springframework.data.domain.AuditorAware;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

import java.util.Optional;

@Component // 1. Spring Bean으로 등록
public class SecurityAuditorAware implements AuditorAware<String> { // T는 반환 타입 (e.g., Long or String)

    @Override
    public Optional<String> getCurrentAuditor() {
        // 2. Spring Security 컨텍스트에서 인증 정보(Authentication)를 가져옴
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null || !authentication.isAuthenticated() || authentication.getPrincipal() instanceof String) {
            // 인증 정보가 없거나, 익명 사용자(anonymousUser)일 경우 null 반환
            return Optional.empty(); 
        }

        // 3. (예시) Principal이 UserDetails 구현체일 경우 사용자 ID 반환
        // UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        // return Optional.of(userDetails.getUsername());
        
        // (예시) Principal이 사용자 ID(String)를 바로 반환할 경우
        return Optional.of(authentication.getName());
    }
}
```
> `SecurityAuditorAware`가 빈으로 등록되어 있으면, `AuditingEntityListener`는 이 빈을 사용하여 `@CreatedBy`, `@LastModifiedBy` 필드를 자동으로 채웁니다.

#### **Step 4: 실제 엔티티에 상속 적용**
`BaseTimeEntity`를 상속받고, `@CreatedBy` 등을 추가한 `BaseEntity`를 만들어 상속받게 할 수도 있습니다.

```java
// ...
import org.springframework.data.annotation.CreatedBy;
import org.springframework.data.annotation.LastModifiedBy;

@Getter
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
public abstract class BaseEntity extends BaseTimeEntity { // 1. 시간 정보 상속

    @CreatedBy // 2. 생성자 자동 저장
    @Column(updatable = false)
    private String createdBy; // AuditorAware<String>의 반환 타입과 일치해야 함

    @LastModifiedBy // 3. 수정자 자동 저장
    private String modifiedBy;
}

// Post.java
@Entity
public class Post extends BaseEntity { // 4. BaseEntity만 상속
    @Id
    @GeneratedValue
    private Long id;

    private String title;
    private String content;
    
    // ...
}
```

이제 `postRepository.save(new Post())`를 호출하면, 서비스 로직에 아무 코드가 없어도 `createdAt`, `createdBy` 등이 자동으로 채워져 INSERT 쿼리가 실행됩니다.

---

## 💡 배운 점

1.  **비즈니스 로직과 인프라 로직의 완벽한 분리**: Auditing은 명백히 '인프라/공통' 로직입니다. `@MappedSuperclass`와 `@EntityListeners`를 사용함으로써, 서비스 계층에서 `setCreatedAt` 같은 코드를 완전히 몰아내고 순수한 비즈니스 로직에만 집중할 수 있게 되었습니다.
2.  **`AuditorAware`는 '전략 패턴'의 구현체다**: Spring Security가 현재 사용자를 아는 방식과, JPA Auditing이 사용자를 필요로 하는 방식은 다릅니다. `AuditorAware`는 이 둘 사이를 연결해주는 '전략(Strategy)'을 주입하는 방식으로, Spring의 유연한 설계 사상을 엿볼 수 있었습니다.
3.  **`@MappedSuperclass`의 유용성**: 상속 관계 매핑(e.g., `Joined`, `Single Table`)은 테이블 구조에 영향을 주지만, `@MappedSuperclass`는 단순히 **"필드만 물려주고 테이블은 만들지 마라"**는 의미로, 공통 필드를 관리하기에 가장 가볍고 이상적인 방법임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Data JPA Docs - Auditing](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#auditing)
-   [JPA @MappedSuperclass (Baeldung)](https.baeldung.com/jpa-mapped-superclass)
-   [Spring Security and JPA Auditing (Baeldung)](https.baeldung.com/spring-security-auditor-aware)