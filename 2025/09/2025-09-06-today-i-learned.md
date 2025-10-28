---
title: "Spring Boot와 Redis를 활용한 분산 캐싱 적용기"
date: 2025-09-06
categories: [Spring, Redis]
tags: [SpringBoot, Redis, Cache, Caching, TIL]
excerpt: "Spring Boot 애플리케이션에 Redis를 연동하여 간단한 분산 캐싱을 적용하고, @Cacheable, @CachePut, @CacheEvict 어노테이션을 활용하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot와 Redis를 활용한 캐싱 적용 🚀

오늘은 Spring Boot 애플리케이션의 성능을 향상시키기 위해 **Redis를 활용한 캐싱**을 적용하는 방법에 대해 학습했습니다. 반복적으로 조회되는 데이터를 매번 데이터베이스에서 가져오는 대신, 메모리 기반의 Redis 캐시에 저장해두고 빠르게 응답하도록 만들어보겠습니다.

---

## 🤔 캐싱(Caching)이란 무엇이고 왜 필요할까?

캐싱은 자주 사용되거나 계산 비용이 비싼 데이터의 복사본을 일시적으로 저장해두는 기술입니다. 이를 통해 향후 동일한 데이터 요청이 발생했을 때, 원본 데이터 소스(예: 데이터베이스)에 접근하지 않고 캐시에서 직접 데이터를 가져와 **애플리케이션의 응답 속도를 크게 향상**시킬 수 있습니다. 또한, 데이터베이스의 부하를 줄여 시스템 전체의 안정성과 확장성을 높이는 데 도움이 됩니다.

Redis는 In-Memory 데이터 구조 저장소로서, 빠른 속도와 다양한 데이터 타입을 지원하여 분산 캐시 서버로 널리 사용됩니다.

---

## 🛠️ 개발 환경 및 의존성 설정

먼저, Spring Boot 프로젝트에 Redis 캐싱을 적용하기 위해 필요한 의존성을 `build.gradle` 파일에 추가합니다.

-   **Spring Boot Version**: 3.x.x
-   **Java Version**: 17

```groovy
dependencies {
    // Spring Web Starter
    implementation 'org.springframework.boot:spring-boot-starter-web'

    // Spring Data Redis (Lettuce)
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'

    // Spring Cache Abstraction
    implementation 'org.springframework.boot:spring-boot-starter-cache'

    // Lombok (Optional)
    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'
}
```

-   `spring-boot-starter-data-redis`: Spring에서 Redis를 손쉽게 사용하기 위한 라이브러리입니다. (내부적으로 Lettuce 클라이언트를 사용합니다.)
-   `spring-boot-starter-cache`: Spring의 캐시 추상화를 사용하기 위한 라이브러리로, `@EnableCaching` 어노테이션을 제공합니다.

---

## ⚙️ Redis 연동 및 캐시 설정

의존성 추가 후, `application.yml` 파일에 Redis 접속 정보를 설정하고 캐시 관련 설정을 추가합니다.

```yaml
spring:
  data:
    redis:
      host: localhost # Redis 서버 호스트
      port: 6379      # Redis 서버 포트

  cache:
    type: redis # 사용할 캐시 타입으로 redis를 명시
    redis:
      time-to-live: 60000 # 캐시 만료 시간 (60초, millisecond 단위)
      cache-null-values: false # null 값은 캐싱하지 않도록 설정
```

그 다음, 메인 애플리케이션 클래스에 `@EnableCaching` 어노테이션을 추가하여 Spring Boot의 캐싱 기능을 활성화합니다.

```java
package com.example.rediscache;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cache.annotation.EnableCaching;

@EnableCaching // 캐싱 기능 활성화
@SpringBootApplication
public class RedisCacheApplication {

    public static void main(String[] args) {
        SpringApplication.run(RedisCacheApplication.class, args);
    }

}
```

---

## 💻 캐싱 어노테이션 활용 예제

이제 실제로 캐싱을 적용할 코드를 작성해 보겠습니다. 간단한 사용자 정보를 조회, 수정, 삭제하는 예제입니다.

### 1. DTO (Data Transfer Object) 생성

캐싱할 데이터 객체인 `UserProfile` DTO를 생성합니다. Redis에 저장되기 위해서는 `Serializable` 인터페이스를 구현해야 합니다.

```java
package com.example.rediscache.dto;

import java.io.Serializable;

public record UserProfile(String id, String name, int age) implements Serializable {
}
```
> **💡 Record 와 Serializable**
> Java 14부터 도입된 `record`는 자동으로 `toString()`, `hashCode()`, `equals()` 메서드를 생성해 줍니다. `Serializable` 인터페이스를 구현하면 이 객체가 직렬화되어 Redis에 저장될 수 있음을 명시합니다.

### 2. Service 클래스에 캐싱 적용

`UserProfileService` 클래스에서 각 메서드에 캐싱 관련 어노테이션을 추가합니다.

