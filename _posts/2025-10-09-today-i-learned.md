---
title: "Spring Boot 비동기 처리와 CompletableFuture 활용법"
date: 2025-10-09
categories: [Java, Spring]
tags: [Async, CompletableFuture, Spring Boot, Performance, Concurrency, TIL]
excerpt: "Spring Boot 애플리케이션에서 I/O 바운드 작업의 성능을 극대화하기 위한 비동기 처리 방법을 학습합니다. @Async의 한계를 알아보고, Java 8의 CompletableFuture를 사용하여 여러 비동기 작업을 조합하고 제어하는 세련된 방법을 탐구합니다."
author_profile: true
---

# Today I Learned: Spring Boot 비동기 처리와 CompletableFuture 활용법

## 📚 오늘 학습한 내용

많은 백엔드 서비스는 사용자 요청을 처리하기 위해 데이터베이스 조회, 외부 API 호출 등 여러 I/O 바운드(I/O-bound) 작업을 수행합니다. 이러한 작업들을 동기적으로 순차 처리하면, I/O 대기 시간만큼 전체 응답 시간이 길어지는 병목 현상이 발생합니다. 오늘은 Spring Boot 환경에서 이러한 문제를 해결하고 시스템의 처리량을 극대화하기 위한 **`@Async`**와 **`CompletableFuture`**에 대해 학습했습니다.

---

### 1. **기본적인 비동기 처리: `@Async`의 한계**

Spring은 `@Async` 애노테이션을 통해 메서드를 별도의 스레드에서 비동기적으로 실행하는 간편한 방법을 제공합니다.

```java
@Service
public class EmailService {
    @Async
    public void sendWelcomeEmail(String email) {
        // 시간이 오래 걸리는 이메일 발송 작업...
        System.out.println("Sent welcome email to " + email);
    }
}
```
이 방식은 "실행하고 잊어버리는(fire-and-forget)" 스타일의 작업에는 유용합니다. 하지만 `@Async` 메서드가 반환하는 `Future<T>` 타입은 한계가 명확합니다.

-   **블로킹**: 결과를 얻기 위해 `future.get()`을 호출하면, 작업이 완료될 때까지 현재 스레드가 **블로킹**됩니다. 비동기 처리의 이점이 사라집니다.
-   **조합의 어려움**: 여러 비동기 작업들을 조합(Composition)하기가 매우 어렵습니다. 예를 들어, "A 작업이 끝나면 그 결과로 B와 C 작업을 동시에 실행하고, 두 작업이 모두 끝나면 그 결과를 합쳐서 D 작업을 실행하라"와 같은 복잡한 흐름을 구현하기 힘듭니다.

---

### 2. **세련된 비동기 파이프라인: `CompletableFuture`의 등장**

Java 8에서 등장한 **`CompletableFuture`**는 이러한 `Future`의 한계를 극복하고, 비동기 작업들을 조합하여 선언적으로 파이프라인을 구성할 수 있게 해주는 강력한 도구입니다.

-   **주요 특징**:
    -   **논블로킹**: `.get()`을 호출하지 않고도 작업이 완료되었을 때 실행될 콜백(Callback)을 등록할 수 있습니다.
    -   **조합 가능**: 여러 `CompletableFuture`를 연결하여 복잡한 비동기 워크플로우를 만들 수 있습니다.
    -   **예외 처리**: 비동기 작업 중 발생한 예외를 우아하게 처리하는 방법을 제공합니다.

#### **주요 API와 사용 예제**
`사용자 프로필 조회` 시나리오: 사용자 기본 정보, 최신 주문 목록, 팔로워 수를 각각 다른 API 서버에서 가져와야 한다고 가정해봅시다.

**❌ 동기 방식 (총 응답 시간: 1s + 1s + 1s = 3s)**
```java
@Service
public class SyncUserProfileService {
    public UserProfile getProfile(Long userId) {
        UserInfo info = fetchUserInfo(userId); // 1초 소요
        List<Order> orders = fetchLatestOrders(userId); // 1초 소요
        long followers = fetchFollowerCount(userId); // 1초 소요
        return new UserProfile(info, orders, followers);
    }
}
```

