---
title: "클린 아키텍처(Clean Architecture)를 Spring Boot에 적용하기"
date: 2025-10-10
categories: [Architecture, Design Pattern]
tags: [Clean Architecture, Spring Boot, DDD, Software Design, TIL]
excerpt: "소프트웨어의 유지보수성과 테스트 용이성을 극대화하는 클린 아키텍처(Clean Architecture)의 핵심 원칙을 학습합니다. 의존성 규칙(Dependency Rule)을 중심으로 각 계층의 역할을 이해하고, 실제 Spring Boot 프로젝트에 어떻게 적용할 수 있는지 패키지 구조와 코드를 통해 알아봅니다."
author_profile: true
---

# Today I Learned: 클린 아키텍처(Clean Architecture)를 Spring Boot에 적용하기

## 📚 오늘 학습한 내용

좋은 소프트웨어 아키텍처의 목표는 시간이 지나도 **유지보수하기 쉽고**, **변화에 유연**하며, **테스트하기 쉬운** 시스템을 만드는 것입니다. 로버트 C. 마틴(Uncle Bob)이 제안한 **클린 아키텍처(Clean Architecture)**는 이러한 목표를 달성하기 위한 구체적인 설계 원칙과 구조를 제시합니다. 오늘은 클린 아키텍처의 핵심 사상과 이를 실제 Spring Boot 프로젝트에 어떻게 적용할 수 있는지 학습했습니다.

---

### 1. **클린 아키텍처의 핵심: 의존성 규칙 (The Dependency Rule)**

클린 아키텍처는 시스템을 여러 개의 동심원 계층으로 나누어 관심사를 분리하는 것을 핵심으로 합니다. 그리고 이 계층들 사이에는 **단 하나의 엄격한 규칙**이 존재합니다.

> **의존성 규칙**: 모든 소스 코드 의존성은 반드시 **바깥쪽에서 안쪽으로**, 즉 저수준 정책에서 고수준 정책으로 향해야 한다.



-   **안쪽 계층 (고수준 정책)**: 시스템의 핵심 비즈니스 로직(도메인)을 담고 있으며, 가장 안정적이고 변화가 적어야 합니다.
-   **바깥쪽 계층 (저수준 정책)**: 프레임워크, 데이터베이스, UI 등 구체적인 기술 구현과 세부 사항을 담고 있습니다. 이들은 자주 변경될 수 있는 '도구'에 불과합니다.

이 규칙을 지킴으로써, 데이터베이스가 MySQL에서 PostgreSQL로 바뀌거나, API 프레임워크가 Spring MVC에서 다른 것으로 바뀌더라도 **핵심 비즈니스 로직(안쪽 계층)은 전혀 영향을 받지 않게 됩니다.**

---

### 2. **클린 아키텍처의 계층과 Spring Boot 패키지 구조 매핑**

클린 아키텍처는 대표적으로 4개의 계층을 제시합니다. 이를 Spring Boot 프로젝트의 패키지 구조에 다음과 같이 매핑해 볼 수 있습니다.

#### **① Entities (도메인 계층)**
-   **역할**: 애플리케이션의 가장 핵심적인 비즈니스 규칙과 데이터를 담습니다. 순수한 Plain Old Java Object(POJO)로, 외부 프레임워크에 대한 의존성이 전혀 없어야 합니다.
-   **Spring Boot 패키지**: `com.example.project.domain`

#### **② Use Cases (애플리케이션 계층)**
-   **역할**: 애플리케이션의 고유한 비즈니스 흐름(Use Case)을 구현합니다. "사용자가 주문을 생성한다"와 같은 시나리오를 담당합니다.
-   **핵심**: 이 계층은 도메인 계층의 객체들을 조합하여 비즈니스 로직을 수행합니다. 데이터베이스 접근 등 외부와의 통신은 **인터페이스(Interface)**에 의존합니다.
-   **Spring Boot 패키지**: `com.example.project.application.service`, `com.example.project.application.port` (인터페이스)

#### **③ Interface Adapters (어댑터 계층)**
-   **역할**: Use Case 계층과 외부 세계(프레임워크, DB 등) 사이에서 데이터를 변환하고 전달하는 '어댑터' 역할을 합니다.
-   **구성 요소**:
    -   **Web Adapters**: `@RestController` (외부 요청을 내부 Use Case 입력 모델로 변환)
    -   **Persistence Adapters**: `@Repository` 구현체 (Application 계층의 Repository 인터페이스를 구현)
-   **Spring Boot 패키지**: `com.example.project.adapter.in.web`, `com.example.project.adapter.out.persistence`

