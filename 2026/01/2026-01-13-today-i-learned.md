---
title: "로그 추적의 필수품 MDC(Mapped Diagnostic Context)와 비동기 스레드 컨텍스트 전파"
date: 2026-01-13
categories: [Spring, Logging, DevOps]
tags: [MDC, Logging, Spring Boot, ThreadLocal, TaskDecorator, Async, TraceId, TIL]
excerpt: "멀티 스레드 환경에서 뒤섞인 로그들을 요청별로 구분하기 위해 SLF4J의 MDC를 도입합니다. 기본적인 필터 설정부터, @Async와 같은 별도 스레드 실행 시 끊기는 MDC 컨텍스트를 TaskDecorator를 통해 우아하게 전파하는 방법까지 학습합니다."
author_profile: true
---

# Today I Learned: 로그 추적의 필수품 MDC(Mapped Diagnostic Context)와 비동기 스레드 컨텍스트 전파

## 📚 오늘 학습한 내용

운영 로그를 모니터링하다 보면, 동시 접속자가 많을 때 수십 개의 요청 로그가 뒤섞여서 특정 사용자의 에러 원인을 찾기가 불가능에 가까웠습니다. "주문 실패 에러" 로그는 찾았지만, 그 앞 단계에서 어떤 파라미터가 들어왔는지 추적할 수가 없었습니다.

오늘은 각 HTTP 요청마다 고유한 ID(TraceId)를 부여하고, 이를 로그의 모든 줄에 자동으로 남겨주는 **MDC(Mapped Diagnostic Context)**와, 스레드가 바뀔 때 이 컨텍스트를 유지하는 방법을 학습했습니다.

---

### 1. **MDC란? 🕵️**

MDC는 SLF4J(Logback)가 제공하는 기능으로, **ThreadLocal**을 활용하여 현재 스레드의 컨텍스트에 메타 데이터(Key-Value)를 저장하는 맵입니다.

-   **장점**: `log.info("메시지", traceId)` 처럼 매번 ID를 파라미터로 넘길 필요 없이, 로그 설정(`logback.xml`)에서 `%X{traceId}`만 추가하면 알아서 모든 로그에 찍힙니다.

**logback-spring.xml 설정**
```xml
<pattern>[%d{yyyy-MM-dd HH:mm:ss}] [%thread] [%X{request_id:-NO_ID}] %-5level %logger{36} - %msg%n</pattern>
```

---

### 2. **Filter에서 MDC 설정하기**

모든 요청의 진입점인 Filter(또는 Interceptor)에서 UUID를 생성하여 MDC에 넣고, 요청이 끝날 때 반드시 지워야 합니다. (ThreadLocal은 스레드 풀에서 재사용되므로 **초기화가 필수**입니다.)

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@Slf4j
public class MdcLoggingFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) 
            throws IOException, ServletException {
        
        // 1. 요청 ID 생성 (이미 헤더에 있으면 그거 쓰고, 없으면 새로 생성)
        String requestId = UUID.randomUUID().toString().substring(0, 8);
        
        // 2. MDC에 저장
        MDC.put("request_id", requestId);
        
        try {
            chain.doFilter(request, response);
        } finally {
            // 3. 사용 후 반드시 삭제 (메모리 누수 및 데이터 오염 방지)
            MDC.clear();
        }
    }
}
```

---

### 3. **문제 상황: `@Async`에서 MDC가 사라진다?**

MDC는 `ThreadLocal` 기반이므로, 비동기 처리를 위해 `@Async`를 사용하여 **다른 스레드**로 작업이 넘어가는 순간 `request_id` 정보가 증발합니다.

```java
@Async
public void sendEmail() {
    // 여기서 로그를 찍으면 [NO_ID]로 나옴 (새로운 스레드라서 MDC가 비어있음)
    log.info("이메일 전송 시작"); 
}
```

---

### 4. **해결책: `TaskDecorator`로 컨텍스트 전파 📡**

Spring의 `ThreadPoolTaskExecutor`는 스레드를 생성하거나 실행하기 직전에 작업을 가로채는 **`TaskDecorator`** 인터페이스를 제공합니다. 이를 이용해 부모 스레드의 MDC 맵을 자식 스레드로 복사해줄 수 있습니다.

#### **Step 1: Decorator 구현**

```java
public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        // 1. 현재(부모) 스레드의 MDC 컨텍스트를 꺼냄
        Map<String, String> contextMap = MDC.getCopyOfContextMap();
        
        return () -> {
            try {
                // 2. 자식 스레드에 컨텍스트 복사
                if (contextMap != null) {
                    MDC.setContextMap(contextMap);
                }
                // 3. 원래 작업 수행
                runnable.run();
            } finally {
                // 4. 자식 스레드 작업 후 정리 (스레드 풀 오염 방지)
                MDC.clear();
            }
        };
    }
}
```

#### **Step 2: Executor에 등록**

```java
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        // ... 기타 설정 ...
        
        // 커스텀 데코레이터 등록
        executor.setTaskDecorator(new MdcTaskDecorator());
        
        executor.initialize();
        return executor;
    }
}
```

이제 `@Async` 메서드 내부에서도 Controller와 동일한 `request_id`가 로그에 찍히게 되어, 전체 트랜잭션의 흐름을 완벽하게 추적할 수 있습니다.

---

## 💡 배운 점

1.  **로그는 데이터다**: 로그 파일은 단순히 텍스트 덩어리가 아니라, 장애 상황을 복기할 수 있는 가장 중요한 데이터입니다. MDC를 통해 구조화된 로깅(Structured Logging)의 기초를 다질 수 있었습니다.
2.  **ThreadLocal의 생명주기**: 톰캣의 스레드 풀이나 커스텀 스레드 풀이나, 스레드는 재사용된다는 점을 항상 명심해야 합니다. `MDC.clear()`를 `finally` 블록에서 호출하지 않으면, 다음 요청자가 이전 사람의 `request_id`를 달고 로직을 수행하는 끔찍한 혼종 로그가 발생할 수 있음을 주의해야 합니다.
3.  **횡단 관심사의 처리**: 비즈니스 로직마다 로그 코드를 넣는 것이 아니라, Filter와 Decorator라는 AOP스런 장치를 통해 인프라 레벨에서 추적성을 확보하는 패턴이 유지보수성에 큰 도움이 됨을 느꼈습니다.

---

## 🔗 참고 자료

-   [Logback MDC Manual](https://logback.qos.ch/manual/mdc.html)
-   [Spring Boot TaskDecorator](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/core/task/TaskDecorator.html)
-   [Distributed Tracing with Spring Boot and MDC](https://www.baeldung.com/spring-boot-logging-mdc-tracing)