---
title: "Spring Kafka: Dead Letter Topic (DLT)으로 안전한 메시지 에러 처리하기"
date: 2025-11-07
categories: [Architecture, Kafka]
tags: [Kafka, Spring Kafka, Error Handling, DLQ, DLT, MSA, Resilience, TIL]
excerpt: "Kafka Consumer에서 메시지 처리 실패 시 발생하는 무한 재시도와 파티션 블로킹 문제를 학습합니다. Spring Boot 3의 CommonErrorHandler와 DLT(Dead Letter Topic) 기능을 사용해 실패한 메시지를 격리하고 시스템의 회복탄력성을 높이는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Kafka: Dead Letter Topic (DLT)으로 안전한 메시지 에러 처리하기

## 📚 오늘 학습한 내용

저는 3~4년차 개발자로서 MSA 환경에서 Kafka를 사용해왔습니다. `@KafkaListener`로 메시지를 받는 것은 익숙하지만, 만약 리스너의 **비즈니스 로직 수행 중 예외(Exception)가 발생하면** 어떻게 될까요?

-   **문제점**: DB 장애나 `NullPointerException` 등으로 로직이 실패하면, Spring Kafka는 기본적으로 해당 메시지를 **계속해서 재시도**합니다. 재시도가 계속 실패하면 Consumer는 해당 메시지의 오프셋(Offset)을 커밋하지 못하고, 그 뒤에 있는 모든 메시지들이 처리되지 못하는 **파티션 블로킹(Partition Blocking)** 상태에 빠집니다. 이는 시스템 전체의 데이터 흐름을 멈추게 하는 심각한 장애입니다.

오늘은 이 문제를 해결하기 위해, 실패한 메시지를 **"죽은 메시지"**로 간주하고 별도의 토픽으로 격리하는 **DLT(Dead Letter Topic)** 전략에 대해 학습했습니다.

---

### 1. **DLT(Dead Letter Topic)란 무엇인가? 묘지**

**DLT**는 "죽은 편지 토픽"이라는 뜻으로, Consumer가 여러 번의 재시도에도 불구하고 최종적으로 처리에 실패한 메시지들을 보내는 **'묘지' 또는 '격리소'** 같은 토픽입니다.

-   **핵심 아이디어**:
    1.  문제가 있는 메시지 하나 때문에 전체 파티션의 처리가 멈춰서는 안 됩니다.
    2.  일단 실패한 메시지는 별도의 DLT(e.g., `order-created.DLT`)로 치워둡니다.
    3.  원본 토픽의 오프셋은 정상적으로 커밋하여, 다음 메시지 처리를 계속 진행합니다.
    4.  개발자는 나중에 DLT에 쌓인 메시지들을 확인하여, 원인을 분석하고 수동으로 복구할 기회를 가집니다.

---

### 2. **Spring Boot 3의 `CommonErrorHandler`로 DLT 구현하기**

과거에는 `SeekToCurrentErrorHandler`나 `DefaultErrorHandler` 빈을 복잡하게 설정해야 했지만, Spring Boot 3 (Spring Kafka 3.x)부터는 `application.yml` 설정만으로 DLT를 매우 쉽게 구성할 수 있습니다.

#### **1. `application.yml` 설정**
`spring.kafka.listener.common-error-handler` 설정을 통해 DLT를 활성화합니다.

```yaml
spring:
  kafka:
    listener:
      # (중요) CommonErrorHandler를 사용하도록 설정
      # START, CONTAINER, BATCH 등이 있으며, 레코드(메시지) 단위 처리를 위해 START/CONTAINER 사용
      type: START 
      common-error-handler:
        # DLT 기능을 활성화합니다.
        dlt-enabled: true
        
        # DLT로 보낼 토픽 이름을 지정합니다.
        # 지정하지 않으면 {원본토픽}.DLT 라는 이름으로 자동 생성됩니다.
        dlt-topic-name: "dead-letter-topic-general"
        
        # 재시도 횟수를 지정합니다. (e.g., 총 3번 시도 = 최초 1번 + 재시도 2번)
        retry-max-attempts: 3
        
        # 재시도 간의 간격 (Backoff)
        retry-back-off-ms: 1000 # 1초 간격으로 재시도
```

