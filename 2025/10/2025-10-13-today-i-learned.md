---
title: "Java 동시성 컬렉션(Concurrent Collections)의 이해와 활용"
date: 2025-10-13
categories: [Java, Concurrency]
tags: [ConcurrentHashMap, CopyOnWriteArrayList, Concurrency, Collections, Thread-Safe, TIL]
excerpt: "멀티스레드 환경에서 일반적인 컬렉션(ArrayList, HashMap 등)을 사용할 때 발생하는 문제를 알아보고, 이를 해결하기 위한 Java의 동시성 컬렉션(ConcurrentHashMap, CopyOnWriteArrayList 등)의 동작 원리와 각각의 장단점을 학습합니다."
author_profile: true
---

# Today I Learned: Java 동시성 컬렉션(Concurrent Collections)의 이해와 활용

## 📚 오늘 학습한 내용

멀티스레드 환경에서 여러 스레드가 하나의 데이터 구조에 동시에 접근할 때, 예기치 않은 문제가 발생할 수 있습니다. 예를 들어, 한 스레드가 `ArrayList`를 순회하는 동안 다른 스레드가 요소를 추가하거나 삭제하면 `ConcurrentModificationException`이 발생하거나 데이터의 일관성이 깨질 수 있습니다.

오늘은 이러한 문제를 해결하기 위해 Java에서 제공하는 **스레드-세이프(Thread-safe)**한 컬렉션, 즉 **동시성 컬렉션(Concurrent Collections)**의 동작 원리와 올바른 사용법에 대해 학습했습니다.

---

### 1. **왜 일반 컬렉션은 멀티스레드 환경에서 위험한가? 💣**

-   `ArrayList`, `HashMap`과 같은 일반적인 컬렉션들은 **스레드-세이프하지 않습니다.** 즉, 여러 스레드가 동시에 접근할 때 데이터의 무결성을 보장하도록 설계되지 않았습니다.
-   과거에는 `Collections.synchronizedMap(new HashMap<>())`과 같이 컬렉션 전체를 하나의 락(Lock)으로 감싸서 동기화를 구현했습니다.
    -   **문제점**: 이 방식은 한 번에 오직 하나의 스레드만 컬렉션에 접근할 수 있도록 만들기 때문에, 여러 스레드가 동시에 작업을 처리하는 멀티스레딩의 이점을 전혀 살리지 못하고 **심각한 성능 저하**를 유발합니다. 모든 스레드가 하나의 문을 통과하기 위해 길게 줄을 서는 것과 같습니다.

---

### 2. **`ConcurrentHashMap`: 더 작게 잠그고, 더 빠르게 처리하라 ⚡️**

**`ConcurrentHashMap`**은 `synchronizedMap`의 성능 문제를 개선한 고성능 동시성 해시맵입니다.

-   **핵심 원리: Lock Striping (락 스트라이핑)**
    -   `synchronizedMap`이 맵 전체를 하나의 락으로 잠그는 것과 달리, `ConcurrentHashMap`은 내부적으로 데이터를 여러 개의 **세그먼트(Segment)** 또는 **버킷(Bucket)**으로 나눕니다.
    -   데이터를 수정할 때 맵 전체가 아닌, **해당 데이터가 속한 세그먼트(버킷)에만 락**을 겁니다.
    -   따라서 서로 다른 세그먼트에 있는 데이터에 접근하는 스레드들은 락 경합 없이 **동시에 작업을 수행**할 수 있습니다.



-   **특징**:
    -   **높은 동시성**: 읽기 작업은 대부분 락 없이 수행되며, 쓰기 작업도 락의 범위를 최소화하여 동시 처리 성능이 매우 뛰어납니다.
    -   **이터레이터(Iterator) 안전성**: `ConcurrentHashMap`의 이터레이터는 생성 시점의 스냅샷을 기반으로 동작하여, 순회 중에 다른 스레드가 맵을 수정하더라도 `ConcurrentModificationException`을 발생시키지 않습니다.

---

### 3. **`CopyOnWriteArrayList`: 읽기는 자유롭게, 쓰기는 신중하게 📝**

