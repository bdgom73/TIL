---
title: "MSA 분산 트랜잭션의 해법: Saga Pattern과 보상 트랜잭션(Compensating Transaction) 구현 전략"
date: 2026-01-08
categories: [Architecture, MSA, Pattern]
tags: [Saga Pattern, Distributed Transaction, MSA, Choreography, Orchestration, Kafka, Spring Boot, TIL]
excerpt: "마이크로서비스 환경에서 데이터 정합성을 보장하기 위해 기존의 2PC(Two-Phase Commit) 대신 Saga 패턴을 도입합니다. 코레오그래피(Choreography)와 오케스트레이션(Orchestration) 방식의 장단점을 비교하고, 실패 시 데이터를 원상 복구하는 보상 트랜잭션의 구현 원리를 학습합니다."
author_profile: true
---

# Today I Learned: MSA 분산 트랜잭션의 해법: Saga Pattern과 보상 트랜잭션(Compensating Transaction) 구현 전략

## 📚 오늘 학습한 내용

서비스를 MSA로 분리하면서 가장 골치 아픈 문제는 **"주문 서비스와 재고 서비스의 데이터 정합성을 어떻게 맞출 것인가?"**였습니다. 단일 DB라면 `@Transactional` 하나로 해결되지만, DB가 분리된 환경에서는 불가능합니다.

전통적인 `XA/2PC(Two-Phase Commit)`는 성능 저하와 데드락 위험 때문에 MSA에서 지양됩니다. 대안으로 각 서비스의 로컬 트랜잭션을 순차적으로 실행하되, 실패 시 **거꾸로 실행하여 되돌리는(Undo)** 개념인 **Saga Pattern**을 학습하고 설계했습니다.

---

### 1. **Saga 패턴의 두 가지 방식 ⚖️**



#### **1) 코레오그래피 (Choreography-based)**
-   **방식**: 중앙 제어 없이 서비스끼리 이벤트를 주고받으며 다음 동작을 수행합니다. (마치 무용수들이 서로 합을 맞추듯)
-   **흐름**: `주문 생성` 이벤트 발행 -> `재고` 서비스가 구독 후 차감 -> `결제` 서비스가 구독 후 결제.
-   **장점**: 구성이 간단하고 서비스 간 결합도가 낮습니다.
-   **단점**: 프로세스가 복잡해지면 순환 의존이 생길 수 있고, 현재 비즈니스 상태가 어디쯤인지 추적하기 어렵습니다.

#### **2) 오케스트레이션 (Orchestration-based)**
-   **방식**: 중앙의 **Orchestrator(Manager)**가 각 서비스에 명령(Command)을 내리고 상태를 관리합니다. (지휘자가 지시하듯)
-   **흐름**: `주문 Saga`가 `재고`에 차감 요청 -> 성공 응답 받음 -> `결제`에 승인 요청 -> 실패 응답 받음 -> `재고`에 보상(롤백) 요청.
-   **장점**: 복잡한 프로세스 관리가 용이하고 트랜잭션 상태 추적이 명확합니다.
-   **단점**: 오케스트레이터 서비스에 로직이 집중될 수 있습니다.

> **결론**: 서비스가 3개 이상 엮이는 복잡한 주문 프로세스에는 **오케스트레이션** 방식이 적합하다고 판단했습니다.

---

### 2. **보상 트랜잭션(Compensating Transaction) 설계**

Saga의 핵심은 **"Rollback이 아니라 Compensate(상쇄)"** 한다는 점입니다. 이미 커밋된 DB 트랜잭션을 물리적으로 되돌릴 수는 없으므로, **반대되는 작업**을 수행하여 논리적으로 취소 상태를 만듭니다.

| 단계 | 정상 트랜잭션 (Action) | 보상 트랜잭션 (Compensating Action) |
| :--- | :--- | :--- |
| **재고** | `decreaseStock(ItemId, 1)` | `increaseStock(ItemId, 1)` |
| **결제** | `processPayment(User, Amount)` | `refundPayment(User, Amount)` |
| **주문** | `createOrder(Order)` | `cancelOrder(Order)` |

