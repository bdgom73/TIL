---
title: "Java 21 Virtual Threads: 리액티브의 복잡성 없이 고성능 동시성 처리하기"
date: 2025-12-09
categories: [Java, Spring, Performance]
tags: [Java 21, Virtual Threads, Project Loom, Spring Boot 3.2, Concurrency, Performance, TIL]
excerpt: "Java 21의 핵심 기능인 가상 스레드(Virtual Threads)의 개념과 도입 배경을 학습합니다. 기존 플랫폼 스레드(Platform Thread)와의 차이점을 이해하고, Spring Boot 3.2 이상에서 단 한 줄의 설정으로 톰캣의 처리량을 비약적으로 높이는 방법과 주의할 점(Pinning)을 알아봅니다."
author_profile: true
---

# Today I Learned: Java 21 Virtual Threads: 리액티브의 복잡성 없이 고성능 동시성 처리하기

## 📚 오늘 학습한 내용

고트래픽 처리를 위해 Spring WebFlux(비동기 논블로킹)를 도입하려다 보면, 러닝 커브와 디버깅의 어려움, 그리고 JDBC/JPA와의 부조화 때문에 주저하게 되는 경우가 많습니다. "기존의 블로킹(Blocking) 방식 코드를 그대로 짜면서, 성능만 WebFlux처럼 낼 수는 없을까?"

이 오랜 난제를 해결하기 위해 JDK 21에서 정식 도입된 **가상 스레드(Virtual Threads, Project Loom)**의 원리와 Spring Boot 적용 방법을 학습했습니다.

---

### 1. **플랫폼 스레드 vs. 가상 스레드 🧵**

기존 Java의 스레드는 **플랫폼 스레드(Platform Thread)**로, OS(운영체제)의 커널 스레드와 **1:1로 매핑**되었습니다.

-   **플랫폼 스레드의 한계**:
    -   생성 비용이 비쌉니다 (메모리 약 2MB 점유).
    -   Context Switching 비용이 큽니다.
    -   I/O 작업(DB 조회, API 호출)으로 블로킹되면, 해당 OS 스레드도 함께 멈춰버려 자원이 낭비됩니다.
    -   따라서 스레드 풀(Thread Pool) 사이즈를 무작정 늘릴 수 없습니다 (보통 200개 제한).

반면, **가상 스레드(Virtual Thread)**는 **JVM이 관리하는 경량 스레드**입니다.

-   **가상 스레드의 혁신**:
    -   OS 스레드 하나 위에서 여러 가상 스레드가 번갈아 실행됩니다 (M:N 매핑).
    -   생성 비용이 극도로 저렴합니다 (수천, 수만 개 생성 가능).
    -   **I/O 블로킹 시**: 가상 스레드가 멈추더라도, 밑받침하는 OS 스레드(Carrier Thread)는 멈추지 않고 다른 가상 스레드를 실행합니다. (**Non-blocking I/O 효과**)



---

### 2. **Spring Boot 3.2+에서 적용하기**

Java 21 이상을 사용하고 Spring Boot 3.2 버전을 넘겼다면, 가상 스레드 적용은 믿을 수 없을 만큼 간단합니다.

**`application.yml` 설정**
```yaml
spring:
  threads:
    virtual:
      enabled: true # 이 설정 하나로 끝!
```

이 설정을 켜면 일어나는 일:
1.  **Tomcat**: 요청을 처리하는 스레드 풀이 기존의 제한된 플랫폼 스레드 풀 대신, **가상 스레드 생성기(Executor)**로 교체됩니다. 요청이 들어올 때마다 새로운 가상 스레드를 무제한에 가깝게 생성해서 처리합니다.
2.  **AsyncTask**: `@Async` 등을 처리하는 `TaskExecutor`도 가상 스레드 기반으로 변경됩니다.