**✅ `CompletableFuture` 비동기 방식 (총 응답 시간: max(1s, 1s, 1s) ≈ 1s)**
```java
@Service
public class AsyncUserProfileService {
    // 별도의 스레드 풀을 정의하여 사용하는 것이 권장됨
    private final ExecutorService executor = Executors.newFixedThreadPool(10);

    public UserProfile getProfile(Long userId) throws ExecutionException, InterruptedException {
        CompletableFuture<UserInfo> infoFuture = CompletableFuture.supplyAsync(() ->
                fetchUserInfo(userId), executor);

        CompletableFuture<List<Order>> ordersFuture = CompletableFuture.supplyAsync(() ->
                fetchLatestOrders(userId), executor);
        
        CompletableFuture<Long> followersFuture = CompletableFuture.supplyAsync(() ->
                fetchFollowerCount(userId), executor);

        // thenCombine: 두 작업이 모두 완료되면 결과를 조합하여 새로운 작업을 수행
        CompletableFuture<UserProfile> combinedFuture = infoFuture.thenCombine(ordersFuture, (info, orders) ->
                new UserProfile(info, orders, 0L) // 임시 UserProfile 생성
        ).thenCombine(followersFuture, (profile, followers) ->
                profile.withFollowers(followers) // 최종 UserProfile 완성
        );

        return combinedFuture.get(); // 모든 비동기 작업이 완료될 때까지 기다린 후 최종 결과 반환
    }
}
```
> `supplyAsync`로 각 작업을 별도의 스레드에서 동시에 시작하고, `thenCombine`으로 모든 작업의 결과를 안전하게 조합하여 최종 결과를 만들어냅니다.

---

### 3. **주요 조합 API**

-   **`thenApply(Function)`**: `Future`가 완료되면, 그 결과를 입력으로 받아 새로운 값을 반환하는 함수를 실행합니다. (순차적 연결)
    ```java
    CompletableFuture<Integer> future = CompletableFuture.supplyAsync(() -> 10);
    future.thenApply(result -> result * 2); // 결과는 20
    ```
-   **`thenAccept(Consumer)`**: `Future`가 완료되면, 그 결과를 소비하는 함수를 실행합니다. (반환값 없음)
    ```java
    future.thenAccept(result -> System.out.println("Result: " + result));
    ```
-   **`thenCompose(Function)`**: `Future`가 완료되면, 그 결과를 입력으로 받아 **또 다른 `CompletableFuture`를 반환**하는 함수를 실행합니다. (비동기 작업의 중첩 연결)
-   **`allOf(futures...)`**: 여러 `CompletableFuture`를 입력으로 받아, **모든 작업이 완료될 때** 완료되는 새로운 `CompletableFuture<Void>`를 반환합니다.

---

## 💡 배운 점

1.  **I/O 바운드 작업은 비동기가 필수다**: 외부 API 호출이나 DB 쿼리처럼 대기 시간이 긴 작업들을 동기적으로 처리하는 것은 시스템 리소스를 심각하게 낭비하는 것임을 다시 한번 깨달았습니다. `CompletableFuture`는 이러한 낭비를 줄여 시스템의 전체 처리량을 높이는 강력한 도구입니다.
2.  **선언적 코드의 가독성**: 콜백 지옥(Callback Hell)을 유발할 수 있는 전통적인 비동기 코드와 달리, `CompletableFuture`의 체이닝(Chaining) 방식은 "A가 끝나면 B를 하고, C와 합쳐서 D를 만든다"와 같이 비즈니스 흐름을 선언적으로 명확하게 표현할 수 있어 코드의 가독성과 유지보수성을 높여줍니다.
3.  **적절한 스레드 풀 관리가 중요하다**: `CompletableFuture`를 사용할 때 별도의 `Executor`를 지정하지 않으면 공용 `ForkJoinPool`을 사용하게 됩니다. 특정 작업이 전체 애플리케이션에 영향을 주지 않도록, 용도에 맞는 스레드 풀을 생성하고 관리하는 것이 실제 운영 환경에서는 매우 중요하다는 점을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Java CompletableFuture (Baeldung)](https://www.baeldung.com/java-completablefuture)
-   [Guide to @Async in Spring (Baeldung)](https://www.baeldung.com/spring-async)
-   [Java 8: The Missing Tutorial – Asynchronous C… (YouTube - T.J.DEV)](https://www.youtube.com/watch?v=eQ44weK-DkM)