---
title: "Project Loom: Java 가상 스레드와 동시성 프로그래밍의 혁신"
date: 2025-10-04
categories: [Java, JVM]
tags: [Project Loom, Virtual Threads, Concurrency, Java 21, Spring Boot, TIL]
excerpt: "Java의 동시성 모델을 근본적으로 바꾸는 Project Loom과 가상 스레드(Virtual Threads)의 개념을 학습합니다. 기존 플랫폼 스레드의 한계를 알아보고, 가상 스레드가 어떻게 적은 리소스로 높은 처리량을 달성하는지 그 원리와 Spring Boot 적용법을 탐구합니다."
author_profile: true
---

# Today I Learned: Project Loom: Java 가상 스레드와 동시성 프로그래밍의 혁신

## 📚 오늘 학습한 내용

전통적인 Java 웹 애플리케이션은 **"요청 당 스레드(Thread-per-request)"** 모델을 사용해왔습니다. 이는 각 사용자 요청을 별도의 스레드에서 처리하는 직관적인 방식이지만, 수만, 수십만 개의 동시 요청을 처리해야 하는 현대적인 서비스 환경에서는 심각한 한계에 부딪힙니다. 오늘은 이 문제를 해결하기 위해 Java 21에서 정식으로 등장한 혁신적인 기능, **Project Loom**의 **가상 스레드(Virtual Threads)**에 대해 학습했습니다.

---

### 1. **기존 동시성 모델의 한계: 비싼 OS 스레드**

우리가 지금까지 Java에서 `new Thread()`로 생성했던 스레드는 실제로는 운영체제(OS)가 직접 관리하는 **플랫폼 스레드(Platform Threads)**의 얇은 래퍼(Wrapper)입니다.

-   **문제점**:
    1.  **높은 비용**: 플랫폼 스레드는 OS 커널 수준에서 생성되고 스케줄링되므로, 생성 비용이 비싸고 많은 메모리(보통 1MB 이상)를 차지합니다.
    2.  **제한된 개수**: 하나의 시스템이 생성할 수 있는 플랫폼 스레드의 개수는 수천 개 수준으로 제한적입니다. 10만 개의 동시 요청을 처리하기 위해 10만 개의 스레드를 생성하는 것은 사실상 불가능합니다.
    3.  **블로킹(Blocking)의 비효율**: 데이터베이스 조회나 외부 API 호출과 같은 I/O 작업이 발생하면, 해당 스레드는 작업이 끝날 때까지 **차단(Blocked)**됩니다. 이 시간 동안 비싼 플랫폼 스레드는 아무 일도 하지 않고 자원만 낭비하게 됩니다.

이 문제를 해결하기 위해 과거에는 `CompletableFuture`나 WebFlux 같은 복잡한 비동기/논블로킹 프로그래밍 기법을 사용해야 했습니다.

---

### 2. **해결책: JVM이 관리하는 경량 스레드, 가상 스레드(Virtual Threads)**

**가상 스레드**는 OS가 아닌 **JVM에 의해 관리되는 매우 가벼운(Lightweight) 스레드**입니다.

-   **핵심 원리**:
    -   수많은 가상 스레드들이 소수의 실제 플랫폼 스레드(이를 **Carrier Thread**라고 함) 위에서 실행됩니다.
    -   가상 스레드가 데이터베이스 조회와 같은 블로킹 I/O 작업을 만나면, 해당 가상 스레드는 **차단되지 않고 잠시 중단(suspended)**됩니다.
    -   그동안 JVM은 해당 가상 스레드가 사용하던 플랫폼 스레드를 다른 가상 스레드에 할당하여 다른 작업을 처리하도록 합니다.
    -   I/O 작업이 완료되면, JVM은 중단되었던 가상 스레드를 다시 가져와 비어있는 플랫폼 스레드 위에서 작업을 이어갑니다.



-   **비유**:
    -   **플랫폼 스레드**: 매우 비싸고 강력한 소수의 '산업용 로봇'.
    -   **가상 스레드**: 수많은 '가상 작업자'.
    -   한 작업자가 재료를 기다리는 동안(I/O 대기), 로봇은 그 작업자를 잠시 내려놓고 다른 작업자를 데려와 다른 일을 처리합니다. 이로써 로봇(플랫폼 스레드)은 단 한 순간도 쉬지 않고 일하게 되어 전체 공장(애플리케이션)의 생산성이 극대화됩니다.

#### **가상 스레드 생성 예제**
```java
public class VirtualThreadExample {
    public static void main(String[] args) throws InterruptedException {
        // 100만 개의 가상 스레드 생성 및 실행
        // 플랫폼 스레드였다면 OutOfMemoryError가 발생할 수 있음
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < 1_000_000; i++) {
                int taskNumber = i;
                executor.submit(() -> {
                    // System.out.println("Executing task " + taskNumber + " in thread " + Thread.currentThread());
                    try {
                        Thread.sleep(1000); // I/O 작업 시뮬레이션
                    } catch (InterruptedException e) {
                        // ...
                    }
                });
            }
        } // try-with-resources 구문으로 executor 자동 종료
        
        System.out.println("All tasks submitted.");
    }
}
```

---

### 3. **Spring Boot에서 가상 스레드 사용하기**

Spring Boot 3.2 이상 버전에서는 간단한 설정 하나로 내장 웹 서버(Tomcat)가 모든 HTTP 요청을 가상 스레드로 처리하도록 할 수 있습니다.

**`application.properties`**
```properties
# 이 설정 하나만으로 모든 웹 요청이 가상 스레드에서 처리됨
spring.threads.virtual.enabled=true
```
이 설정을 추가하는 것만으로, 기존의 동기/블로킹 방식으로 작성된 컨트롤러 코드를 전혀 수정하지 않고도 애플리케이션의 동시 처리량을 극적으로 향상시킬 수 있습니다.

---

## 💡 배운 점

1.  **동시성 프로그래밍의 패러다임 전환**: 가상 스레드는 복잡한 비동기 코드 없이, 기존의 간단하고 직관적인 동기/블로킹 코드 스타일을 그대로 유지하면서도 논블로킹 방식에 버금가는 높은 처리량을 달성할 수 있게 해주는 혁신적인 기술임을 깨달았습니다.
2.  **'블로킹'은 더 이상 죄가 아니다**: 기존에는 성능을 위해 블로킹 코드를 피해야 한다는 인식이 강했지만, 가상 스레드 환경에서는 블로킹 I/O가 발생해도 JVM이 알아서 효율적으로 처리해주므로, 더 이상 블로킹을 두려워할 필요가 없어졌습니다. 이는 코드의 가독성과 유지보수성을 크게 향상시킵니다.
3.  **기술의 진화 방향**: Project Loom은 개발자가 비즈니스 로직에 더 집중할 수 있도록 복잡한 기술적 문제를 JVM 레벨에서 해결해주는 방향으로 Java가 진화하고 있음을 보여주는 좋은 예시입니다. 앞으로는 애플리케이션 레벨의 복잡한 동시성 처리보다 JVM의 동작 원리를 이해하는 것이 더 중요해질 것이라 생각합니다.

---

## 🔗 참고 자료

-   [JEP 444: Virtual Threads (Official Proposal)](https://openjdk.org/jeps/444)
-   [Spring Boot with Virtual Threads (Official Blog)](https://spring.io/blog/2022/10/11/embracing-virtual-threads)
-   [Introduction to Java Virtual Threads (Baeldung)](https://www.baeldung.com/java-virtual-threads)