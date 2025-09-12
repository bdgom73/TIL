---
title: "Spring Boot 순환참조 문제와 해결 방법"
date: 2025-09-12
categories: [Spring Boot, Dependency Injection, Java]
tags: [Spring, Spring Boot, Circular Dependency, Dependency Injection, Lazy Initialization]
excerpt: "Spring Boot의 순환참조 발생 원인 및 해결 방법에 대해 학습하면서, 순환참조를 방지하는 설계 방법과 해결 방식을 익혔다."
author_profile: true
---

### TIL: Spring Boot 순환참조 문제와 해결 방법

#### 오늘의 학습 내용

1. **Spring에서 순환참조란?**
   - **순환참조(Circular Dependency)**는 두 개 이상의 빈(Bean)이 서로를 의존하여 빈 생성을 완료하지 못하는 상태를 의미.
   - 예를 들어:
      - A 객체가 B 객체를 주입받고,
      - B 객체가 다시 A 객체를 주입받으려고 할 때 발생.

2. **Spring Boot의 순환참조 기본 설정**
   - Spring Boot 2.6부터 **순환참조가 기본적으로 금지**됨.
   - 이전 버전(2.5 이하)의 경우 기본적으로 허용되며, 이를 해결하기 위해 **프록시 객체**를 사용했으나, 복잡한 구조에서는 예기치 않은 동작을 유발할 가능성이 있었음.

3. **순환참조 문제 해결 방법**  
   순환참조는 보통 설계 상의 문제로 간주되며, 일반적으로 다음과 같은 방법으로 해결이 가능:
   - **설계 변경**: 의존 관계를 단방향으로 수정하여 구조를 단순화.
   - **Lazy Initialization (지연 초기화)**: `@Lazy` 어노테이션을 통해 필요한 시점에 초기화.
     ```java
     @Component
     public class A {
         private final B b;

         public A(@Lazy B b) {
             this.b = b;
         }
     }
     ```
   - **Setter 또는 Method Injection 사용**: 의존성 주입을 생성자 대신 메서드나 세터를 통해 수행, 순환참조를 완화.
     ```java
     @Component
     public class A {
         private B b;

         @Autowired
         public void setB(B b) {
             this.b = b;
         }
     }
     ```
   - **필요 시 순환참조 허용 설정**:  
     `application.properties` 또는 `application.yml`에서 아래 설정으로 순환참조를 허용할 수 있음.
     ```properties
     spring.main.allow-circular-references=true
     ```

4. **순환참조 발생 가능성이 높은 사례**
   - 계층 간 의존성이 복잡하게 얽혀 있는 경우 (예: Service 간 직접 참조).
   - 컨트롤러에서 서비스나 리포지토리를 동시에 참조할 때.
   - 객체 간 의존성이 명확히 분리되지 않는 경우, 빈 생성 과정에서 문제가 발생하기 쉬움.

---

#### 느낀 점 및 반성

- 순환참조 문제는 설계 복잡도로 이어질 가능성이 높음을 알게 되었음.
- Spring Boot 2.6 이후 버전에선 순환참조가 기본적으로 금지되어 이를 설계 단계에서 해결하도록 유도. 이는 더 나은 아키텍처 설계에 기여함.
- 앞으로 개발 시 의존성을 명확히 하고, 문제 발생 시 빈 초기화 우선순위를 파악하며 Lazy Initialization과 같은 방식을 적극 활용할 예정.

#### 내일 학습 계획
1. Circular Dependency 발생 위험을 줄이는 **DDD (Domain-Driven Design)** 설계 방법 이해.
2. Spring Boot의 Auto-Configuration 과정에서 의존성 구조 확인 방법 익히기.