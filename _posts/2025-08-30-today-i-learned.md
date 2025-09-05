---
title: "Java 버전별 핵심 정리 (8, 11, 17, 21, 25)"
date: 2025-08-30
categories: [Java, Programming]
tags: [Java, Java8, Java11, Java17, Java21, Java25, Lambda, Stream, Records, VirtualThreads]
excerpt: "Java의 주요 릴리스 버전별 특징을 정리했습니다. Java 8의 람다와 스트림부터 Java 21의 가상 스레드까지, 각 버전의 핵심 기능들을 알아보세요."
author_profile: true
---

# Today I Learned: Java 버전별 핵심 정리 (8, 11, 17, 21, 25)

오늘은 자바의 주요 릴리스 버전별 특징을 정리해보았습니다. 각 버전이 어떤 변화를 가져왔는지, 그리고 앞으로 어떤 변화가 예정되어 있는지 간략하게 살펴보겠습니다.

---

## ☕️ Java 8 (2014년 3월)

**"자바의 혁명"** 이라 불리는 버전으로, 현대적인 프로그래밍 패러다임을 대거 도입했습니다. 아직도 많은 현업 시스템에서 사용되고 있는 매우 중요한 버전입니다.

* **람다 표현식 (Lambda Expressions)**
    * `->` 기호를 사용하여 익명 함수를 간결하게 표현할 수 있게 되었습니다. 이는 코드를 혁신적으로 줄여주고 가독성을 높였습니다.
    * 예시: `(a, b) -> a + b`

* **스트림 API (Stream API)**
    * 컬렉션(배열, 리스트 등)의 데이터를 선언형으로 처리할 수 있는 강력한 기능입니다. `filter`, `map`, `reduce` 등의 연산을 통해 복잡한 데이터 처리를 간결하게 구현할 수 있습니다.

* **Optional**
    * `NullPointerException`(NPE)을 방지하기 위해 등장했습니다. null이 될 수 있는 값을 감싸서 명시적으로 처리하도록 유도합니다.
    * Optional은 null을 방지한다기보다는 null을 포함할 가능성을 명시적으로 다룸으로써 에러를 줄이는 데 유용합니다.
* **새로운 날짜와 시간 API (Date and Time API)**
    * 기존의 `java.util.Date`와 `Calendar`의 단점을 보완한 `java.time` 패키지가 추가되었습니다. 불변(Immutable) 객체를 사용하여 스레드 안전성을 높이고, 직관적인 API를 제공합니다.

* **인터페이스의 기본 메소드 (Default Methods)**
    * 인터페이스 내에 구현을 포함한 메소드를 추가할 수 있게 되어, 기존 구현 클래스의 수정 없이 기능을 확장할 수 있게 되었습니다.

---

## 🚀 Java 11 (2018년 9월)

Java 8 이후 등장한 **첫 LTS 버전**으로, 많은 기업들이 Java 8에서 다음 버전으로 업그레이드할 때 주로 선택하는 버전입니다. 안정성과 성능 개선에 초점을 맞췄습니다.

* **단일 파일 소스 코드 실행**
    * `javac`로 컴파일하지 않고 `java` 명령어만으로 `.java` 소스 파일을 바로 실행할 수 있게 되었습니다. 간단한 스크립트나 테스트에 유용합니다.
    * 예시: `java MyProgram.java`

* **`var` 키워드 개선 (지역 변수 타입 추론)**
    * Java 10에서 도입된 `var` 키워드가 Java 11에서 람다 표현식에 확장되었습니다.
    * 예시: `(@NonNull var x, var y) -> x.process(y)`

* **새로운 `String` 메소드 추가**
    * `isBlank()`, `lines()`, `strip()`, `repeat()` 등 문자열 처리를 편리하게 해주는 유용한 메소드들이 추가되었습니다.

* **HTTP 클라이언트 API 표준화**
    * Java 9에서 인큐베이터 모듈로 소개되었던 HTTP 클라이언트 API가 표준으로 포함되었습니다. 비동기, WebSocket 등을 지원하는 현대적인 HTTP 클라이언트입니다.

* **ZGC (Z Garbage Collector) 도입**
    * 매우 짧은 `pause` 시간을 목표로 하는 확장 가능한 저지연 가비지 컬렉터입니다. 대용량 메모리를 다루는 애플리케이션에 유리합니다.

---

## ✨ Java 17 (2021년 9월)

Java 11 다음의 **LTS 버전**으로, 안정성과 함께 개발자 편의성을 높이는 새로운 기능들이 많이 추가되었습니다.

* **레코드 (Records)**
    * `final` 필드, `getter`, `equals()`, `hashCode()`, `toString()` 메소드를 자동으로 생성해주는 불변 데이터 객체입니다. DTO(Data Transfer Object)나 VO(Value Object) 작성 시 반복적인 코드를 크게 줄여줍니다.
    * 예시: `public record Point(int x, int y) {}`

