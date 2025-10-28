---
title: "Java 동시성 이슈: 가시성과 원자성 문제 해결하기"
date: 2025-09-23
categories: [Java, CS]
tags: [Concurrency, Volatile, Synchronized, JMM, Atomicity, Visibility, TIL]
excerpt: "Java 멀티스레드 환경에서 발생하는 고질적인 문제인 가시성(Visibility)과 원자성(Atomicity) 이슈의 원인을 Java 메모리 모델(JMM)을 통해 이해하고, volatile과 synchronized 키워드를 사용한 해결 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Java 동시성 이슈: 가시성과 원자성 문제 해결하기

## 📚 오늘 학습한 내용

Java 멀티스레드 프로그래밍은 애플리케이션의 성능을 극대화할 수 있는 강력한 도구이지만, 여러 스레드가 공유 자원(Shared Resource)에 동시에 접근할 때 예기치 않은 문제를 일으킬 수 있습니다. 오늘은 그중 가장 대표적인 **가시성(Visibility)**과 **원자성(Atomicity)** 문제의 원인과 해결책에 대해 깊이 있게 학습했습니다.

---

### 1. **문제의 근원: Java 메모리 모델(JMM)과 CPU 캐시**

이 문제를 이해하려면 먼저 Java 메모리 모델(JMM)과 CPU의 동작 방식을 알아야 합니다.

-   **Main Memory (메인 메모리)**: 모든 스레드가 공유하는 데이터가 저장되는 주 기억장치입니다.
-   **CPU Cache (CPU 캐시)**: 각 CPU 코어는 성능 향상을 위해 메인 메모리의 데이터를 복사해 와서 사용하는 자신만의 고속 캐시 메모리를 가집니다.

각 스레드는 별도의 CPU 코어에서 실행될 수 있으며, 이때 스레드는 메인 메모리가 아닌 **자신의 CPU 캐시에 저장된 값을 사용**하게 됩니다. 바로 이 지점에서 동시성 문제가 발생합니다.

-   **가시성 문제**: 한 스레드가 공유 변수의 값을 변경해도, 다른 스레드의 CPU 캐시에는 이전 값이 그대로 남아 있어 변경된 값을 즉시 보지 못하는 문제입니다.
-   **원자성 문제**: `count++`와 같이 단일 연산처럼 보이는 작업이 실제로는 '읽기-수정-쓰기'의 여러 단계로 나뉘어 실행됩니다. 이 단계 사이에 다른 스레드가 끼어들면 연산이 누락되어 값이 꼬이게 됩니다.



---

### 2. **가시성(Visibility) 문제와 `volatile`**

`volatile` 키워드는 특정 변수를 **메인 메모리에서 직접 읽고 쓰도록 강제**하여 가시성 문제를 해결합니다.

-   **동작 원리**:
    1.  **쓰기(Write)**: `volatile` 변수에 값을 쓸 때, 해당 값은 즉시 CPU 캐시를 거쳐 메인 메모리에 반영됩니다.
    2.  **읽기(Read)**: `volatile` 변수를 읽을 때, CPU 캐시에 저장된 값이 있더라도 무시하고 항상 메인 메모리에서 최신 값을 가져옵니다.

#### **`volatile` 사용 예제**

아래 코드는 `running` 플래그를 사용하여 한 스레드가 다른 스레드를 멈추게 하는 예제입니다. `volatile`이 없으면 `worker` 스레드는 `main` 스레드가 변경한 `running` 값을 자신의 캐시에서만 읽어 무한 루프에 빠질 수 있습니다.

```java
public class VisibilityExample {
    // volatile 키워드로 가시성 문제 해결
    private static volatile boolean running = true;

    public static void main(String[] args) throws InterruptedException {
        // Worker 스레드: running이 true인 동안 계속 실행
        Thread worker = new Thread(() -> {
            while (running) {
                // ... 작업 수행 ...
            }
            System.out.println("Worker thread finished.");
        });

        worker.start();

        Thread.sleep(1000); // 1초 대기

        System.out.println("Stopping worker thread...");
        running = false; // main 스레드가 running 값을 변경
        worker.join();
        System.out.println("Main thread finished.");
    }
}
```

