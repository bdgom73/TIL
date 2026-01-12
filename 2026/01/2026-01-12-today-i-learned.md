---
title: "Spring Boot @Async와 CompletableFuture: Default 스레드 풀의 함정과 커스텀 Executor 튜닝"
date: 2026-01-12
categories: [Java, Spring, Concurrency]
tags: [Spring Boot, Async, ThreadPool, CompletableFuture, Performance Tuning, ExecutorService, TIL]
excerpt: "편리하게 사용하는 @Async 애노테이션 뒤에 숨겨진 'SimpleAsyncTaskExecutor'의 위험성을 파악하고, 운영 환경에 맞는 ThreadPoolTaskExecutor를 설정하는 방법을 학습합니다. 또한 CompletableFuture를 활용해 여러 비동기 작업을 병렬로 처리하고 결과를 조합하는 패턴을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot @Async와 CompletableFuture: Default 스레드 풀의 함정과 커스텀 Executor 튜닝

## 📚 오늘 학습한 내용

외부 API 여러 개를 호출해서 데이터를 합쳐야 하는 요구사항이 생겼습니다. 순차적으로 호출하면 응답 시간이 너무 길어져서 `CompletableFuture`와 `@Async`를 이용해 병렬 처리를 도입했습니다.

하지만 Spring Boot에서 별도 설정 없이 `@Async`를 쓰면 **스레드 풀을 쓰지 않고 요청마다 스레드를 계속 생성**한다는 사실을 알게 되었습니다. 오늘은 비동기 처리의 핵심인 스레드 풀 설정 전략과 `CompletableFuture` 조합 패턴을 정리했습니다.

---

### 1. **Default 설정의 함정: `SimpleAsyncTaskExecutor` 💣**

Spring Boot에서 `@EnableAsync`만 붙이고 별도의 `Executor` 빈을 등록하지 않으면, 기본적으로 **`SimpleAsyncTaskExecutor`**가 사용됩니다.

-   **문제점**: 이름과 달리 스레드 풀(Thread Pool)이 아닙니다.
-   **동작**: 비동기 요청이 올 때마다 **새로운 스레드를 생성**(`new Thread()`)하고, 작업이 끝나면 버립니다.
-   **위험성**: 요청이 폭주하면 스레드 생성 비용으로 CPU가 치솟고, `OutOfMemoryError`로 서버가 다운될 수 있습니다.

---

### 2. **커스텀 `ThreadPoolTaskExecutor` 설정**

운영 환경에서는 반드시 커스텀 Executor를 정의해야 합니다. 이때 `CorePoolSize`, `QueueCapacity`, `MaxPoolSize`의 동작 순서를 정확히 아는 것이 중요합니다.

**AsyncConfig.java**
```java
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean(name = "apiExecutor")
    public Executor apiExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        
        // 1. 기본 스레드 수 (평상시 대기)
        executor.setCorePoolSize(10);
        
        // 2. 대기열 크기 (Core 스레드가 꽉 차면 여기 쌓임)
        executor.setQueueCapacity(50);
        
        // 3. 최대 스레드 수 (Queue까지 꽉 차야 비로소 Core 이상으로 스레드가 생성됨)
        executor.setMaxPoolSize(20);
        
        // 4. 스레드 이름 접두사 (디버깅 시 필수)
        executor.setThreadNamePrefix("ApiExecutor-");
        
        // 5. 거부 정책 (Max까지 꽉 찼을 때 어떻게 할 것인가?)
        // CallerRunsPolicy: 요청한 스레드(Main)에서 직접 실행 (유실 방지용)
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        
        executor.initialize();
        return executor;
    }
}
```

> **주의**: `QueueCapacity`가 디폴트(`Integer.MAX_VALUE`)면 `MaxPoolSize` 설정은 무시됩니다. (큐가 영원히 안 차니까)

---

### 3. **`CompletableFuture`로 결과 조합하기 🧩**

