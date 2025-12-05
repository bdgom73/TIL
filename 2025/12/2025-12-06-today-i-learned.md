---
title: "분산 시스템의 데이터 정합성: Transactional Outbox 패턴"
date: 2025-12-06
categories: [Architecture, MSA]
tags: [Transactional Outbox, Kafka, MSA, Distributed System, Data Consistency, Design Pattern, TIL]
excerpt: "MSA 환경에서 DB 업데이트와 메시지 발행(Kafka)을 원자적(Atomic)으로 처리하기 위한 'Transactional Outbox 패턴'을 학습합니다. Dual Write 문제의 원인을 분석하고, Outbox 테이블과 폴링(Polling) 또는 CDC(Debezium)를 활용한 해결 전략을 알아봅니다."
author_profile: true
---

# Today I Learned: 분산 시스템의 데이터 정합성: Transactional Outbox 패턴

## 📚 오늘 학습한 내용

마이크로서비스 환경에서 비즈니스 로직을 수행한 후, 다른 서비스에 이벤트를 전파하기 위해 Kafka와 같은 메시지 브로커를 사용하는 것은 일반적입니다. 하지만 **"DB 저장과 메시지 발행을 어떻게 하나의 트랜잭션으로 묶을 것인가?"**라는 문제는 생각보다 까다롭습니다.

단순히 `@Transactional` 안에 `kafkaTemplate.send()`를 넣는 것으로는 데이터 정합성을 보장할 수 없습니다. 오늘은 이 **이중 쓰기(Dual Write)** 문제를 해결하는 표준 패턴인 **Transactional Outbox 패턴**에 대해 학습했습니다.

---

### 1. **문제의 본질: 이중 쓰기(Dual Write)의 딜레마 💣**

대부분의 메시지 브로커는 DB와 트랜잭션을 공유(2PC, XA)하지 않습니다. 따라서 다음과 같은 시나리오에서 데이터 불일치가 발생합니다.

```java
@Transactional
public void placeOrder(Order order) {
    // 1. 주문 DB 저장 (Pending)
    orderRepository.save(order);
    
    // 2. 이벤트 발행 (네트워크 타임아웃 발생!)
    kafkaTemplate.send("order-topic", new OrderEvent(order));
}
```
-   **상황 A**: DB 트랜잭션은 커밋되었는데, Kafka 발행이 실패하면? -> **주문은 생성되었지만, 배송 서비스는 이를 모름 (데이터 누락).**
-   **상황 B**: (순서를 바꿔서) Kafka 발행은 성공했는데, DB 트랜잭션이 롤백되면? -> **주문은 취소되었는데, 배송 서비스는 물건을 보냄 (유령 데이터).**

---

### 2. **해결책: Transactional Outbox 패턴 📮**

이 패턴의 핵심은 **"메시지를 브로커에 직접 보내지 말고, 일단 DB에 저장하자"**입니다.

1.  비즈니스 로직을 수행할 때, 발행할 이벤트를 **같은 DB의 별도 테이블(Outbox)**에 저장합니다.
2.  RDBMS는 단일 트랜잭션을 보장하므로, 비즈니스 데이터와 Outbox 데이터는 **동시에 커밋되거나 동시에 롤백**됩니다 (원자성 보장).
3.  별도의 프로세스(Relay)가 Outbox 테이블을 읽어서 메시지 브로커에 발행합니다.
4.  발행이 성공하면 Outbox 테이블에서 해당 데이터를 삭제(또는 상태 변경)합니다.



[Image of Transactional Outbox Pattern Diagram]


---

### 3. **Spring Boot로 구현하기 (Polling Publisher 방식)**

가장 직관적인 **Polling Publisher** 방식을 구현해 봅니다.

#### **Step 1: Outbox 테이블 생성**
```sql
CREATE TABLE outbox (
    id UUID PRIMARY KEY,
    aggregate_type VARCHAR(255),
    aggregate_id VARCHAR(255),
    payload JSON, -- 이벤트 내용
    created_at TIMESTAMP,
    published BOOLEAN DEFAULT FALSE
);
```

