---
title: "DDD 핵심 패턴: Aggregate와 Repository로 일관성 유지하기"
date: 2025-10-01
categories: [Architecture, DDD]
tags: [DDD, Domain Driven Design, Aggregate, Repository, JPA, System Design, TIL]
excerpt: "도메인 주도 설계(DDD)의 핵심 패턴인 Aggregate(애그리거트)가 어떻게 복잡한 비즈니스 규칙 속에서 데이터의 일관성을 보장하는지 학습합니다. Aggregate 단위로 객체의 영속성을 관리하는 Repository 패턴의 원칙과 JPA를 이용한 구현 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: DDD 핵심 패턴: Aggregate와 Repository로 일관성 유지하기

## 📚 오늘 학습한 내용

복잡한 비즈니스 로직을 다룰 때 가장 어려운 문제 중 하나는 **데이터의 일관성(Consistency)**을 유지하는 것입니다. 예를 들어, 온라인 쇼핑몰에서 주문 항목을 추가하면 주문의 총 금액도 함께 변경되어야 합니다. 이처럼 관련된 여러 객체의 상태가 하나의 비즈니스 규칙 아래에서 함께 변경되어야 할 때, **도메인 주도 설계(DDD)**의 **Aggregate(애그리거트)** 패턴은 매우 강력한 해법을 제시합니다. 오늘은 Aggregate와, 이 Aggregate의 영속성을 관리하는 **Repository** 패턴에 대해 학습했습니다.

---

### 1. **Aggregate(애그리거트)란 무엇인가?**

**Aggregate**는 관련된 여러 객체들을 하나의 단위로 묶은 클러스터입니다. 이 단위는 데이터 변경 시 **일관성을 보장하는 경계(Consistency Boundary)** 역할을 합니다. 즉, 하나의 Aggregate 내의 객체들은 함께 생성되고, 함께 변경되며, 함께 삭제됩니다.

-   **구성 요소**:
    -   **Aggregate Root (애그리거트 루트)**: Aggregate의 대표가 되는 하나의 엔티티(Entity). 이 루트는 Aggregate의 **유일한 진입점** 역할을 합니다. 외부에서는 오직 루트를 통해서만 Aggregate 내부의 다른 객체에 접근하고 상태를 변경할 수 있습니다.
    -   **내부 객체 (Internal Objects)**: 루트에 속한 다른 엔티티나 값 객체(Value Object).

-   **핵심 규칙**:
    1.  **루트를 통해서만 접근하라**: 외부 객체는 Aggregate Root만 참조할 수 있습니다. 내부 객체를 직접 참조해서는 안 됩니다.
    2.  **하나의 트랜잭션으로 처리하라**: Aggregate에 대한 모든 변경은 하나의 트랜잭션 내에서 원자적으로(Atomically) 이루어져야 합니다. 즉, Aggregate 전체가 저장되거나, 전체가 실패해야 합니다.

#### **예시: 주문(Order) Aggregate**
-   **Aggregate Root**: `Order`
-   **내부 객체**: `OrderLine`(주문 항목), `ShippingInfo`(배송 정보)



사용자가 주문에 상품을 추가하는 로직은 다음과 같이 Aggregate Root를 통해 이루어져야 합니다.

```java
@Entity
public class Order { // Aggregate Root
    
    @Id
    private Long id;
    
    @OneToMany(cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderLine> orderLines = new ArrayList<>();
    
    private Money totalAmount; // 주문 총액
    
    // 비즈니스 로직은 루트가 책임진다.
    public void addOrderLine(Product product, int quantity) {
        // 비즈니스 규칙(Invariant) 검증
        verifyNotYetShipped(); 
        
        this.orderLines.add(new OrderLine(product, quantity));
        calculateTotalAmount(); // 총 금액을 다시 계산하여 일관성을 유지한다.
    }
    
    private void calculateTotalAmount() {
        this.totalAmount = new Money(this.orderLines.stream()
                .mapToLong(line -> line.getPrice().getValue())
                .sum());
    }
    
    // ...
}
```
`addOrderLine` 메서드는 단순히 리스트에 항목을 추가하는 것을 넘어, 주문 상태를 검증하고 총 금액을 재계산하는 **비즈니스 규칙(Invariant)**을 강제합니다. 이렇게 함으로써 `Order` Aggregate는 항상 일관된 상태를 유지할 수 있습니다.

---

### 2. **Repository 패턴: Aggregate를 위한 영속성 관리자**