**`CopyOnWriteArrayList`**는 **읽기 작업이 쓰기 작업보다 압도적으로 많을 때** 매우 효과적인 스레드-세이프 리스트입니다.

-   **핵심 원리: Copy-on-Write (쓰기 시 복사)**
    1.  **읽기 작업**: 읽기 작업 시에는 어떠한 락도 사용하지 않습니다. 여러 스레드가 완전히 자유롭게 데이터를 읽을 수 있습니다.
    2.  **쓰기 작업 (add, set, remove)**:
        -   리스트에 변경이 발생하면, 내부적으로 **전체 배열의 복사본**을 새로 만듭니다.
        -   이 복사본에 변경 사항을 적용합니다.
        -   변경이 완료되면, 내부 포인터가 기존 배열에서 새로운 복사본 배열을 가리키도록 **원자적으로(atomically) 교체**합니다.



-   **특징**:
    -   **읽기 성능 극대화**: 읽기 작업에는 동기화 비용이 전혀 없어 매우 빠릅니다.
    -   **높은 쓰기 비용**: 쓰기 작업이 발생할 때마다 전체 배열을 복사하므로, 데이터가 많거나 쓰기가 잦은 경우에는 메모리 사용량이 많고 성능이 저하될 수 있습니다.
    -   **데이터 일관성**: 한 스레드가 쓰기 작업을 진행하는 동안, 다른 읽기 스레드들은 변경 전의 원본 배열을 보기 때문에 데이터의 일관성이 보장됩니다.

#### **예제 코드**
```java
// 읽기 작업은 매우 빠르다.
List<String> list = new CopyOnWriteArrayList<>();
list.add("Apple");
list.add("Banana");

// 스레드 1: 리스트 순회 (락 없음)
new Thread(() -> {
    for (String fruit : list) {
        System.out.println("Reading: " + fruit);
        try { Thread.sleep(100); } catch (InterruptedException e) {}
    }
}).start();

// 스레드 2: 리스트 수정 (내부적으로 복사 발생)
new Thread(() -> {
    try { Thread.sleep(50); } catch (InterruptedException e) {}
    System.out.println("--- Writing: Adding Orange ---");
    list.add("Orange"); // 이 시점에 스레드 1은 여전히 원본 리스트("Apple", "Banana")를 보고 있음
}).start();
```

---

## 💡 배운 점

1.  **상황에 맞는 동시성 컬렉션을 선택해야 한다**: `synchronized` 키워드로 무조건 감싸는 것은 멀티스레드 환경에서 최악의 선택일 수 있습니다. 데이터의 읽기/쓰기 패턴을 분석하여, 쓰기 경합이 잦다면 `ConcurrentHashMap`을, 읽기가 압도적으로 많다면 `CopyOnWriteArrayList`를 사용하는 등 상황에 맞는 최적의 자료구조를 선택하는 것이 중요함을 깨달았습니다.
2.  **'불변성(Immutability)'과 '복사'의 힘**: `CopyOnWriteArrayList`의 동작 원리는, 원본 데이터를 절대 바꾸지 않고 복사본을 만들어 변경함으로써 동시성 문제를 해결하는 함수형 프로그래밍의 '불변성' 철학과 맞닿아 있습니다. 이는 복잡한 락 없이도 데이터의 일관성을 유지하는 매우 우아한 방법입니다.
3.  **성능은 '잠금의 범위'에 달려있다**: `ConcurrentHashMap`이 빠른 이유는 결국 락을 얼마나 작게, 필요한 부분에만 거느냐에 달려있습니다. 동시성 프로그래밍의 성능을 개선할 때, 무작정 락을 없애려고 하기보다 락이 걸리는 범위를 줄이는 것(Lock Granularity)이 현실적이고 효과적인 해결책이 될 수 있다는 것을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Java Docs - java.util.concurrent](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/package-summary.html)
-   [ConcurrentHashMap vs. Synchronized HashMap (Baeldung)](https://www.baeldung.com/java-concurrenthashmap-vs-synchronizedhashmap)
-   [CopyOnWriteArrayList in Java (Baeldung)](https://www.baeldung.com/java-copy-on-write-arraylist)