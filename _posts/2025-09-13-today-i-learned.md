---
title: "Spring Boot Auto-Configuration과 DDD 설계"
date: 2025-09-13
categories: [Spring Boot, DDD, Java]
tags: [Spring, Spring Boot, Auto-Configuration, Domain-Driven Design]
excerpt: "Spring Boot의 Auto-Configuration 과정과 DDD 설계 방법에 대해 학습하여 순환 참조 발생 위험을 줄이는 설계 방법과 Spring Boot의 의존성 주입 구조를 이해한다."
author_profile: true
---

### TIL: Spring Boot Auto-Configuration과 DDD 설계

#### 1. DDD (Domain-Driven Design) 설계

##### 1.1. DDD란 무엇인가?

- DDD는 도메인 전문가와 개발자가 협력하여 소프트웨어를 설계하는 방법론입니다.
- 도메인 로직을 명확하게 모델링하고, 이를 코드에 반영하여 복잡한 비즈니스 요구사항을 효과적으로 구현할 수 있습니다.
- 순환 참조 발생 위험 감소: DDD는 도메인 객체 간의 관계를 명확하게 정의하고, 의존성을 관리하여 순환 참조 발생 가능성을 줄입니다.

##### 1.2. DDD 주요 개념

* **엔티티(Entity):** 고유한 식별자를 가지는 객체. 예: `Order`, `Customer`
* **값 객체(Value Object):** 식별자 없이 값으로 비교되는 객체. 예: `Address`, `Money`
* **애그리거트(Aggregate):** 관련된 엔티티와 값 객체의 집합. 예: `Order` 애그리거트는 `Order` 엔티티와 `OrderItem` 엔티티, `ShippingAddress` 값 객체 등으로 구성될 수 있음.
* **리포지토리(Repository):** 애그리거트의 영속성을 관리하는 인터페이스.
* **도메인 서비스(Domain Service):** 여러 애그리거트에 걸친 복잡한 비즈니스 로직을 담는 객체.

##### 1.3. DDD 실습

온라인 쇼핑몰 도메인에서 `Order`와 `Customer` 엔티티가 있다고 가정합니다. `Order`는 `Customer`를 참조해야 하지만, `Customer`가 `Order`를 직접 참조하면 순환 참조가 발생할 수 있습니다. 이를 방지하기 위해 `Customer`는 `Order`를 직접 참조하지 않고, `OrderRepository`를 통해 `Order` 정보에 접근하도록 설계합니다.

```java
// Order 엔티티
public class Order {
    private Customer customer; // Customer 엔티티 참조

    // ...
}

// Customer 엔티티 (Order를 직접 참조하지 않음)
public class Customer {
    // ...
}

// OrderRepository 인터페이스
public interface OrderRepository {
    List<Order> findByCustomer(CustomerId customerId);
    // ...
}
```

#### 2. Spring Boot Auto-Configuration

##### 2.1. Spring Boot Auto-Configuration 이란?

- Spring Boot는 의존성을 자동으로 구성하는 Auto-Configuration 기능을 제공합니다.
- `spring-boot-autoconfigure` 라이브러리는 Spring Boot 애플리케이션에서 필요한 빈을 자동으로 등록하고 구성합니다.
- 의존성 구조 확인: Spring Boot Actuator를 사용하여 애플리케이션의 의존성 구조 및 Auto-Configuration 세부 정보를 확인할 수 있습니다.

##### 2.2. Auto-Configuration 원리

* Spring Boot는 클래스패스에 있는 라이브러리를 기반으로 필요한 빈을 자동으로 구성합니다.
* `@Conditional` 어노테이션을 사용하여 특정 조건이 충족될 때만 빈을 등록하도록 설정할 수 있습니다.
* `application.properties` 또는 `application.yml` 파일을 통해 Auto-Configuration 설정을 변경할 수 있습니다.

##### 2.3. Auto-Configuration 실습

Spring Boot 프로젝트에 `spring-boot-starter-web` 의존성을 추가하면, Spring Boot는 Tomcat, Spring MVC 등 웹 애플리케이션에 필요한 빈들을 자동으로 구성합니다. Actuator를 통해 `/beans` 엔드포인트에 접근하면 등록된 빈 목록과 의존 관계를 확인할 수 있습니다. `/autoconfig` 엔드포인트를 통해 적용된 Auto-Configuration 설정과 조건들을 확인할 수 있습니다.


#### 느낀 점

- DDD 설계 방법을 적용하면 도메인 로직이 명확해지고, 유지보수성이 향상됩니다.
- Spring Boot Auto-Configuration을 통해 의존성 관리가 간편해지고, 개발 생산성이 향상됩니다.