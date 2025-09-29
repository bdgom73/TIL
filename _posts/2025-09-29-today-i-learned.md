---
title: "JVM 메모리 구조와 GC 동작 원리 깊이 보기"
date: 2025-09-29
categories: [Java, JVM]
tags: [JVM, Garbage Collection, GC, Heap, Metaspace, Memory Management, TIL]
excerpt: "Java 애플리케이션의 실행 기반인 JVM의 메모리 구조(Heap, Stack, Metaspace 등)를 분석하고, 자동 메모리 관리의 핵심인 가비지 컬렉션(GC)이 어떤 원리로 동작하며 객체의 생명주기를 관리하는지 학습합니다."
author_profile: true
---

# Today I Learned: JVM 메모리 구조와 GC 동작 원리 깊이 보기

## 📚 오늘 학습한 내용

Java 개발자는 C/C++와 달리 메모리를 직접 할당하고 해제하는 작업에서 해방됩니다. 이는 **JVM(Java Virtual Machine)**의 **가비지 컬렉터(Garbage Collector, GC)**가 자동으로 메모리를 관리해주기 때문입니다. 오늘은 애플리케이션의 성능과 안정성에 직접적인 영향을 미치는 JVM의 메모리 구조와 GC의 동작 원리에 대해 깊이 있게 학습했습니다.

---

### 1. **JVM 메모리 구조 (Runtime Data Areas)**

JVM은 애플리케이션을 실행할 때 OS로부터 할당받은 메모리 공간을 여러 영역으로 나누어 관리합니다. 이를 **Runtime Data Areas**라고 부릅니다.



-   **Method Area (메서드 영역)**
    -   **역할**: 클래스 정보(메타데이터), static 변수, 상수, 메서드 코드 등 클래스 레벨의 데이터를 저장합니다.
    -   **특징**: 모든 스레드가 **공유**하는 영역입니다. Java 8부터는 기존의 PermGen(Permanent Generation)이 사라지고, OS가 관리하는 **네이티브 메모리 영역인 Metaspace**가 이 역할을 대신하게 되어 `OutOfMemoryError: PermGen space` 문제가 해결되었습니다.

-   **Heap Area (힙 영역)**
    -   **역할**: `new` 키워드로 생성된 모든 **객체(인스턴스)와 배열**이 저장되는 공간입니다.
    -   **특징**: 모든 스레드가 **공유**하며, **가비지 컬렉션(GC)이 발생하는 주된 공간**입니다. 성능 튜닝의 핵심 대상이 되는 영역입니다.

-   **Stack Area (스택 영역)**
    -   **역할**: 메서드 호출 정보를 저장하는 **스택 프레임(Stack Frame)**을 위한 공간입니다. 각 프레임에는 메서드의 매개변수, 지역 변수, 리턴 값 등이 저장됩니다.
    -   **특징**: **스레드마다 하나씩** 개별적으로 생성됩니다. 메서드 호출이 시작되면 프레임이 쌓이고(push), 메서드가 종료되면 프레임이 제거됩니다(pop). `StackOverflowError`가 발생하는 곳이 바로 이 영역입니다.

-   **PC Registers & Native Method Stacks**
    -   **PC Registers**: 현재 스레드가 실행 중인 JVM 명령어의 주소를 저장합니다.
    -   **Native Method Stacks**: C/C++ 등 Java 외의 네이티브 코드를 실행할 때 사용되는 스택입니다.

---

### 2. **가비지 컬렉션(GC)의 동작 원리**

GC의 핵심 목표는 **Heap 영역에서 더 이상 사용되지 않는 객체(Garbage)를 찾아내어 메모리에서 제거**하는 것입니다.

#### **Weak Generational Hypothesis (약한 세대 가설)**

대부분의 현대 GC는 아래 두 가지 가설을 전제로 설계됩니다.
1.  대부분의 객체는 생성된 직후 접근 불가능 상태(Unreachable)가 된다.
2.  오래 살아남은 객체에서 젊은 객체로의 참조는 거의 발생하지 않는다.