-   `@Cacheable`: 데이터를 조회할 때 사용합니다. 캐시에 데이터가 있으면 DB를 거치지 않고 캐시에서 바로 반환합니다. 없으면 메서드를 실행하고 결과를 캐시에 저장합니다.
-   `@CachePut`: 데이터를 생성하거나 수정할 때 사용합니다. 메서드를 **항상 실행**하고, 그 결과를 캐시에 갱신합니다.
-   `@CacheEvict`: 데이터를 삭제할 때 사용합니다. 메서드 실행 후 캐시에서 해당 데이터를 제거합니다.

```java
package com.example.rediscache.service;

import com.example.rediscache.dto.UserProfile;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.CachePut;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import java.util.HashMap;
import java.util.Map;

@Service
public class UserProfileService {

    // 간단한 예제를 위해 DB 대신 Map을 사용합니다.
    private static final Map<String, UserProfile> userDatabase = new HashMap<>();

    static {
        userDatabase.put("user1", new UserProfile("user1", "Alice", 30));
        userDatabase.put("user2", new UserProfile("user2", "Bob", 25));
    }

    // `userprofiles` 캐시 그룹에 `id`를 키로 사용하여 데이터를 캐싱합니다.
    @Cacheable(value = "userprofiles", key = "#id")
    public UserProfile getUserProfile(String id) {
        System.out.println("Fetching from DB for user: " + id);
        // DB 조회 로직 (시뮬레이션)
        try {
            Thread.sleep(1000); // DB 조회에 시간이 걸리는 것을 시뮬레이션
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return userDatabase.get(id);
    }

    // `userprofiles` 캐시 그룹의 데이터를 `id` 키 값으로 갱신합니다.
    @CachePut(value = "userprofiles", key = "#id")
    public UserProfile updateUserProfile(String id, String name, int age) {
        System.out.println("Updating DB for user: " + id);
        UserProfile updatedProfile = new UserProfile(id, name, age);
        userDatabase.put(id, updatedProfile);
        return updatedProfile;
    }

    // `userprofiles` 캐시 그룹에서 `id` 키에 해당하는 데이터를 삭제합니다.
    @CacheEvict(value = "userprofiles", key = "#id")
    public void deleteUserProfile(String id) {
        System.out.println("Deleting from DB for user: " + id);
        userDatabase.remove(id);
    }
}
```

> **key = "#id"**
> SpEL (Spring Expression Language)을 사용하여 메서드의 파라미터 `id`를 캐시 키로 동적으로 지정하는 부분입니다.

### 3. Controller 클래스 작성

서비스를 호출하는 간단한 REST 컨트롤러를 작성합니다.

```java
package com.example.rediscache.controller;

import com.example.rediscache.dto.UserProfile;
import com.example.rediscache.service.UserProfileService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/users")
public class UserProfileController {

    private final UserProfileService userProfileService;

    @GetMapping("/{id}")
    public UserProfile getUserProfile(@PathVariable String id) {
        return userProfileService.getUserProfile(id);
    }

    @PutMapping("/{id}")
    public UserProfile updateUserProfile(@PathVariable String id, @RequestParam String name, @RequestParam int age) {
        return userProfileService.updateUserProfile(id, name, age);
    }

    @DeleteMapping("/{id}")
    public String deleteUserProfile(@PathVariable String id) {
        userProfileService.deleteUserProfile(id);
        return "User " + id + " deleted.";
    }
}
```

---

## ✅ 동작 확인

1.  **최초 조회**: `GET /users/user1` 요청 시, 서비스의 `getUserProfile` 메서드가 실행되고 "Fetching from DB..." 로그가 출력됩니다. 결과는 Redis 캐시에 저장됩니다.
2.  **캐시된 데이터 조회**: 다시 `GET /users/user1` 요청 시, "Fetching from DB..." 로그 없이 바로 결과가 반환됩니다. 이는 Redis 캐시에서 데이터를 직접 가져왔기 때문입니다.
3.  **데이터 수정**: `PUT /users/user1?name=AliceNew&age=31` 요청 시, `updateUserProfile` 메서드가 실행되고 "Updating DB..." 로그가 출력됩니다. 동시에 Redis 캐시의 `user1` 데이터도 새로운 정보로 갱신됩니다.
4.  **데이터 삭제**: `DELETE /users/user1` 요청 시, `deleteUserProfile` 메서드가 실행되고 "Deleting from DB..." 로그가 출력되며, Redis 캐시에서도 해당 데이터가 삭제됩니다.

## ✨ 정리

-   **@EnableCaching**: Spring Boot에 캐싱 기능을 활성화합니다.
-   **@Cacheable**: 데이터 조회 시 캐시를 먼저 확인하고, 없으면 DB 조회 후 캐시에 저장합니다.
-   **@CachePut**: DB 데이터를 업데이트하고, 캐시도 항상 갱신합니다.
-   **@CacheEvict**: DB 데이터를 삭제하고, 캐시에서도 함께 제거합니다.

Spring Boot의 캐시 추상화 덕분에 어노테이션 몇 개만으로 간단하게 Redis 캐싱을 적용할 수 있었습니다. 이를 통해 데이터베이스의 부하를 줄이고 애플리케이션의 성능을 효과적으로 개선할 수 있습니다.