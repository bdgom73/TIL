---
title: "Spring Cache Abstraction: `@Cacheable`로 선언적 캐시 적용하기"
date: 2025-11-06
categories: [Spring, Performance]
tags: [Spring Cache, @Cacheable, @CacheEvict, AOP, Caffeine, Performance, TIL]
excerpt: "반복적인 DB 조회로 인한 성능 저하를 해결하기 위해 Spring의 '캐시 추상화(@Cacheable)'가 어떻게 동작하는지 학습합니다. AOP 기반의 프록시 동작 원리와 캐시 무효화를 위한 @CacheEvict, 그리고 AOP의 공통 함정인 '자기 호출' 문제를 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Cache Abstraction: `@Cacheable`로 선언적 캐시 적용하기

## 📚 오늘 학습한 내용

저는 3~4년차 개발자로서, 서비스의 성능 병목 지점이 대부분 **반복적인 DB 조회**에서 발생한다는 것을 자주 경험했습니다. 예를 들어, 거의 변경되지 않는 '카테고리 목록 조회'나 '사용자 프로필 조회' API가 매번 DB를 호출하는 것은 명백한 자원 낭비입니다.

오늘은 이러한 문제를 해결하기 위해, 애플리케이션의 비즈니스 코드 수정 없이 **애노테이션 하나로 캐시를 적용**할 수 있게 해주는 **Spring Cache Abstraction**의 핵심, **`@Cacheable`**에 대해 학습했습니다.

---

### 1. **Spring Cache Abstraction: '추상화'의 의미**

Spring Cache의 핵심은 개발자가 캐시 기술에 종속되지 않도록 하는 **'추상화'**에 있습니다.

-   **역할**: Spring은 캐시 적용을 위한 **표준 인터페이스(API)만 제공**합니다.
-   **구현체**: 실제 캐시 저장소(e.g., `Caffeine`, `EhCache`, `Redis`)는 개발자가 선택하여 의존성으로 추가하면, Spring Boot가 이를 자동으로 감지하여 `CacheManager` 빈으로 등록해줍니다.

개발자는 `Redis`용 코드나 `Caffeine`용 코드를 작성하는 것이 아니라, Spring이 제공하는 `@Cacheable`이라는 표준 애노테이션만 사용하면 됩니다.

---

### 2. **`@Cacheable`의 마법: AOP 프록시의 동작 원리**

`@Cacheable`은 `@Transactional`과 마찬가지로 **AOP(관점 지향 프로그래밍)**를 기반으로 **프록시(Proxy)**를 통해 동작합니다.

1.  `@EnableCaching`이 활성화되면, Spring은 `@Cacheable`이 붙은 빈(Bean)을 **프록시 객체**로 감쌉니다.
2.  외부에서 이 메서드를 호출하면, 프록시가 먼저 호출을 가로챕니다.
3.  프록시는 메서드의 인자(Argument)를 기반으로 **캐시 키(Key)**를 생성합니다.
4.  **[Cache Hit]**: 해당 키로 `CacheManager`를 조회하여 캐시된 데이터가 있으면, **실제 메서드를 호출하지 않고** 캐시된 값을 즉시 반환합니다.
5.  **[Cache Miss]**: 캐시된 데이터가 없으면, 프록시는 **실제 메서드를 호출**하여 DB 등에서 데이터를 가져옵니다.
6.  프록시는 이 반환값을 캐시에 저장한 후, 클라이언트에게 반환합니다.



---

### 3. **Spring Boot에 Caffeine 캐시 적용하기**

가장 간단한 로컬 인메모리 캐시인 Caffeine을 적용하는 방법입니다.

**1. `build.gradle` 의존성 추가**
```groovy
// 1. Spring Cache 추상화 API
implementation 'org.springframework.boot:spring-boot-starter-cache'
// 2. 실제 캐시 구현체 (Caffeine)
implementation 'com.github.ben-manes.caffeine:caffeine'
```

**2. `@EnableCaching` 활성화**
```java
@EnableCaching // 캐시 기능을 활성화
@SpringBootApplication
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}
```
> (참고) `application.yml`에 `spring.cache.caffeine.spec=...`을 추가하여 캐시의 만료 시간(TTL), 최대 크기(Size) 등을 상세히 설정할 수 있습니다.