> **핵심**: `volatile`은 하나의 스레드가 쓰고 여러 스레드가 읽는 상황에서 **가장 최신의 값을 보장**하는 데 효과적입니다. 하지만 원자성은 보장하지 못합니다.

---

### 3. **원자성(Atomicity) 문제와 `synchronized`**

`synchronized` 키워드는 **임계 영역(Critical Section)**을 설정하여 오직 하나의 스레드만 해당 코드 블록이나 메서드에 접근하도록 보장합니다. 이를 통해 원자성을 확보합니다.

-   **동작 원리**:
    -   `synchronized` 블록에 진입하기 전에 스레드는 객체에 대한 **Lock(락)**을 획득해야 합니다.
    -   하나의 스레드가 락을 획득하면, 다른 스레드들은 해당 락이 해제될 때까지 대기(Blocked) 상태가 됩니다.
    -   블록 실행이 끝나면 스레드는 락을 자동으로 해제합니다.
    -   `synchronized`는 원자성을 보장할 뿐만 아니라, 블록이 끝날 때 변경된 값을 메인 메모리에 반영하므로 **가시성 문제도 함께 해결**합니다.

#### **`synchronized` 사용 예제**

여러 스레드가 동시에 `count++`를 실행하면 값이 누락될 수 있습니다. `synchronized`로 `increment()` 메서드를 감싸면 이 연산이 원자적으로 실행되어 항상 정확한 결과가 나옵니다.

```java
public class AtomicityExample {
    private int count = 0;

    // increment 메서드 전체를 동기화하여 원자성 보장
    public synchronized void increment() {
        count++; // 읽기, 수정, 쓰기 작업이 하나의 원자적 단위로 묶임
    }

    public static void main(String[] args) throws InterruptedException {
        AtomicityExample example = new AtomicityExample();

        Thread t1 = new Thread(() -> {
            for (int i = 0; i < 10000; i++) {
                example.increment();
            }
        });

        Thread t2 = new Thread(() -> {
            for (int i = 0; i < 10000; i++) {
                example.increment();
            }
        });

        t1.start();
        t2.start();

        t1.join();
        t2.join();

        // synchronized가 없으면 20000보다 작은 값이 나올 수 있음
        System.out.println("Final count: " + example.count);
    }
}
```

| 구분 | **`volatile`** | **`synchronized`** |
| :--- | :--- | :--- |
| **주요 목적** | 가시성(Visibility) 확보 | 원자성(Atomicity) 확보 |
| **락(Lock)** | 사용하지 않음 | 사용함 (객체 락) |
| **적용 대상** | 변수 | 메서드, 코드 블록 |
| **성능** | 상대적으로 가벼움 | 락 경쟁 시 성능 저하 가능성 있음 |
| **부가 효과** | 없음 | 가시성도 함께 보장 |

---

## 💡 배운 점

1.  **동시성 문제는 CPU 캐시와 JMM의 특성 때문에 발생**하는 구조적인 문제입니다. 단순히 코드를 눈으로 봐서는 문제를 발견하기 어렵다는 것을 깨달았습니다.
2.  **`volatile`은 가시성만을 위한 경량 솔루션**입니다. 여러 스레드가 하나의 변수를 수정하는 복합 연산(`i++`)에는 부적합하며, 오직 하나의 스레드만 값을 쓰고 다른 스레드들은 읽기만 하는 '상태 플래그' 등에 적합합니다.
3.  **`synchronized`는 원자성과 가시성을 모두 보장하는 강력한 도구**입니다. 하지만 락을 획득하고 해제하는 과정에서 성능 비용이 발생하므로, 반드시 필요한 최소한의 범위에만 적용해야 한다는 점을 명심해야 합니다.
