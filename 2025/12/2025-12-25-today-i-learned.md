---
title: "Spring Modulith: MSA가 부담스러울 때 선택하는 모듈러 모놀리스(Modular Monolith)"
date: 2025-12-25
categories: [Architecture, Spring]
tags: [Spring Modulith, Modular Monolith, DDD, Architecture, Refactoring, TIL]
excerpt: "무분별한 MSA 도입으로 인한 복잡성을 피하고, 단일 배포 단위 내에서 논리적인 모듈 경계를 강제하는 Spring Modulith를 학습합니다. 패키지 의존성 순환을 자동으로 감지하고 테스트하는 방법과, 모듈 간 결합을 느슨하게 유지하는 전략을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Modulith: MSA가 부담스러울 때 선택하는 모듈러 모놀리스(Modular Monolith)

## 📚 오늘 학습한 내용

서비스 초기부터 MSA(Microservices Architecture)를 도입했다가 분산 트랜잭션, 배포 복잡도, 네트워크 레이턴시 문제로 고생하는 경우를 많이 봤습니다. 반대로 모놀리식(Monolithic)으로 시작하면 시간이 지날수록 코드가 스파게티처럼 얽혀 유지보수가 불가능해집니다.

오늘은 이 두 극단의 장점을 취하여, **"배포는 하나로 하되, 내부 코드는 마치 별도의 서비스처럼 완벽하게 격리"**하는 **Spring Modulith** 프로젝트와 **모듈러 모놀리스** 아키텍처를 학습했습니다.

---

### 1. **Spring Modulith란? 🧩**

Spring Modulith는 Spring Boot 애플리케이션 내에서 논리적인 모듈(패키지) 경계를 명확히 하고, 이를 위반하는 의존성을 **테스트 단계에서 막아주는** 프레임워크입니다.

-   **기본 규칙**: 최상위 패키지 하위의 패키지들을 하나의 '모듈'로 간주합니다.
-   **제약 사항**:
    -   다른 모듈의 내부 클래스(Internal)에 접근할 수 없습니다.
    -   모듈 간의 순환 참조(Cyclic Dependency)는 허용되지 않습니다.
    -   오직 API로 노출된 클래스(public)만 다른 모듈에서 호출할 수 있습니다.

---

### 2. **프로젝트 적용 및 검증**

#### **Step 1: 의존성 추가**
Spring Boot 3.1 이상에서 사용할 수 있습니다.

```groovy
implementation 'org.springframework.modulith:spring-modulith-starter-core'
testImplementation 'org.springframework.modulith:spring-modulith-starter-test'
```

#### **Step 2: 패키지 구조 잡기**
`inventory` 모듈은 `order` 모듈의 내부 구현을 절대 알면 안 됩니다.

```text
com.example.shop
├── order           <-- [모듈 1]
│   ├── Order.java
│   ├── OrderService.java (public: 외부 노출)
│   └── internal    <-- (패키지: 외부에서 접근 불가)
│       └── OrderRepository.java
├── inventory       <-- [모듈 2]
│   ├── InventoryService.java
│   └── ...
└── ShopApplication.java
```

#### **Step 3: 아키텍처 검증 테스트**
ArchUnit을 기반으로 만들어진 `ApplicationModules`를 사용하면, 모듈 규칙 위반 시 **테스트가 실패**합니다.

```java
class ModularityTest {

    @Test
    void verifyModularity() {
        // 프로젝트의 모듈 구조를 분석하고 규칙 위반 여부 검증
        ApplicationModules modules = ApplicationModules.of(ShopApplication.class);
        
        // 순환 참조가 있거나, 허용되지 않은 내부 패키지에 접근하면 예외 발생
        modules.verify(); 
    }
    
    @Test
    void writeDocumentation() {
        // 현재 모듈 구조를 C4 다이어그램(PlantUML)으로 자동 생성
        ApplicationModules.of(ShopApplication.class).createImage();
    }
}
```

---

### 3. **모듈 간 통신: Event Externalization**

모듈 간에 메서드를 직접 호출(`orderService.create()`)하면 강결합이 발생합니다. Spring Modulith는 모듈 간 통신을 **이벤트**로 처리하도록 권장하며, 이를 위한 강력한 기능을 제공합니다.

**시나리오**: 주문 완료(Order) -> 재고 차감(Inventory)

1.  **Order 모듈**: `OrderCompletedEvent` 발행 (ApplicationEventPublisher).
2.  **Inventory 모듈**: `@ApplicationModuleListener`로 이벤트 수신.

```java
@Service
public class InventoryService {

    // @Async + @TransactionalEventListener를 합친 Modulith 전용 애노테이션
    @ApplicationModuleListener 
    public void on(OrderCompletedEvent event) {
        // 재고 차감 로직 수행
        inventoryRepository.decrease(event.getProductId());
    }
}
```

**Moments (Event Registry)**
만약 재고 차감 중 에러가 나면? Spring Modulith는 이벤트를 DB(H2, MySQL 등)에 잠깐 저장해두는 **Event Registry** 기능을 제공합니다. 트랜잭션이 커밋되면 이벤트를 발행하고, 실패하면 발행하지 않거나 재시도할 수 있게 하여 **모듈 간의 데이터 정합성**을 보장합니다.

```yaml
spring:
  modulith:
    events:
      jdbc-schema-initialization:
        enabled: true # DB에 이벤트 발행 기록 테이블 자동 생성
```

---

### 4. **왜 모듈러 모놀리스인가?**

-   **리팩토링의 안전망**: 나중에 트래픽이 터져서 `Order` 모듈만 따로 MSA로 떼어내야 할 때, 이미 모듈 간 경계가 완벽하게 분리되어 있으므로 **"복사-붙여넣기"** 수준으로 분리가 가능합니다.
-   **생산성**: IDE의 리팩토링 기능, 디버깅, 단일 배포 파이프라인의 이점을 그대로 누리면서도 스파게티 코드를 방지할 수 있습니다.
-   **인지 부하 감소**: 개발자는 자신이 맡은 모듈(`inventory`) 내부만 신경 쓰면 되고, 다른 모듈은 공개된 API(인터페이스)만 알면 됩니다.

---

## 💡 배운 점

1.  **구조적인 강제성**: "코드 리뷰 때 잘 확인하자"는 약속은 결국 깨지기 마련입니다. Spring Modulith는 `mvn test` 단계에서 아키텍처 위반을 잡아내므로, 시스템의 엔트로피가 증가하는 것을 물리적으로 차단해준다는 점이 인상 깊었습니다.
2.  **문서화의 자동화**: `ApplicationModules.createImage()`를 실행하면 현재 모듈 간의 의존 관계를 **UML 다이어그램**으로 그려줍니다. 항상 최신 상태의 아키텍처 문서를 유지할 수 있는 킬러 기능입니다.
3.  **MSA의 전 단계**: 처음부터 MSA로 시작하는 것보다, 잘 짜인 모듈러 모놀리스로 시작하고 필요할 때 찢는 것이 성공 확률이 훨씬 높은 전략임을 확신하게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Modulith Reference Documentation](https://docs.spring.io/spring-modulith/reference/)
-   [Quick Guide to Spring Modulith](https://www.baeldung.com/spring-modulith)
-   [Modular Monolith: A Primer (Kamil Grzybek)](https://kamilgrzybek.com/design/modular-monolith-primer/)