---

### 3. **Spring Boot로 간단한 Orchestrator 구현해보기**

별도의 프레임워크(Axon, Eventuate) 없이 Kafka와 상태 머신 개념을 활용해 간단한 오케스트레이터를 구성해 보았습니다.

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderSagaOrchestrator {

    private final KafkaTemplate<String, String> kafkaTemplate;

    // 주문 요청이 들어오면 Saga 시작
    public void startSaga(Order order) {
        // 1. 재고 차감 명령 전송
        kafkaTemplate.send("stock-commands", new StockCommand("DECREASE", order.getItemId()));
    }

    // 각 서비스의 처리 결과를 수신하는 리스너
    @KafkaListener(topics = "saga-replies")
    public void handleReply(String message) {
        SagaResult result = parse(message);

        if (result.isSuccess()) {
            switch (result.getService()) {
                case "STOCK" -> requestPayment(result.getOrderId()); // 재고 성공 -> 결제 요청
                case "PAYMENT" -> completeOrder(result.getOrderId()); // 결제 성공 -> 주문 완료
            }
        } else {
            // 실패 시 보상 트랜잭션 실행 (Compensate)
            log.error("Saga Failed at {}", result.getService());
            switch (result.getService()) {
                case "PAYMENT" -> rollbackStock(result.getOrderId()); // 결제 실패 -> 재고 복구
                case "STOCK" -> cancelOrder(result.getOrderId()); // 재고 실패 -> 주문 취소
            }
        }
    }

    private void rollbackStock(Long orderId) {
        // 보상 트랜잭션 명령: 재고 증가
        kafkaTemplate.send("stock-commands", new StockCommand("INCREASE", orderId));
    }
}
```

---

### 4. **주의사항: 멱등성(Idempotency) 보장 🛡️**

분산 환경에서 메시지는 **중복 전달**되거나, 타임아웃으로 인해 **재시도**가 발생할 수 있습니다.
-   만약 `increaseStock`(보상 트랜잭션) 명령이 네트워크 이슈로 2번 도착한다면? 재고가 2번 늘어나면 안 됩니다.
-   따라서 모든 트랜잭션 메시지는 **Unique ID(Request ID)**를 가져야 하며, 수신 측에서는 이를 기록해두고 **이미 처리된 ID는 무시**하는 멱등성 처리가 필수입니다.

---

## 💡 배운 점

1.  **ACID의 환상 깨기**: MSA에서는 강한 일관성(ACID)을 포기하고 **결과적 일관성(Eventual Consistency)**을 받아들여야 합니다. "결제 실패 시 재고가 복구되는 데 1초가 걸릴 수 있다"는 사실을 비즈니스적으로 허용하는 협의가 선행되어야 함을 배웠습니다.
2.  **복잡도와의 싸움**: Saga를 도입하니 로직보다 "실패 처리"와 "상태 관리" 코드가 더 많아졌습니다. 무조건적인 MSA 전환보다는, 트랜잭션이 중요한 도메인은 모듈러 모놀리스로 묶는 것이 나을 수도 있겠다는 인사이트를 얻었습니다.
3.  **로그 추적의 중요성**: 여러 서비스에 걸쳐 로직이 실행되므로, `TraceId` 하나로 전체 Saga 흐름을 볼 수 있는 분산 추적 환경(Zipkin 등)이 없으면 디버깅이 불가능에 가깝습니다.

---

## 🔗 참고 자료

-   [Microservices Patterns (Chris Richardson)](https://microservices.io/patterns/data/saga.html)
-   [Saga Pattern in Spring Boot (Baeldung)](https://www.baeldung.com/cs/saga-pattern-microservices)
-   [Uber Cadence / Temporal (Orchestration Engine)](https://temporal.io/)