#### **④ Frameworks & Drivers (인프라 계층)**
-   **역할**: Spring Boot 프레임워크 자체, 데이터베이스(MySQL, H2), 외부 라이브러리 등 가장 바깥쪽에 위치하는 모든 세부 사항입니다. 개발자가 직접 코드를 작성하는 영역은 주로 어댑터 계층까지입니다.

---

### 3. **코드로 보는 의존성 규칙 적용**

`주문 생성` 유스케이스를 예로 들어 의존성 규칙이 어떻게 적용되는지 살펴봅시다.

**1. Domain Layer (`domain`)**
```java
// 순수한 비즈니스 모델. 프레임워크 의존성 없음.
public class Order {
    private Long id;
    private Money totalAmount;
    // ...
}
```

**2. Application Layer (`application`)**
```java
// application/port/out/SaveOrderPort.java
// **핵심**: 어떻게 저장할지는 모르지만, '저장한다'는 행위(Port)만 정의.
public interface SaveOrderPort {
    Order save(Order order);
}

// application/port/in/CreateOrderUseCase.java
public interface CreateOrderUseCase {
    Order createOrder(CreateOrderCommand command);
}

// application/service/CreateOrderService.java
@Service
public class CreateOrderService implements CreateOrderUseCase {
    private final SaveOrderPort saveOrderPort; // 인터페이스에 의존

    // ... 생성자 ...

    @Override
    public Order createOrder(CreateOrderCommand command) {
        // 비즈니스 로직 수행...
        Order newOrder = new Order(...);
        return saveOrderPort.save(newOrder); // 외부 세계와의 통신은 Port를 통해
    }
}
```
> `CreateOrderService`는 `SaveOrderPort`라는 **인터페이스**에만 의존합니다. JPA 구현체에 대해서는 전혀 알지 못합니다. 이것이 바로 의존성 역전 원칙(DIP)입니다.

**3. Adapter Layer (`adapter`)**
```java
// adapter/out/persistence/OrderPersistenceAdapter.java
// **핵심**: Application 계층의 Port 인터페이스를 '구현'.
@Repository
@RequiredArgsConstructor
public class OrderPersistenceAdapter implements SaveOrderPort {

    private final OrderJpaRepository orderJpaRepository; // Spring Data JPA는 외부 기술
    private final OrderMapper orderMapper;

    @Override
    public Order save(Order order) {
        OrderJpaEntity orderJpaEntity = orderMapper.toJpaEntity(order);
        OrderJpaEntity savedEntity = orderJpaRepository.save(orderJpaEntity);
        return orderMapper.toDomain(savedEntity);
    }
}

// adapter/in/web/OrderController.java
@RestController
@RequiredArgsConstructor
public class OrderController {
    private final CreateOrderUseCase createOrderUseCase; // Use Case 인터페이스에 의존

    @PostMapping("/orders")
    public ResponseEntity<Order> createOrder(@RequestBody CreateOrderRequest request) {
        CreateOrderCommand command = request.toCommand();
        Order createdOrder = createOrderUseCase.createOrder(command);
        return ResponseEntity.ok(createdOrder);
    }
}
```
> `OrderPersistenceAdapter`가 `SaveOrderPort`를 구현함으로써, 의존성의 방향이 바깥쪽(Adapter)에서 안쪽(Application)으로 향하게 됩니다.

---

## 💡 배운 점

1.  **아키텍처의 목적은 '유연성'이다**: 클린 아키텍처의 복잡해 보이는 계층 분리는 결국 '세부 사항(DB, Framework 등)을 쉽게 교체할 수 있는 유연성'을 확보하기 위함이라는 것을 깨달았습니다. 핵심 도메인은 그대로 둔 채, 기술 트렌드에 따라 바깥 계층만 교체하면 됩니다.
2.  **인터페이스의 진정한 힘**: 의존성 규칙을 지키는 핵심은 '인터페이스'에 의존하는 것입니다. 구체적인 구현이 아닌 추상화된 역할(Port)에 의존함으로써, 안쪽 계층은 바깥쪽 계층의 변화로부터 완벽하게 보호받을 수 있습니다.
3.  **테스트 용이성은 저절로 따라온다**: 도메인과 애플리케이션 계층은 외부 프레임워크나 DB에 대한 의존성이 없으므로, 매우 빠르고 간단하게 단위 테스트를 작성할 수 있습니다. `SaveOrderPort`를 Mocking하여 `CreateOrderService`의 비즈니스 로직을 순수하게 테스트할 수 있습니다.

---

## 🔗 참고 자료

-   [The Clean Code Blog - The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
-   [Book: Clean Architecture (Robert C. Martin)](https://www.yes24.com/Product/Goods/77283734)
-   [Get Your Hands Dirty on Clean Architecture (Book)](https://www.packtpub.com/product/get-your-hands-dirty-on-clean-architecture/9781839211966)