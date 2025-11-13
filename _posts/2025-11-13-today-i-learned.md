---
title: "Spring Expression Language (SpEL) 탐구: 단순한 @Value를 넘어"
date: 2025-11-13
categories: [Spring, Core]
tags: [Spring Expression Language, SpEL, @Value, @PreAuthorize, @Cacheable, TIL]
excerpt: "Spring의 @Value, @PreAuthorize, @Cacheable 등 강력한 애노테이션의 이면에서 동작하는 'Spring Expression Language (SpEL)'의 문법과 동작 원리를 학습합니다. 단순한 프로퍼티 주입(${...})을 넘어, 런타임에 빈(Bean)의 메서드를 호출하고 동적인 로직을 수행하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Expression Language (SpEL) 탐구: 단순한 @Value를 넘어

## 📚 오늘 학습한 내용

`@Value("${my.property}")`로 설정을 주입받거나, `@PreAuthorize("hasRole('ADMIN')")`로 보안을 설정하고, `@Cacheable(key = "#userId")`로 캐시 키를 동적으로 생성하는 데 익숙했습니다. 하지만 이 애노테이션들 안에서 사용되는 `${...}`와 `#{...}`의 차이가 무엇인지, 그리고 `#{...}` 문법이 정확히 어떻게 동작하는지 깊이 있게 알지 못했습니다.

오늘은 이 모든 것의 기반이 되는 **Spring Expression Language (SpEL)**, 즉 스프링 표현식 언어에 대해 제대로 학습했습니다.

---

### 1. **가장 큰 오해: `${...}` vs. `#{...}` ⚡️**

가장 먼저 바로잡아야 할 개념은 이 둘의 차이였습니다.

-   **`${...}` (Property Placeholder, 프로퍼티 플레이스홀더)**
    -   이것은 SpEL이 **아닙니다.**
    -   `application.yml`이나 환경 변수 등 Spring `Environment`에 등록된 **프로퍼티(설정값)를 찾아 주입**하는 기능입니다.
    -   Spring 컨테이너가 빈(Bean)을 정의하는 시점(초기 로딩 시)에 값으로 치환됩니다.

-   **`#{...}` (SpEL, 스프링 표현식 언어)**
    -   이것이 **진짜 SpEL**입니다.
    -   단순한 값 치환이 아니라, **런타임에 실행되는 코드**입니다.
    -   다른 빈(Bean)을 참조하거나, 메서드를 호출하고, 연산을 수행하는 등 프로그래밍적인 로직을 수행할 수 있습니다.

**예시 비교:**
```java
@Component
public class MyComponent {
    
    // 1. 프로퍼티 주입: application.yml의 my.server.port 값을 주입
    @Value("${my.server.port}")
    private int port; 
    
    // 2. SpEL: 'systemProperties'라는 내장 빈에서 'java.version' 키의 값을 읽어옴
    @Value("#{ systemProperties['java.version'] }")
    private String javaVersion;
    
    // 3. SpEL: 다른 빈(@myService)의 메서드를 호출한 결과를 주입
    @Value("#{ @myService.getDefaultValue() }")
    private String defaultValue;
    
    // 4. SpEL: 정적 값 또는 연산
    @Value("#{ 1 + 1 }") // 2가 주입됨
    private int two;
}
```

---

### 2. **SpEL은 어디에 활용되는가? (3대 활용처)**

SpEL은 Spring 생태계 전반에서 '동적인' 로직을 처리하는 데 사용됩니다.

#### **1. `@Value`: 동적인 값 주입**
위 예시처럼 정적인 프로퍼티 외에, 다른 빈의 메서드 호출 결과나 시스템 프로퍼티, 또는 간단한 연산 결과를 주입할 때 사용합니다.

#### **2. `@Cacheable` / `@CacheEvict`: 동적인 캐시 키 생성**
메서드의 파라미터를 기반으로 캐시 키를 동적으로 생성할 때 SpEL이 필수적입니다.

```java
@Service
public class UserService {
    
    // 파라미터 'userId'를 캐시 키로 사용
    @Cacheable(cacheNames = "user", key = "#userId")
    public UserDto getUserById(Long userId) {
        // ...
    }
    
    // DTO 객체 내부의 필드를 키로 사용
    @CacheEvict(cacheNames = "user", key = "#dto.userId")
    public void updateUser(UserUpdateDto dto) {
        // ...
    }
}
```

#### **3. `@PreAuthorize`: 동적인 보안 검증 (가장 강력함)**
Spring Security에서 URL 기반의 정적인 권한 설정을 넘어, 메서드의 파라미터나 현재 인증된 사용자의 정보를 기반으로 동적인 인가(Authorization)를 수행할 때 사용됩니다.

```java
@Service
public class PostService {

    // 1. 단순 역할(Role) 검사
    @PreAuthorize("hasRole('ADMIN')")
    public void deletePost(Long postId) {
        // ...
    }

    // 2. (핵심) 현재 인증된 사용자(principal)의 username과 
    //    메서드 파라미터(postAuthor)를 비교
    @PreAuthorize("authentication.principal.username == #postAuthor")
    public void editPost(Long postId, String content, String postAuthor) {
        // "게시글 작성자 본인만 수정 가능" 로직이
        // 서비스 코드에서 분리되어 AOP로 처리됨
    }
}
```

---

### 3. **SpEL의 유용한 문법들**

-   **Bean 참조**: `@beanName`
    -   `#{ @userRepository.count() }`
-   **Ternary Operator (삼항 연산자)**:
    -   `#{ #user.age > 19 ? 'Adult' : 'Minor' }`
-   **Safe Navigation**: (Null-safe)
    -   `#{ #user.team?.name }` (user.team이 null이면 NullPointerException 대신 null을 반환)
-   **컬렉션 프로젝션(Projection) / 셀렉션(Selection)**:
    -   `#{ users.![name] }` (프로젝션: users 리스트에서 name만 뽑아 새 리스트 생성)
    -   `#{ users.?[age > 20] }` (셀렉션: users 리스트에서 age > 20인 사용자만 필터링)

---

## 💡 배운 점

1.  **`${...}`와 `#{...}`는 완전히 다르다**: 3~4년차임에도 둘을 혼용하거나 막연하게 "설정값 가져오는 것" 정도로 생각했습니다. `${...}`는 '설정 주입(Static)'이고, `#{...}`는 '코드 실행(Dynamic)'이라는 근본적인 차이를 명확히 이해했습니다.
2.  **SpEL은 '작은 프로그래밍 언어'다**: SpEL은 단순한 변수 치환이 아니라, 빈 참조, 메서드 호출, 연산, 컬렉션 처리까지 가능한 강력한 런타임 언어였습니다.
3.  **AOP와의 시너지**: SpEL의 진정한 힘은 AOP(관점 지향 프로그래밍)와 결합될 때 나타납니다. `@PreAuthorize` 예시처럼, 복잡한 인가 로직을 비즈니스 코드(`editPost`)에서 분리하여 애노테이션의 표현식 하나로 선언할 수 있게 해줍니다. 이는 코드를 매우 깔끔하고 선언적으로 만듭니다.

---

## 🔗 참고 자료

-   [Spring Docs - Spring Expression Language (SpEL)](https://docs.spring.io/spring-framework/reference/core/expressions.html)
-   [Spring Docs - @Value](https://docs.spring.io/spring-framework/reference/core/beans/annotation-config.html#beans-value)
-   [SpEL - Accessing Beans (Baeldung)](https://www.baeldung.com/spring-expression-language-operators)