* **봉인 클래스 (Sealed Classes)**
    * 상속받거나 구현할 수 있는 클래스를 특정 클래스들로 제한하는 기능입니다. 이를 통해 더 안정적이고 예측 가능한 클래스 계층 구조를 설계할 수 있습니다.

* **패턴 매칭 (Pattern Matching for `instanceof`)**
    * `instanceof` 연산과 타입 캐스팅을 한 번에 처리할 수 있게 되어 코드가 더 간결하고 안전해졌습니다.
    * 예시:
    ```java
    if (obj instanceof String s) {
        System.out.println(s.toUpperCase());
    }
    ```

* **향상된 의사 난수 생성기 API**
    * 다양한 의사 난수 생성 알고리즘을 플러그인 방식으로 사용할 수 있는 새로운 API를 제공합니다.

---

## 💡 Java 21 (2023년 9월)

가장 최신의 **LTS 버전**으로, 비동기 프로그래밍과 동시성 처리를 혁신적으로 개선하는 기능들이 대거 포함되었습니다.

* **가상 스레드 (Virtual Threads)**
    * **"Project Loom"** 의 결과물로, 기존 플랫폼 스레드보다 훨씬 가볍고 효율적인 스레드입니다. 적은 리소스로 수많은 동시 작업을 처리할 수 있어, 고성능 동시성 애플리케이션 개발의 패러다임을 바꿀 것으로 기대됩니다.

* **구조화된 동시성 (Structured Concurrency)**
    * 여러 스레드에서 실행되는 관련 작업들을 하나의 작업 단위로 처리하여, 오류 처리와 취소를 단순화하고 코드의 안정성을 높입니다.
    * try-with-resources와 유사한 방식으로 태스크 관리를 간단하게 구현 가능하지만 모든 경우에 효율적이라고 보장되지 않습니다.

* **레코드 패턴 (Record Patterns)**
    * 레코드의 구조를 분해하여 필드 값을 바로 변수로 추출할 수 있는 기능입니다. `switch` 문이나 `instanceof`와 함께 사용되어 코드를 더욱 간결하게 만듭니다.

* **`switch` 패턴 매칭**
    * `switch` 문에서 타입 패턴, 레코드 패턴 등 다양한 패턴을 사용하여 복잡한 조건 분기를 훨씬 직관적이고 안전하게 처리할 수 있습니다.
    * 예시:
    ```java
    switch (obj) {
        case String s -> System.out.println(s.toUpperCase());
        case Integer i -> System.out.println(i + 1);
        default -> System.out.println("Unknown type");
    }
    ```

* **시퀀스 컬렉션 (Sequenced Collections)**
    * 순서가 있는 컬렉션(List, Deque 등)을 위한 공통 인터페이스가 도입되어, 첫 요소, 마지막 요소 접근 및 역순 조회 등의 작업을 일관된 방식으로 처리할 수 있게 되었습니다.

---
## 요약: 릴리스별 주요 기능 정리
### Java 8
- 람다 표현식, 스트림 API, Optional, 새로운 날짜/시간 API
### Java 11
- 단일 파일 실행, String 메서드 추가, HTTP 클라이언트 표준화
### Java 17
- 레코드, 봉인 클래스, 의사 난수 생성기, 패턴 매칭
### Java 21
- 가상 스레드, 구조화된 동시성, `switch` 패턴 매칭, 시퀀스 컬렉션
### Java 25 (예정)
- 기본 객체, 범용 제네릭, Project Panama

## 🔮 Java 25 (2025년 9월 예정)
Java 25는 아직 개발 중으로, 일부 기능은 변경될 수 있습니다. **"Project Valhalla"** 를 비롯한 중요한 변화들이 포함될 것으로 예상됩니다.

* **기본 객체 (Primitive Objects)**
    * `int`와 같은 기본 타입(primitive type)의 성능과 `Integer`와 같은 참조 타입(reference type)의 객체 지향적 특성을 모두 갖춘 새로운 종류의 타입을 추가하여 메모리 효율성과 성능을 크게 높입니다.
    * 예시: 새로운 타입으로 `Point` 정의 시 객체 생성 없이 성능 이점 제공.

* **범용 제네릭 (Universal Generics)**
    * 기본 타입을 포함한 모든 타입에 대해 동작하는 제네릭을 구현하여, 메모리를 최적화하고 현재 제네릭의 한계를 극복하려는 시도가 이루어지고 있습니다.

* 기타 **"Project Panama"** 결과물:
    * 향상된 네이티브 코드와의 상호작용으로 성능 개선. 
    * JNI(Java Native Interface)를 대체하여 비효율성을 최소화.