단순히 실행만 하는 것(`void`)이 아니라, 비동기 작업의 결과를 받아야 한다면 `Future` 대신 Java 8의 `CompletableFuture`를 사용해야 합니다.

**Service 로직**
```java
@Service
@RequiredArgsConstructor
public class DashboardService {

    private final ExternalApiClient apiClient;

    // 비동기 메서드 (반환 타입에 주의)
    @Async("apiExecutor")
    public CompletableFuture<UserInfo> getUserInfo(Long userId) {
        return CompletableFuture.completedFuture(apiClient.getUser(userId));
    }

    @Async("apiExecutor")
    public CompletableFuture<List<Order>> getOrders(Long userId) {
        return CompletableFuture.completedFuture(apiClient.getOrders(userId));
    }

    // 메인 로직: 병렬 실행 및 결과 조합
    public DashboardDto getDashboard(Long userId) {
        long start = System.currentTimeMillis();

        // 1. 비동기 호출 시작 (Non-blocking)
        CompletableFuture<UserInfo> userFuture = getUserInfo(userId);
        CompletableFuture<List<Order>> orderFuture = getOrders(userId);

        // 2. 두 작업이 모두 끝날 때까지 대기 (allOf)
        // join()은 예외 발생 시 Unchecked Exception을 던져서 코드가 깔끔함
        CompletableFuture.allOf(userFuture, orderFuture).join();

        // 3. 결과 꺼내기 (이미 완료된 상태임)
        UserInfo user = userFuture.join();
        List<Order> orders = orderFuture.join();

        log.info("Total Time: {}ms", System.currentTimeMillis() - start);
        return new DashboardDto(user, orders);
    }
}
```

---

### 4. **예외 처리 전략**

비동기 메서드 내부에서 예외가 발생하면, 메인 스레드에서는 이를 바로 알 수 없습니다. `CompletableFuture`의 `exceptionally`를 사용해 우아하게 처리해야 합니다.

```java
@Async("apiExecutor")
public CompletableFuture<UserInfo> getUserInfo(Long userId) {
    try {
        return CompletableFuture.completedFuture(apiClient.getUser(userId));
    } catch (Exception e) {
        // 방법 1: 바로 throw 하면 Future.join()에서 CompletionException으로 감싸져서 나옴
        throw e; 
    }
}

// 호출부에서 처리
public DashboardDto getDashboard(Long userId) {
    CompletableFuture<UserInfo> userFuture = getUserInfo(userId)
        .exceptionally(ex -> {
            log.error("유저 조회 실패", ex);
            return new UserInfo("Unknown", "Default"); // 실패 시 기본값 반환 (Fallback)
        });
    
    // ...
}
```

---

## 💡 배운 점

1.  **스레드 풀 동작 순서의 반전**: 일반적인 상식으로는 "Core가 차면 Max까지 늘리고, 그래도 안 되면 큐에 쌓겠지?"라고 생각하기 쉬운데, 실제로는 **Core -> Queue -> Max** 순서라는 점이 중요합니다. 즉, 큐 용량을 너무 크게 잡으면 Max Pool 설정이 무용지물이 될 수 있습니다.
2.  **`@Async`의 리턴 타입**: `void`가 아닌 값을 반환할 때 `Future`를 쓰면 `get()` 호출 시 블로킹이 발생하여 비동기의 이점이 반감됩니다. `CompletableFuture`를 써야 Non-blocking 스타일로 파이프라인 구성이 가능함을 알았습니다.
3.  **MDC 로그 추적**: 비동기 스레드로 넘어가면 `TraceId` 같은 MDC 컨텍스트가 끊깁니다. 이를 해결하기 위해 `TaskDecorator`를 구현하여 컨텍스트를 복사해주는 추가 작업이 필요하다는 것도 알게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Boot Async Execution Guide](https://spring.io/guides/gs/async-method/)
-   [Java CompletableFuture Guide (Baeldung)](https://www.baeldung.com/java-completableFuture)
-   [ThreadPoolTaskExecutor Configuration](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/concurrent/ThreadPoolTaskExecutor.html)