#### **Step 2: 서비스 계층 (저장)**
Kafka를 직접 호출하는 대신, Outbox 엔티티를 저장합니다.

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final OutboxRepository outboxRepository;
    private final ObjectMapper objectMapper;

    @Transactional // 하나의 DB 트랜잭션
    public void createOrder(OrderRequest request) {
        // 1. 비즈니스 데이터 저장
        Order order = new Order(request);
        orderRepository.save(order);

        // 2. Outbox에 이벤트 저장 (아직 발행 안 함)
        OutboxEvent outbox = OutboxEvent.builder()
                .id(UUID.randomUUID())
                .aggregateType("ORDER")
                .aggregateId(order.getId().toString())
                .payload(objectMapper.writeValueAsString(new OrderCreatedEvent(order)))
                .createdAt(LocalDateTime.now())
                .published(false)
                .build();
        
        outboxRepository.save(outbox);
    }
}
```

#### **Step 3: 메시지 중계기 (Message Relay)**
스케줄러를 사용하여 주기적으로 Outbox 테이블을 조회하고 Kafka로 발행합니다.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxRelay {

    private final OutboxRepository outboxRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;

    // 1초마다 실행
    @Scheduled(fixedDelay = 1000)
    public void publishEvents() {
        // 1. 아직 발행되지 않은 이벤트 조회
        List<OutboxEvent> events = outboxRepository.findAllByPublishedFalse();

        for (OutboxEvent event : events) {
            try {
                // 2. Kafka로 실제 발행
                kafkaTemplate.send("order-events", event.getAggregateId(), event.getPayload())
                    .whenComplete((result, ex) -> {
                        if (ex == null) {
                            // 3. 성공 시 상태 변경 (또는 삭제)
                            event.setPublished(true);
                            outboxRepository.save(event);
                        }
                    });
            } catch (Exception e) {
                log.error("Failed to publish event: {}", event.getId(), e);
            }
        }
    }
}
```

---

### 4. **더 나아가기: CDC (Change Data Capture) 활용**

위의 Polling 방식은 구현이 쉽지만, DB에 지속적인 부하를 주고 실시간성이 약간 떨어질 수 있습니다. 더 발전된 형태는 **Debezium** 같은 CDC 도구를 사용하는 것입니다.

-   **Log Tailing**: Debezium이 MySQL의 `Binlog`를 실시간으로 감시합니다.
-   **자동 발행**: `outbox` 테이블에 데이터가 INSERT 되는 순간, Debezium이 이를 감지하여 Kafka Connect를 통해 Kafka 토픽으로 자동으로 쏘아줍니다.
-   **장점**: 애플리케이션 코드에서 스케줄러를 제거할 수 있고, DB 부하가 적으며 실시간성이 보장됩니다.

---

## 💡 배운 점

1.  **분산 트랜잭션은 피하는 게 상책이다**: 2PC(Two-Phase Commit) 같은 복잡한 분산 트랜잭션을 사용하는 것보다, Outbox 패턴을 통해 **'로컬 트랜잭션'**으로 문제를 단순화하는 것이 훨씬 효율적이고 확장성이 좋다는 것을 깨달았습니다.
2.  **최소 한 번 전달 (At-Least-Once Delivery)**: Outbox 패턴을 사용하면 메시지가 유실될 확률은 0%가 되지만, 메시지가 **중복 발행**될 가능성은 존재합니다. (Kafka 발행 후 DB 상태 업데이트 전에 서버가 죽는 경우). 따라서 컨슈머(Consumer) 측의 **멱등성(Idempotency)** 처리가 필수적임을 다시 한번 확인했습니다.
3.  **비동기의 본질**: "사용자에게 응답을 주는 것"과 "이벤트를 발행하는 것"을 시간적으로 분리함으로써, 시스템의 결합도를 낮추고 사용자 응답 속도를 높일 수 있는 아키텍처 패턴임을 이해했습니다.

---

## 🔗 참고 자료

-   [Microservices.io - Transactional Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)
-   [Debezium - Outbox Event Router](https://debezium.io/documentation/reference/transformations/outbox-event-router.html)
-   [The Outbox Pattern (InfoQ)](https://www.infoq.com/articles/outbox-pattern-microservices/)