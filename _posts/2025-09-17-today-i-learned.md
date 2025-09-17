---
title: "JUnit 5를 사용한 단위 테스트"
date: 2025-09-17
categories: [테스트]
tags: [JUnit, Unit Test, TDD]
excerpt: "JUnit 5를 사용하여 Java 코드의 단위 테스트를 작성하는 방법과 주요 기능에 대해 학습합니다."
author_profile: true
---

# Today I Learned: JUnit 5를 사용한 단위 테스트

## 📚 오늘 학습한 내용

### 1. JUnit 5 소개
- JUnit 5는 Java에서 단위 테스트를 작성하기 위한 프레임워크입니다.
- JUnit 4에 비해 모듈화된 아키텍처와 다양한 새로운 기능을 제공합니다.
- Jupiter, Platform, Vintage 세 가지 모듈로 구성됩니다.

### 2. 주요 어노테이션
- `@Test`: 테스트 메서드를 표시합니다.
- `@BeforeEach`: 각 테스트 메서드 실행 전에 실행될 메서드를 표시합니다.
- `@AfterEach`: 각 테스트 메서드 실행 후에 실행될 메서드를 표시합니다.
- `@BeforeAll`: 모든 테스트 메서드 실행 전에 한 번 실행될 메서드를 표시합니다.
- `@AfterAll`: 모든 테스트 메서드 실행 후에 한 번 실행될 메서드를 표시합니다.
- `@DisplayName`: 테스트 이름을 지정합니다.
- `@Disabled`: 테스트를 비활성화합니다.
- `@Nested`: 중첩된 테스트 클래스를 정의합니다.
- `@Tag`: 테스트에 태그를 지정합니다.
- `@ParameterizedTest`: 파라미터화된 테스트를 작성합니다.

## 💻 코드 예시

```java
import org.junit.jupiter.api.*;

import static org.junit.jupiter.api.Assertions.*;

class CalculatorTest {

    private Calculator calculator;

    @BeforeAll
    static void beforeAll() {
        System.out.println("BeforeAll");
    }

    @BeforeEach
    void setUp() {
        System.out.println("BeforeEach");
        calculator = new Calculator();
    }

    @Test
    @DisplayName("덧셈 테스트")
    void add() {
        System.out.println("add");
        assertEquals(5, calculator.add(2, 3));
    }


    @AfterEach
    void tearDown() {
        System.out.println("AfterEach");
    }

    @AfterAll
    static void afterAll() {
        System.out.println("AfterAll");
    }
}
```

## 🔍 문제 상황 및 해결 과정

### 문제 상황
- 기존 JUnit 4에서는 테스트 메서드 이름을 지정하는 것이 제한적이었습니다.

### 해결 과정
1. JUnit 5의 `@DisplayName` 어노테이션을 사용하여 테스트 메서드에 명시적인 이름을 지정할 수 있습니다.

### 결과
- 테스트 결과 보고서에서 테스트 메서드의 이름을 명확하게 확인할 수 있습니다.

## 💡 배운 점

- JUnit 5는 다양한 어노테이션을 제공하여 테스트 코드를 더욱 효율적으로 작성할 수 있습니다.
- `@DisplayName` 어노테이션을 사용하여 테스트 메서드의 의도를 명확하게 표현할 수 있습니다.
- JUnit 5의 모듈화된 아키텍처는 확장성과 유연성을 제공합니다.

## 🔗 참고 자료

- [JUnit 5 User Guide](https://junit.org/junit5/docs/current/user-guide/)

## 📝 추가로 학습할 것

- JUnit 5의 다른 어노테이션과 기능들을 학습합니다.
- Mockito, Testcontainers 등 다른 테스트 관련 라이브러리와의 연동을 학습합니다.

## 🎯 다음 목표

- JUnit 5를 사용하여 프로젝트의 단위 테스트를 작성합니다.
- TDD(Test-Driven Development) 방법론을 적용하여 개발합니다.

---