**3. `@Cacheable` 적용**
```java
@Service
@Slf4j
public class UserService {

    @Cacheable(cacheNames = "userProfile", key = "#userId")
    public UserProfileDto getUserProfile(Long userId) {
        log.info("### [Cache Miss] DB에서 사용자 프로필 조회: {}", userId);
        // 이 부분은 DB에서 조회하는 비싼 작업이라고 가정
        return new UserProfileDto(userId, "User " + userId, "user@email.com");
    }
}
```
-   `cacheNames = "userProfile"`: 사용할 캐시 저장소의 이름을 지정합니다.
-   `key = "#userId"`: **SpEL(Spring Expression Language)**을 사용한 키 생성 방식입니다. 매개변수 `userId`의 값을 캐시 키로 사용합니다. (e.g., `userProfile::1`, `userProfile::2`)
-   이렇게 설정하고 API를 두 번 호출하면, 로그는 **오직 한 번만** 찍히는 것을 볼 수 있습니다.

---

### 4. **캐시 무효화: `@CacheEvict`**

사용자 프로필이 변경되면 기존 캐시를 삭제(무효화)하여 데이터 정합성을 맞춰야 합니다. 이때 **`@CacheEvict`**를 사용합니다.

```java
@Service
@Slf4j
public class UserService {
    
    // ... getUserProfile 메서드 ...

    @CacheEvict(cacheNames = "userProfile", key = "#updateRequest.userId")
    public void updateUserProfile(Long userId, UserUpdateRequest updateRequest) {
        log.info("### [Cache Evict] DB 업데이트 및 캐시 삭제: {}", userId);
        // 1. DB 업데이트 로직 수행
        // ...
        // 2. 메서드가 성공적으로 종료되면, 프록시가 userProfile 캐시에서 
        //    key="#updateRequest.userId"에 해당하는 항목을 삭제합니다.
    }
}
```

---

### 5. **3~4년차의 함정: AOP 프록시와 '자기 호출(Self-invocation)'**

오늘 배운 가장 중요한 내용입니다. `@Cacheable`도 `@Transactional`과 동일한 **프록시 기반 AOP의 함정**을 가지고 있습니다.

**❌ 잘못된 예시**
```java
@Service
public class UserService {

    @Cacheable(cacheNames = "userProfile", key = "#userId")
    public UserProfileDto getUserProfile(Long userId) {
        log.info("### DB 조회...: {}", userId);
        return new UserProfileDto(userId, "User " + userId, "user@email.com");
    }
    
    /**
     * 같은 클래스 내부의 public 메서드 호출 (자기 호출)
     */
    public UserProfileDto getProfileAndDoSomething(Long userId) {
        // ...
        
        // (주의!) 이 호출은 프록시를 타지 않는다!
        UserProfileDto profile = this.getUserProfile(userId); 
        
        // ...
        return profile;
    }
}
```
-   **문제**: 외부에서 `getProfileAndDoSomething(1L)`을 호출하면, 이 메서드는 프록시를 통해 정상적으로 실행됩니다.
-   **함정**: 하지만 이 메서드 내부에서 `this.getUserProfile(1L)`을 호출하는 것은, 프록시 객체가 아닌 **실제 `this` 객체**의 메서드를 직접 호출하는 것입니다.
-   **결과**: 프록시를 거치지 않았으므로 캐시 기능이 전혀 동작하지 않고, `getProfileAndDoSomething`을 호출할 때마다 `getUserProfile`은 매번 DB를 조회(로그가 매번 찍힘)하게 됩니다.

---

## 💡 배운 점

1.  **`@Cacheable`은 AOP다**: 캐시 기능이 `@Transactional`과 100% 동일한 AOP 프록시 원리로 동작한다는 것을 명확히 이해했습니다. 이는 '자기 호출'이라는 동일한 함정을 공유한다는 의미이기도 합니다.
2.  **캐시는 '추상화'다**: Spring이 왜 `starter-cache`만 제공하고 구현체를 강제하지 않았는지 이해했습니다. 개발자는 비즈니스 로직에만 집중하고, 실제 캐시 구현체(Caffeine/Redis)는 운영 환경이나 요구사항에 맞게 언제든 교체(Plug-in)할 수 있습니다.
3.  **성능과 정합성의 트레이드오프**: 캐시를 적용하는 순간, 성능은 올라가지만 '데이터 정합성'이라는 새로운 숙제가 생깁니다. `@CacheEvict`를 사용해 "언제 이 캐시를 무효화할 것인가"를 설계하는 것이 캐시를 '잘' 사용하는 핵심임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Framework Docs - Cache Abstraction](https://docs.spring.io/spring-framework/reference/integration/cache.html)
-   [Spring Boot Caching (Baeldung)](https://www.baeldung.com/spring-boot-caching)
-   [Caffeine Cache (GitHub)](https://github.com/ben-manes/caffeine)