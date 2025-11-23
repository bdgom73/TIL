---
title: "Spring Modulith: 모듈러 모놀리스(Modular Monolith)로 아키텍처 복잡성 제어하기"
date: 2025-11-23
categories: [Spring, Architecture]
tags: [Spring Modulith, Modular Monolith, DDD, Architecture, MSA, Event-Driven, TIL]
excerpt: "무조건적인 MSA 전환이 정답일까요? 거대한 모놀리식 시스템의 복잡성을 해결하면서도 MSA의 운영 비용은 피할 수 있는 '모듈러 모놀리스' 아키텍처를 학습합니다. Spring Modulith를 사용하여 패키지 간의 의존성을 강제하고, 도메인 이벤트를 통해 모듈 간 결합도를 낮추는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Modulith: 모듈러 모놀리스(Modular Monolith)로 아키텍처 복잡성 제어하기

## 📚 오늘 학습한 내용

서비스가 커지면서 코드가 뒤엉키는 '스파게티 코드' 문제를 해결하기 위해 많은 팀이 MSA(마이크로서비스)로 전환합니다. 하지만 MSA는 분산 트랜잭션, 네트워크 지연, 배포 복잡성 등 엄청난 운영 비용을 요구합니다.

"아직 MSA로 갈 정도의 트래픽은 아니지만, 코드의 모듈화는 절실하다"라는 딜레마를 해결하기 위해, 최근 Spring 생태계에서 주목받고 있는 **Spring Modulith** 프로젝트와 **모듈러 모놀리스(Modular Monolith)** 아키텍처에 대해 학습했습니다.

---

### 1. **모듈러 모놀리스(Modular Monolith)란? 🧩**

하나의 배포 단위(JAR) 안에서, **논리적으로 모듈을 완벽하게 분리**하여 설계하는 아키텍처입니다.

-   **기존 모놀리스**: `com.example.service` 패키지 아래에 모든 서비스(`OrderService`, `MemberService`, `ProductService`)가 모여 있고, 서로가 서로를 자유롭게 참조합니다. (순환 참조의 지옥)
-   **모듈러 모놀리스**: 도메인 단위로 최상위 패키지를 분리합니다. (`com.example.order`, `com.example.member`). 그리고 **다른 모듈의 내부 구현체에는 접근할 수 없도록 강제**합니다.

---

### 2. **Spring Modulith로 의존성 검증하기**

Spring Modulith는 이러한 패키지 간의 의존성 규칙을 코드로 검증하고 강제할 수 있는 기능을 제공합니다.

#### **1. 의존성 추가 (`build.gradle`)**
```groovy
implementation 'org.springframework.modulith:spring-modulith-starter-core'
testImplementation 'org.springframework.modulith:spring-modulith-starter-test'
```

#### **2. 패키지 구조 정의**
Spring Modulith는 `@SpringBootApplication`이 있는 패키지의 **직계 하위 패키지**를 하나의 '모듈'로 인식합니다.

```text
src/main/java/com/acme/
  └─ MyApplication.java
  └─ inventory/           <-- 'Inventory' 모듈
      └─ InventoryService.java (public)
      └─ InternalHelper.java (package-private)
  └─ order/               <-- 'Order' 모듈
      └─ OrderService.java
```

#### **3. 아키텍처 검증 테스트**
개발자가 실수로 `Order` 모듈에서 `Inventory` 모듈의 내부 클래스를 참조하거나, 순환 참조를 만들면 테스트가 실패하게 만듭니다.

```java
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

class ModulithArchitectureTest {

    @Test
    void verifyModularity() {
        // 전체 모듈 구조를 분석하고 규칙 위반 시 예외 발생
        ApplicationModules modules = ApplicationModules.of(MyApplication.class);
        modules.verify(); 
    }
    
    @Test
    void createModuleDocumentation() {
        // 모듈 간의 의존성 관계를 C4 다이어그램(PUML) 등으로 자동 문서화
        ApplicationModules modules = ApplicationModules.of(MyApplication.class);
        new Documenter(modules).writeDocumentation();
    }
}
```

---

### 3. **모듈 간 통신: 메서드 호출 vs 이벤트 발행**

모듈러 모놀리스의 핵심은 모듈 간의 **느슨한 결합(Loose Coupling)**입니다.

#### **❌ 나쁜 예: 다른 모듈의 서비스 직접 주입**
```java
package com.acme.order;

@Service
class OrderService {
    // Inventory 모듈을 직접 의존. 
    // InventoryService가 변경되면 OrderService도 영향받음 (강결합)
    private final InventoryService inventoryService; 
    
    public void placeOrder(Order order) {
        // ...
        inventoryService.decreaseStock(order.getProductId());
    }
}
```

#### **✅ 좋은 예: Spring Application Event 활용**
Spring Modulith는 모듈 간의 이벤트 발행/구독을 강력하게 지원합니다.

**1. Order 모듈 (이벤트 발행)**
```java
package com.acme.order;

@Service
@RequiredArgsConstructor
class OrderService {
    private final ApplicationEventPublisher events;

    @Transactional
    public void placeOrder(Order order) {
        // DB 저장 로직...
        
        // "주문이 완료되었다"는 사실만 전파
        events.publishEvent(new OrderPlacedEvent(order.getId()));
    }
}
```

**2. Inventory 모듈 (이벤트 구독)**
```java
package com.acme.inventory;

import org.springframework.modulith.events.ApplicationModuleListener;

@Service
class InventoryService {

    // @EventListener + @TransactionalEventListener + @Async 등을 결합한 애노테이션
    @ApplicationModuleListener 
    void on(OrderPlacedEvent event) {
        // 재고 차감 로직 수행
        decreaseStock(event.orderId());
    }
}
```
> **Spring Modulith의 강점**: 만약 이벤트 리스너(`Inventory`)에서 예외가 발생하면 어떻게 될까요? Spring Modulith는 **이벤트 발행 기록(Publication Log)**을 DB에 저장해두고, 실패한 이벤트를 자동으로 재시도하거나 관리할 수 있는 기능을 기본 제공합니다. (Eventual Consistency 지원)

---

## 💡 배운 점

1.  **아키텍처는 '비용'이다**: MSA는 훌륭하지만 '분산 시스템의 8가지 오류'를 감당해야 하는 비싼 아키텍처입니다. 모듈러 모놀리스는 **"단일 배포의 편의성"**과 **"모듈화된 유지보수성"**의 균형을 맞추는, 중소~중대규모 프로젝트에 가장 합리적인 선택지일 수 있음을 깨달았습니다.
2.  **접근 제어자(Access Modifier)의 재발견**: 자바의 `public`은 너무 관대했습니다. 모듈러 모놀리스에서는 모듈의 API(Interface)만 `public`으로 열고, 내부 구현체는 `package-private`(default)으로 숨겨 컴파일 타임에 의존성을 차단하는 것이 핵심 설계 원칙입니다.
3.  **문서화의 자동화**: `ApplicationModules`를 통해 코드를 기반으로 현재 아키텍처 다이어그램을 자동으로 생성할 수 있다는 점이 인상적이었습니다. 이는 "문서와 코드가 따로 노는" 고질적인 문제를 해결해 줍니다.

---

## 🔗 참고 자료

-   [Spring Modulith Reference Documentation](https://docs.spring.io/spring-modulith/reference/)
-   [Quick Start with Spring Modulith](https://spring.io/guides/gs/modulith/)
-   [Majestic Modular Monoliths (AxonIQ)](https://www.axoniq.io/blog/majestic-modular-monoliths)