#### **2. `@KafkaListener` 구현**
리스너 코드는 특별히 변경할 필요가 없습니다. 로직 수행 중 문제가 발생하면 **그냥 예외를 던지기만** 하면 됩니다.

```java
@Service
@Slf4j
public class OrderConsumer {

    /**
     * DLT 설정은 YML에 의해 전역적으로 적용됩니다.
     */
    @KafkaListener(topics = "order-created", groupId = "order-processing-group")
    public void handleOrderCreated(OrderRequest orderRequest) {
        log.info("Processing order: {}", orderRequest.getOrderId());
        
        try {
            // ... 비즈니스 로직 수행 ...
            if (orderRequest.getOrderId() % 2 == 0) {
                // 짝수 ID는 강제로 예외 발생 시뮬레이션
                throw new RuntimeException("Simulated processing error for order: " 
                                           + orderRequest.getOrderId());
            }
            log.info("Successfully processed order: {}", orderRequest.getOrderId());
            
        } catch (Exception e) {
            log.error("Failed to process order: {}", e.getMessage());
            // 예외를 밖으로 다시 던져야 CommonErrorHandler가 인지할 수 있습니다.
            throw e; 
        }
    }
}
```

#### **3. DLT Consumer 구현 (선택 사항)**
DLT에 쌓인 메시지를 모니터링하거나 관리하기 위한 별도의 리스너를 만들 수 있습니다. (보통 별도의 어드민 애플리케이션에서 관리)

```java
@Service
@Slf4j
public class DeadLetterTopicConsumer {

    /**
     * DLT 토픽을 구독하는 리스너
     */
    @KafkaListener(topics = "dead-letter-topic-general", groupId = "dlt-admin-group")
    public void handleDeadLetter(String message,
                                 @Header(KafkaHeaders.EXCEPTION_MESSAGE) String exceptionMessage,
                                 @Header(KafkaHeaders.ORIGINAL_TOPIC) String originalTopic) {
        
        log.error("!!! Dead Letter Received !!!");
        log.error("Original Topic: {}", originalTopic);
        log.error("Exception: {}", exceptionMessage);
        log.error("Payload: {}", message);
        
        // TODO: Slack 알림 전송, DB에 에러 로그 저장 등
    }
}
```
> Spring Kafka는 DLT로 메시지를 보낼 때, `EXCEPTION_MESSAGE`, `ORIGINAL_TOPIC` 등 유용한 정보들을 헤더에 자동으로 추가해줍니다.

---

## 💡 배운 점

1.  **컨슈머의 장애는 '예상된 시나리오'다**: 3~4년차 개발자로서, 더 이상 "해피 케이스(Happy Path)"만 생각하고 코드를 짜면 안 된다는 것을 깨달았습니다. DB가 다운되거나, 외부 API가 타임아웃되는 등, 컨슈머 로직은 **언제든 실패할 수 있다**는 전제 하에 설계해야 합니다.
2.  **파티션 블로킹은 최악의 장애다**: 메시지 하나가 잘못되어 전체 시스템의 데이터 파이프라인이 막히는 것은 서비스에 치명적입니다. DLT는 **실패를 격리**함으로써, 문제가 있는 데이터를 포기하는 대신 **전체 시스템의 가용성**을 선택하는 성숙한 장애 처리 전략입니다.
3.  **Spring이 복잡함을 숨겨준다**: 과거에는 `RetryTemplate`이나 `try-catch`로 복잡한 재시도 로직을 직접 구현해야 했습니다. Spring Boot 3의 `CommonErrorHandler`는 이 모든 과정을 추상화하고, YML 설정 몇 줄로 강력한 재시도 및 DLT 정책을 적용할 수 있게 해준다는 점에서 프레임워크의 강력함을 다시 한번 느꼈습니다.

---

## 🔗 참고 자료

-   [Spring Kafka Docs - Error Handling and DLT](https://docs.spring.io/spring-kafka/reference/html/#error-handling)
-   [Spring Kafka - CommonErrorHandler (Baeldung)](https://www.baeldung.com/spring-kafka-commonerrorhandler)
-   [Kafka Dead Letter Queue (Confluent Blog)](https://www.confluent.io/blog/kafka-connect-deep-dive-error-handling-and-dead-letter-queues/)