**Repository(리포지토리)**는 Aggregate를 영속성 계층(데이터베이스)에 저장하고 조회하는 역할을 담당하는 객체입니다. 도메인 계층(비즈니스 로직)과 데이터 인프라 계층을 분리하는 중요한 역할을 합니다.

-   **핵심 원칙**:
    1.  **Aggregate Root 하나당 Repository 하나**: `Order`에 대한 `OrderRepository`는 있지만, 내부 객체인 `OrderLine`에 대한 `OrderLineRepository`는 만들지 않습니다. 모든 영속성 관리는 Aggregate Root를 통해서만 이루어져야 합니다.
    2.  **Aggregate 단위로 조회 및 저장**: Repository는 항상 완전한 상태의 Aggregate를 반환해야 합니다. `orderRepository.findById()`는 `Order`와 그에 속한 모든 `OrderLine`을 포함한 완전한 객체를 반환해야 합니다. `orderRepository.save(order)`는 `order` Aggregate 내부의 모든 변경사항(새로운 `OrderLine`, 수정된 `OrderLine` 등)을 하나의 트랜잭션으로 저장해야 합니다.

#### **JPA를 이용한 Repository 구현**

**Spring Data JPA**는 이 Repository 패턴을 매우 자연스럽게 지원합니다.

```java
// OrderRepository는 Order Aggregate를 관리한다.
public interface OrderRepository extends JpaRepository<Order, Long> {
    
    // Spring Data JPA가 메서드 이름을 분석하여 쿼리를 자동으로 생성해준다.
    // 반환 타입은 항상 Aggregate Root인 Order다.
    Optional<Order> findById(Long id);
    
    // save 메서드는 Order Aggregate 전체의 변경사항을 저장한다.
    // Order가 새로운 OrderLine을 포함하고 있다면, OrderLine도 함께 저장된다. (cascade 설정 덕분)
    Order save(Order order);
}
```

서비스 계층에서는 이 Repository를 통해 도메인 로직을 수행합니다.

```java
@Service
@Transactional
public class OrderService {
    
    private final OrderRepository orderRepository;
    private final ProductRepository productRepository;
    
    public void addProductToOrder(Long orderId, Long productId, int quantity) {
        Order order = orderRepository.findById(orderId)
                .orElseThrow(() -> new OrderNotFoundException());
        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException());
        
        // 도메인 객체(Aggregate Root)에 메시지를 보내 일을 시킨다.
        order.addOrderLine(product, quantity);
        
        // save를 호출하지 않아도 @Transactional에 의해 변경 감지(Dirty Checking)되어
        // 트랜잭션 커밋 시점에 Aggregate의 모든 변경이 DB에 반영된다.
        // 명시적으로 save를 호출해도 동일하게 동작한다.
        // orderRepository.save(order);

    }
}
```

---

## 💡 배운 점

1.  **Aggregate는 일관성을 위한 '방어막'이다**: 복잡한 도메인일수록 여러 데이터 조각들이 얽혀서 변경됩니다. Aggregate는 이들을 하나의 캡슐로 묶고, 정해진 문(Aggregate Root)을 통해서만 출입하게 함으로써 데이터가 깨질 위험을 원천적으로 차단하는 강력한 방어막 역할을 한다는 것을 이해했습니다.
2.  **Repository는 Aggregate의 생명주기 관리자다**: Repository는 단순히 DB에 데이터를 넣고 빼는 DAO와는 다릅니다. Repository는 Aggregate가 '하나의 단위'라는 개념을 영속성 계층까지 확장시켜, Aggregate 전체가 함께 저장되고 조회되도록 보장하는 역할을 수행합니다.
3.  **JPA는 DDD를 위한 훌륭한 도구다**: Spring Data JPA의 `@OneToMany(cascade=ALL, orphanRemoval=true)` 설정과 `@Transactional`을 통한 변경 감지 기능은 Aggregate의 생명주기를 관리하는 DDD의 원칙과 아주 자연스럽게 맞아떨어진다는 것을 깨달았습니다. 기술을 잘 이해하고 사용하면 좋은 설계를 더 쉽게 구현할 수 있습니다.

---

## 🔗 참고 자료

-   [Domain-Driven Design (Martin Fowler)](https://martinfowler.com/tags/domain%20driven%20design.html)
-   [DDD - The Aggregate (Vaughn Vernon)](https://vaughnvernon.co/?p=838)
-   [Spring Data JPA - Reference Documentation](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/)