---
title: "JPA에서 생성자 주입을 사용하는 이유"
date: 2025-09-14
categories: [Spring Boot, JPA, Java]
tags: [Spring, Spring Boot, JPA, Constructor Injection, Dependency Injection]
excerpt: "JPA에서 생성자 주입을 사용하는 이유와 장점에 대해 알아봅니다."
author_profile: true
---

### TIL: JPA에서 생성자 주입을 사용하는 이유

JPA (Java Persistence API)에서 엔티티 객체를 생성할 때, 필드 주입 대신 생성자 주입을 사용하는 것이 권장됩니다.  이번 TIL에서는 그 이유와 장점에 대해 알아보겠습니다.

#### 1. 불변성 확보

생성자 주입을 사용하면 객체 생성 시 필수적인 의존성을 모두 주입받아야 합니다. 이는 객체의 상태가 생성 이후 변경되지 않도록 보장하여 불변성을 확보하는 데 도움이 됩니다.  불변 객체는 다중 스레드 환경에서 안전하게 사용될 수 있으며, 예측 가능한 동작을 보장합니다.

#### 2. 순환 의존성 방지

필드 주입을 사용하는 경우, 순환 의존성 문제가 발생할 수 있습니다.  생성자 주입을 사용하면 컴파일 시점에 순환 의존성을 감지할 수 있으므로, 이러한 문제를 미리 예방할 수 있습니다.

#### 3. 테스트 용이성 향상

생성자 주입을 사용하면 테스트 코드에서 Mock 객체를 주입하기 용이합니다.  필드 주입을 사용하는 경우, Reflection API를 사용해야 하거나, 별도의 Setter 메서드를 제공해야 하는 등 테스트 코드 작성이 복잡해질 수 있습니다.

#### 4. 코드 가독성 및 유지보수성 향상

생성자 주입을 사용하면 객체의 의존성을 명확하게 파악할 수 있습니다.  이는 코드 가독성을 높이고 유지보수를 용이하게 합니다.


#### 예시

```java
@Entity
public class Member {

    @Id
    @GeneratedValue
    private Long id;

    private String name;

    @ManyToOne
    private Team team;

    // 기본 생성자 (JPA 스펙 요구사항)
    protected Member() {}

    // 생성자를 통한 주입
    public Member(String name, Team team) {
        this.name = name;
        this.team = team;
    }

    // ... getter 메서드 ...
}
```

#### 결론

JPA에서 생성자 주입을 사용하면 불변성 확보, 순환 의존성 방지, 테스트 용이성 향상, 코드 가독성 및 유지보수성 향상 등 다양한 이점을 얻을 수 있습니다. 따라서 엔티티 객체를 생성할 때는 필드 주입 대신 생성자 주입을 사용하는 것이 좋습니다.
