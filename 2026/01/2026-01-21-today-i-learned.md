---
title: "메시지 발행의 원자성 보장: Transactional Outbox Pattern으로 'Dual Write' 문제 해결하기"
date: 2026-01-21
categories: [Architecture, MSA, Kafka]
tags: [Transactional Outbox, Dual Write, Kafka, MSA, Consistency, CDC, TIL]
excerpt: "DB 저장과 메시지 큐(Kafka) 발행을 동시에 수행할 때 발생하는 '이중 쓰기(Dual Write)' 문제의 위험성을 분석합니다. DB 트랜잭션과 메시지 발행의 원자성을 보장하기 위해 Outbox 테이블을 활용하는 패턴을 학습하고, Polling Publisher 방식을 구현하여 데이터 유실 없는 이벤트 발행 시스템을 구축합니다."
author_profile: true
---

# Today I Learned: 메시지 발행의 원자성 보장: Transactional Outbox Pattern으로 'Dual Write' 문제 해결하기

## 📚 오늘 학습한 내용

주문이 발생하면(DB 저장) 배송 서비스로 이벤트를 발행(Kafka Send)하는 로직을 개발했습니다. 그런데 **"DB에는 저장이 됐는데, 네트워크 불안정으로 카프카 발행이 실패하면 어떡하지?"** 혹은 **"카프카는 보냈는데, 정작 DB 커밋이 롤백되면 어떡하지?"**라는 **Dual Write(이중 쓰기)** 딜레마에 빠졌습니다.

DB 트랜잭션과 메시지 발행은 서로 다른 리소스라 묶을 수 없기 때문입니다. 오늘은 이를 해결하기 위한 업계 표준 패턴인 **Transactional Outbox Pattern**을 학습하고 구현했습니다.

---

### 1. **Dual Write 문제란? 💥**

```java
@Transactional
public void createOrder(Order order) {
    // 1. DB 저장 (성공)
    orderRepository.save(order);
    
    // 2. Kafka 발행 (여기서 네트워크 에러가 나면?)
    // 결과: DB에는 주문이 있는데, 배송팀은 주문이 들어온 줄 모름 -> 정합성 깨짐
    kafkaProducer.send("order-topic", order);
}
```

반대로 Kafka를 먼저 보내고 DB를 저장해도, DB 저장이 실패하면 '없는 주문'에 대한 배송 요청이 나가게 됩니다.

---

### 2. **해결책: Transactional Outbox Pattern 📮**

핵심 아이디어는 **"메시지 발행도 DB 쓰기로 취급하자"**입니다.
이벤트 내용을 카프카로 바로 보내지 않고, **같은 트랜잭션 범위 안에서 DB의 `OUTBOX` 테이블에 저장**합니다.

1.  **Local Transaction**: `주문 테이블 INSERT` + `Outbox 테이블 INSERT` (원자성 보장됨).
2.  **Async Publisher**: 별도의 프로세스(Poller 또는 CDC)가 `Outbox` 테이블을 읽어서 Kafka로 발행.
3.  **Delete/Update**: 발행 성공 시 `Outbox` 데이터 삭제 또는 상태 변경.



---

### 3. **구현: Polling Publisher 방식**

CDC(Debezium)를 도입하면 좋지만 인프라 비용이 크므로, Spring Batch나 Scheduler를 이용한 **Polling** 방식으로 구현했습니다.

#### **Step 1: Outbox 엔티티 정의**

```java
@Entity
@Getter
@NoArgsConstructor
public class OutboxEvent {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String aggregateType; // 예: ORDER
    private Long aggregateId;     // 예: orderId
    private String type;          // 예: ORDER_CREATED
    
    @Lob
    private String payload;       // JSON 데이터
    
    private boolean published;    // 발행 여부
    private LocalDateTime createdAt;
}
```

#### **Step 2: 서비스 로직 수정**

