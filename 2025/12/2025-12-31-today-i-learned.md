---
title: "Java 21 Virtual Threads: WebFlux의 복잡성 없이 I/O Blocking 성능 극복하기"
date: 2025-12-31
categories: [Java, Spring, Performance]
tags: [Java 21, Virtual Threads, Project Loom, Concurrency, Spring Boot 3.2, Performance, TIL]
excerpt: "기존 Platform Thread(OS 스레드) 모델의 한계를 극복하기 위해 등장한 Java 21의 Virtual Threads를 Spring Boot에 적용하는 방법을 학습합니다. Reactive Programming(WebFlux)의 가독성 저하 없이 높은 처리량을 달성하는 원리와, 도입 시 주의해야 할 'Pinning' 이슈에 대해 알아봅니다."
author_profile: true
---

# Today I Learned: Java 21 Virtual Threads: WebFlux의 복잡성 없이 I/O Blocking 성능 극복하기

## 📚 오늘 학습한 내용

전통적인 Spring MVC(Thread-per-request) 모델에서는 요청 하나당 OS 스레드 하나를 점유합니다. DB 쿼리나 외부 API 호출 같은 I/O 작업으로 스레드가 대기(Blocking)하는 동안, 비싼 자원인 OS 스레드는 아무것도 안 하고 낭비됩니다. 이를 해결하기 위해 `WebFlux`를 도입하자니 코드가 너무 복잡해지고 디버깅이 어려웠습니다.

오늘은 **"동기 코드(Blocking) 스타일을 유지하면서도 비동기 논블로킹(Non-blocking) 급의 성능"**을 낼 수 있는 Java 21의 혁명, **Virtual Threads(Project Loom)**를 Spring Boot 환경에 적용하고 주의할 점을 정리했습니다.

---

### 1. **Platform Thread vs. Virtual Thread 🧵**

| 특징 | **Platform Thread (기존)** | **Virtual Thread (Java 21+)** |
| :--- | :--- | :--- |
| **매핑** | OS 스레드와 1:1 매핑 | OS 스레드(Carrier)와 **N:M 매핑** |
| **생성 비용** | 비쌈 (약 1MB 메모리, 커널 호출) | 매우 저렴 (수 KB 힙 메모리, JVM 내부 처리) |
| **컨텍스트 스위칭** | 느림 (OS 커널 레벨) | 빠름 (JVM 내부 포인터 이동 수준) |
| **개수 제한** | 수천 개 정도가 한계 | **수백만 개** 생성 가능 |
| **적합한 작업** | CPU 집약적 작업 | **I/O 집약적 작업** (DB, Network) |



-   **핵심 원리**: Virtual Thread가 I/O 작업(예: `Thread.sleep`이나 소켓 읽기)을 만나면, JVM이 자동으로 해당 Virtual Thread를 잠시 힙 메모리로 치워두고(Unmount), 실제 OS 스레드(Carrier Thread)는 다른 Virtual Thread를 실행하러 떠납니다. 즉, **OS 스레드가 멈추지 않고 계속 일합니다.**

---

### 2. **Spring Boot 3.2+ 적용 방법**

Java 21 이상과 Spring Boot 3.2 이상을 쓴다면 적용은 허무할 정도로 간단합니다.

**application.yml**
```yaml
spring:
  threads:
    virtual:
      enabled: true # 이 설정 하나면 톰캣과 TaskExecutor가 가상 스레드를 사용함
```

**동작 확인**
```java
@RestController
@Slf4j
public class TestController {

    @GetMapping("/thread")
    public String checkThread() {
        // 출력 예시: VirtualThread[#21]/runnable@ForkJoinPool-1-worker-1
        log.info("Current Thread: {}", Thread.currentThread());
        return Thread.currentThread().toString();
    }
}
```

이제 `RestTemplate`, `JdbcTemplate`, `FeignClient` 등 기존 Blocking I/O 라이브러리를 그대로 써도, 내부적으로는 Non-blocking 처럼 동작하여 처리량(Throughput)이 비약적으로 상승합니다.

---

### 3. **주의사항 1: Pinning 이슈 (가장 중요) 📌**

Virtual Thread가 OS 스레드에 "고정(Pinning)"되어 Unmount 되지 못하는 상황이 있습니다. 이렇게 되면 Virtual Thread의 이점이 사라지고 성능이 급격히 저하됩니다.

-   **발생 조건**:
    1.  `synchronized` 블록이나 메서드 내부에서 I/O 작업을 수행할 때.
    2.  JNI(Native Method)를 호출할 때.

**나쁜 예 (`synchronized`)**
```java
public synchronized void logic() { // Pinning 발생!
    Thread.sleep(1000); // OS 스레드도 같이 멈춰버림 (Block)
}
```

**좋은 예 (`ReentrantLock`)**
Java 라이브러리의 `Lock`은 Pinning을 유발하지 않도록 재작성되었습니다.
```java
private final ReentrantLock lock = new ReentrantLock();

public void logic() {
    lock.lock();
    try {
        Thread.sleep(1000); // Virtual Thread만 멈추고 OS 스레드는 다른 일 하러 감 (Good)
    } finally {
        lock.unlock();
    }
}
```

> **MySQL JDBC Driver**: 예전 버전의 JDBC 드라이버는 내부에 `synchronized`가 많아 Pinning 문제가 심했습니다. 반드시 최신 버전(Connector/J 8.0.32+ 등)을 사용해야 합니다.

---

### 4. **주의사항 2: ThreadLocal 오용 금지 🚫**

기존에는 스레드 풀(Thread Pool)을 사용했기 때문에 스레드 개수가 제한적이었고, `ThreadLocal`에 무거운 객체(SimpleDateFormat 등)를 캐싱해서 재사용하는 패턴이 흔했습니다.

하지만 Virtual Thread는 **생성되고 버려지는 일회용**이며, **수백만 개**가 생길 수 있습니다.
-   Virtual Thread마다 `ThreadLocal`에 데이터를 담으면 **메모리 폭발(OOM)**이 발생할 수 있습니다.
-   따라서 Virtual Thread 환경에서는 무거운 객체의 캐싱 용도로 `ThreadLocal`을 사용하면 안 됩니다. (트랜잭션 컨텍스트 전파 같은 가벼운 데이터는 괜찮음)

---

## 💡 배운 점

1.  **WebFlux의 대안**: "비동기 처리를 위해 리액티브를 배워야 하나"라는 고민을 완벽하게 날려버렸습니다. 코드는 동기식으로 직관적으로 짜고, 성능은 비동기로 뽑아내는 **"Write Sync, Run Async"**가 실현되었습니다.
2.  **스레드 풀은 이제 안녕**: Virtual Thread는 필요할 때마다 `new Thread()`로 만들어 쓰는 것이 권장됩니다. 스레드 풀을 관리하고 튜닝하는 복잡한 작업(Core size, Max size 계산 등)에서 해방될 수 있습니다.
3.  **라이브러리 호환성 체크**: 아직 모든 라이브러리가 Virtual Thread 친화적이지 않습니다(특히 `synchronized` 사용). 도입 전 사용 중인 라이브러리의 호환성을 검토하고, `jfr` (Java Flight Recorder)로 Pinning 이벤트를 모니터링해야 함을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Boot Virtual Threads Documentation](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.spring-application.virtual-threads)
-   [JEP 444: Virtual Threads](https://openjdk.org/jeps/444)
-   [Oracle: Embracing Virtual Threads](https://inside.java/2023/11/28/gen-z-virtual-threads/)