**코드 비교 (변화 없음)**
```java
@RestController
@RequiredArgsConstructor
public class MyController {
    
    private final RestClient restClient; // or RestTemplate

    // 기존의 블로킹 방식 코드 그대로 작성!
    @GetMapping("/heavy-io")
    public String heavyIo() {
        // 1. 외부 API 호출 (여기서 블로킹 발생)
        // 가상 스레드 환경에서는 실제 OS 스레드가 블로킹되지 않고 다른 요청을 처리하러 감
        String result = restClient.get().uri("https://slow-api.com").retrieve().body(String.class);
        
        // 2. 결과 반환
        return process(result);
    }
}
```
> WebFlux처럼 `Mono`, `Flux`를 쓰지 않고, 기존의 `imperative` 스타일 코드를 그대로 유지하면서도 I/O 효율은 WebFlux에 근접하게 낼 수 있습니다.

---

### 3. **주의사항: 스레드 피닝(Thread Pinning) 📌**

가상 스레드는 완벽해 보이지만, **Synchronized** 키워드를 만났을 때 치명적인 약점이 있습니다.

-   **Pinning 현상**: 가상 스레드가 `synchronized` 블록이나 메서드 내부에서 I/O 작업을 수행하면, 해당 가상 스레드가 OS 스레드에 **고정(Pinned)**되어 버립니다.
-   **결과**: OS 스레드가 블로킹되므로, 가상 스레드의 이점이 사라지고 기존 플랫폼 스레드처럼 동작하여 성능 저하가 발생할 수 있습니다.

**해결책**:
-   `synchronized` 대신 **`ReentrantLock`**을 사용해야 합니다. (Java 라이브러리들은 이미 대부분 교체되었습니다.)
-   MySQL Driver 등 오래된 라이브러리나 레거시 코드에서 `synchronized` 구간 내에 I/O가 있는지 확인해야 합니다.

**피닝 감지 옵션**:
JVM 옵션으로 피닝 발생 시 로그를 남길 수 있습니다.
```bash
-Djdk.tracePinnedThreads=full
```

---

### 4. **ThreadLocal의 오용 금지**

가상 스레드는 수십만 개가 생성될 수 있습니다. 만약 무거운 객체(e.g., SimpleDateFormat, DB Connection)를 `ThreadLocal`에 저장해서 재사용하는 관습이 있다면, **메모리 폭발(OOM)**로 이어질 수 있습니다.

-   가상 스레드는 "생성하고 버리는" 일회용 리소스로 취급해야 합니다.
-   값비싼 리소스는 `ThreadLocal` 대신 풀링(Pooling)을 하거나 빈(Bean)으로 관리해야 합니다.

---

## 💡 배운 점

1.  **패러다임의 회귀와 진화**: "동기 블로킹 코드는 나쁘다"는 인식을 깨고, 언어 레벨(JVM)의 지원을 통해 **"읽기 쉬운 동기 코드로 비동기의 성능을 내는"** 시대로 진입했음을 느꼈습니다.
2.  **WebFlux의 대안**: CPU 연산이 많은 작업이 아니라, 대부분의 백엔드 워크로드인 **I/O Bound(DB, Network)** 작업에서는 가상 스레드가 WebFlux의 강력한, 그리고 훨씬 쉬운 대안이 될 수 있음을 확인했습니다.
3.  **라이브러리 호환성 체크**: 아직 모든 자바 라이브러리가 가상 스레드 친화적(synchronized 제거 등)이지는 않습니다. 도입 전 사용하는 라이브러리들의 Java 21 지원 여부와 Pinning 이슈를 점검하는 것이 필수적입니다.

---

## 🔗 참고 자료

-   [JEP 444: Virtual Threads](https://openjdk.org/jeps/444)
-   [Spring Boot 3.2 Release Notes (Virtual Threads)](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.2-Release-Notes#support-for-virtual-threads)
-   [Embracing Virtual Threads (Spring Blog)](https://spring.io/blog/2022/10/11/embracing-virtual-threads)