이제 Kafka를 직접 호출하지 않고, Outbox에 저장만 합니다. DB 트랜잭션 내부이므로 **둘 다 성공하거나, 둘 다 실패합니다.**

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final OutboxRepository outboxRepository;
    private final ObjectMapper objectMapper;

    @Transactional
    public void createOrder(OrderDto dto) {
        // 1. 비즈니스 데이터 저장
        Order order = orderRepository.save(dto.toEntity());

        // 2. Outbox 저장 (Kafka 발행 대신)
        OutboxEvent event = new OutboxEvent(
            "ORDER", 
            order.getId(), 
            "ORDER_CREATED", 
            objectMapper.writeValueAsString(order)
        );
        outboxRepository.save(event);
    }
}
```

#### **Step 3: Message Relay (스케줄러)**

주기적으로 Outbox 테이블을 뒤져서 발행되지 않은 이벤트를 Kafka로 쏘는 역할을 합니다.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class MessageRelayScheduler {

    private final OutboxRepository outboxRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;

    // 1초마다 실행 (ShedLock 필수 적용 권장)
    @Scheduled(fixedDelay = 1000)
    public void publishEvents() {
        // 1. 발행되지 않은 이벤트 조회
        List<OutboxEvent> events = outboxRepository.findByPublishedFalse();

        for (OutboxEvent event : events) {
            try {
                // 2. 실제 Kafka 발행
                kafkaTemplate.send("order-topic", event.getPayload()).get();
                
                // 3. 발행 완료 처리 (삭제하거나 상태 변경)
                // outboxRepository.delete(event); // 또는
                event.changePublished(true);
                outboxRepository.save(event);
                
            } catch (Exception e) {
                log.error("메시지 발행 실패 ID: {}", event.getId(), e);
                // 재시도 로직이나 Dead Letter Queue 처리 필요
            }
        }
    }
}
```

---

### 4. **고려사항 및 한계 🤔**

1.  **메시지 순서 보장**: Polling 방식은 멀티 스레드로 돌릴 경우 순서가 꼬일 수 있습니다. 순서가 중요하다면 단일 스레드로 처리하거나, Kafka 파티션 키를 잘 설계해야 합니다.
2.  **최소 한 번 전송 (At-least-once)**: 발행 후 `published=true`로 업데이트하기 직전에 서버가 죽으면, 재시작 후 **같은 메시지가 다시 발행**될 수 있습니다. 따라서 **컨슈머(Consumer) 쪽에서 멱등성(Idempotency) 처리**가 반드시 동반되어야 합니다.
3.  **DB 부하**: Polling 쿼리가 DB에 부하를 줄 수 있습니다. 데이터가 많다면 처리된 Outbox 데이터는 바로바로 지우거나(Hard Delete), 파티셔닝 테이블로 관리해야 합니다.

---

## 💡 배운 점

1.  **정합성의 비용**: 단순히 `kafka.send()` 한 줄이면 될 것을 테이블 만들고 스케줄러 돌리는 과정이 번거로워 보였지만, **"데이터 유실 0%"**를 보장하기 위해 치러야 할 필수적인 비용임을 깨달았습니다.
2.  **비동기의 미학**: 사용자 응답 시간에는 Kafka 발행 시간(네트워크 I/O)이 포함되지 않고 오직 DB Insert 시간만 포함되므로, API 응답 속도가 더 빨라지는 부수적인 장점도 발견했습니다.
3.  **CDC의 필요성**: Polling 방식은 실시간성(Latency)이 스케줄 주기만큼 늦어집니다. 더 리얼타임 처리가 필요하다면 **Debezium** 같은 CDC 도구를 이용해 DB 바이너리 로그(Binlog)를 털어서 Kafka로 보내는 방식으로 고도화해야겠습니다.

---

## 🔗 참고 자료

-   [Microservices.io - Transactional Outbox](https://microservices.io/patterns/data/transactional-outbox.html)
-   [The Outbox Pattern (Debezium)](https://debezium.io/blog/2019/02/19/reliable-microservices-data-exchange-with-the-outbox-pattern/)
-   [Spring Cloud Stream with Outbox](https://docs.spring.io/spring-cloud-stream/docs/current/reference/html/spring-cloud-stream.html#_outbox_pattern)