이 가설에 따라, Heap 영역은 객체의 생존 기간에 따라 **Young Generation**과 **Old Generation**으로 나뉩니다.

#### **GC의 동작 과정**


1.  **객체 생성 & Minor GC (in Young Generation)**
    -   `new`로 생성된 객체는 **Young Generation** 내의 **Eden** 영역에 할당됩니다.
    -   Eden 영역이 가득 차면 **Minor GC**가 발생합니다.
    -   이때, GC는 **GC Roots**(스택의 지역 변수, 메서드 영역의 static 변수 등)로부터 시작하여 참조 경로를 따라가며 **살아있는 객체(Reachable)**를 식별합니다.
    -   살아남은 객체들은 두 개의 **Survivor** 영역(S0, S1) 중 하나로 이동하며, 객체의 나이(age)가 1 증가합니다. 살아남지 못한 객체들은 메모리에서 제거됩니다.
    -   이 과정이 반복되며, 살아남은 객체들은 S0과 S1을 오가며 나이가 계속 증가합니다.

2.  **승격(Promotion) & Major GC (in Old Generation)**
    -   Survivor 영역에서 일정 나이 이상 살아남은 객체들은 **Old Generation**으로 이동(Promotion)됩니다. Old Generation은 상대적으로 오래 살아남는 객체들을 보관하는 곳입니다.
    -   Old Generation 영역이 가득 차면, **Major GC(또는 Full GC)**가 발생합니다. Major GC는 Young Generation보다 더 넓은 영역을 청소하므로, Minor GC에 비해 시간이 훨씬 오래 걸리고 성능에 큰 영향을 미칩니다.

#### **Stop-the-World**
GC가 실행될 때는 GC 스레드를 제외한 **모든 애플리케이션 스레드가 일시적으로 멈춥니다.** 이를 **'Stop-the-World'**라고 합니다. 이 중단 시간이 길어지면 애플리케이션의 응답 지연(Latency)이 발생하므로, GC 튜닝의 핵심은 이 'Stop-the-World' 시간을 최소화하는 것입니다. G1GC, ZGC 같은 최신 GC 알고리즘은 이 중단 시간을 줄이는 데 초점을 맞추고 있습니다.

---

## 💡 배운 점

1.  **메모리 누수는 GC가 있어도 발생한다**: GC는 참조가 없는 객체만 수거합니다. 개발자의 실수로 객체에 대한 참조가 계속 유지된다면(e.g., static 컬렉션에 객체를 넣고 제거하지 않는 경우), 해당 객체는 영원히 메모리에 남아 메모리 누수(Memory Leak)를 일으킬 수 있다는 점을 명심해야 합니다.
2.  **성능 튜닝의 시작은 메모리 이해**: `OutOfMemoryError`나 긴 응답 지연 같은 성능 문제를 해결하려면, 문제의 원인이 어떤 메모리 영역에서 발생했는지 파악하는 것이 우선입니다. 힙 덤프(Heap Dump) 분석 등을 통해 Old Generation에 불필요한 객체가 쌓이는지, Metaspace가 부족한지 등을 진단할 수 있습니다.
3.  **GC는 공짜가 아니다**: 자동 메모리 관리는 매우 편리하지만, 'Stop-the-World'라는 명백한 비용이 따릅니다. 특히 Major GC는 서비스에 직접적인 영향을 줄 수 있으므로, 불필요한 객체 생성을 줄이고 Old Generation으로 객체가 넘어가는 것을 최소화하는 코딩 습관이 중요함을 깨달았습니다.

---

## 🔗 참고 자료

-   [The Java™ Virtual Machine Specification](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-2.html#jvms-2.5)
-   [Getting Started with the G1 Garbage Collector (Oracle)](https://www.oracle.com/technical-resources/articles/java/g1gc.html)
-   [Java Garbage Collection Basics (Baeldung)](https://www.baeldung.com/java-garbage-collection)