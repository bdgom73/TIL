---
title: "Kafka Consumer의 에러 처리 전략: Retry와 Dead Letter Queue(DLQ)로 데이터 유실 막기"
date: 2025-12-17
categories: [Messaging, Kafka]
tags: [Kafka, Spring Kafka, Consumer, DLQ, Error Handling, Retry, TIL]
excerpt: "Kafka 컨슈머가 메시지 처리에 실패했을 때 무한 재시도나 데이터 유실을 방지하기 위한 전략을 학습합니다. Spring for Apache Kafka의 DefaultErrorHandler와 DeadLetterPublishingRecoverer를 조합하여 재시도 후 실패한 메시지를 DLQ(Dead Letter Queue)로 안전하게 격리하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Kafka Consumer의 에러 처리 전략: Retry와 Dead Letter Queue(DLQ)로 데이터 유실 막기

## 📚 오늘 학습한 내용

Kafka를 사용하는 MSA 환경에서 **"컨슈머가 비즈니스 로직 처리 중 DB 오류나 외부 API 장애로 예외를 던진다면?"**이라는 상황은 반드시 발생합니다. 이때 적절한 에러 처리 전략이 없다면 두 가지 심각한 문제가 생깁니다.

1.  **Block**: 컨슈머가 에러를 해결할 때까지 오프셋을 커밋하지 않고 무한히 재시도하여, 뒤따라오는 메시지들이 처리되지 못하고 밀리는 현상 (Lag 증가).
2.  **Skip (Data Loss)**: 에러를 잡아서 로그만 찍고 넘어가면, 중요한 주문 데이터가 유실됨.

오늘은 이 딜레마를 해결하기 위해 **Spring for Apache Kafka**가 제공하는 **재시도(Retry)** 메커니즘과 **DLQ(Dead Letter Queue)** 패턴을 적용하는 표준적인 방법을 학습했습니다.

---

### 1. **핵심 전략: Retry N회 -> DLQ 이동 🔄**

가장 안정적인 패턴은 다음과 같습니다.
1.  메시지 처리 실패 시, 일정 간격(Backoff)을 두고 **N번 재시도**합니다. (일시적인 네트워크 장애일 수 있으므로)
2.  N번 모두 실패하면, 해당 메시지를 **별도의 토픽(DLQ)**으로 발행하여 격리합니다.
3.  원래 토픽의 오프셋은 커밋하고, 다음 메시지를 처리합니다. (Blocking 방지)
4.  DLQ에 쌓인 메시지는 나중에 개발자가 원인을 분석하거나, 별도의 배치를 통해 재처리합니다.



---

### 2. **Spring Boot 설정 (`DefaultErrorHandler`)**

과거에는 `SeekToCurrentErrorHandler`를 썼지만, 최신 버전(Spring Boot 2.7+)에서는 **`DefaultErrorHandler`**로 통합되었습니다.

#### **Step 1: KafkaConfig 설정**

```java
@Configuration
@EnableKafka
@Slf4j
public class KafkaConsumerConfig {

    /**
     * 재시도 및 DLQ 처리를 담당하는 에러 핸들러 설정
     */
    @Bean
    public DefaultErrorHandler errorHandler(KafkaTemplate<Object, Object> template) {
        // 1. Recoverer: 재시도 횟수 초과 시 실행될 로직 (DLQ로 발행)
        // 기본적으로 "원본토픽명.DLT" 라는 토픽으로 메시지를 보냅니다.
        DeadLetterPublishingRecoverer recoverer = new DeadLetterPublishingRecoverer(template,
                (record, ex) -> {
                    log.error("Fail to process. Send to DLQ. Topic: {}, Offset: {}", record.topic(), record.offset());
                    return new TopicPartition(record.topic() + ".DLT", record.partition());
                });

        // 2. Backoff: 재시도 간격 설정 (1초 간격으로 3번 재시도)
        FixedBackOff backOff = new FixedBackOff(1000L, 3L);

        DefaultErrorHandler errorHandler = new DefaultErrorHandler(recoverer, backOff);

        // 3. (옵션) 특정 예외는 재시도 없이 바로 DLQ로 보냄
        // 예: JSON 파싱 에러는 다시 시도해도 무조건 실패하므로
        errorHandler.addNotRetryableExceptions(IllegalArgumentException.class);
        errorHandler.addNotRetryableExceptions(JsonParseException.class);

        return errorHandler;
    }
}
```

#### **Step 2: Consumer 적용**

별도의 설정 없이 `KafkaListenerContainerFactory`에 위에서 만든 `errorHandler`가 주입되어 있다면 자동으로 적용됩니다.

```java
@Component
@Slf4j
public class OrderConsumer {

    @KafkaListener(topics = "orders", groupId = "order-group")
    public void consume(String message) {
        log.info("Processing order: {}", message);

        if (message.contains("error")) {
            // 이 예외가 발생하면 -> 1초 간격 3회 재시도 -> 실패 시 orders.DLT 토픽으로 이동
            throw new RuntimeException("Temporary System Error"); 
        }
        
        if (message.contains("bad-request")) {
            // 이 예외는 설정에 의해 재시도 없이 즉시 DLQ로 이동
            throw new IllegalArgumentException("Invalid Order Data");
        }
    }
    
    // DLQ 토픽을 구독해서 처리하는 컨슈머 (선택 사항)
    // 보통은 알림을 보내거나 DB에 저장해두고 수동 처리함
    @KafkaListener(topics = "orders.DLT", groupId = "order-dlq-group")
    public void consumeDlq(String message) {
        log.error("Received from DLQ: {}", message);
        // 슬랙 알림 발송 or 'failed_orders' 테이블에 저장
    }
}
```

---

### 3. **Non-Blocking Retry 패턴 (고급) 🚀**

위의 `DefaultErrorHandler`는 재시도하는 동안 스레드가 대기(Blocking)하므로 처리량이 떨어질 수 있습니다. 재시도 횟수가 많거나 대기 시간이 길다면(예: 10분 뒤 재시도), **Non-Blocking Retry** 패턴을 고려해야 합니다.

-   **Main Topic**: `orders`
-   **Retry Topic**: `orders.RETRY-10s`, `orders.RETRY-1m`
-   **DLQ Topic**: `orders.DLQ`

메인 컨슈머는 실패 시 즉시 `RETRY` 토픽으로 메시지를 던지고 다음 메시지를 처리합니다. 별도의 컨슈머가 `RETRY` 토픽을 구독하다가 지연 시간 후에 재처리를 시도합니다. Spring Kafka는 `@RetryableTopic` 애노테이션으로 이를 쉽게 지원합니다.

```java
@RetryableTopic(
    attempts = "4",
    backoff = @Backoff(delay = 1000, multiplier = 2.0), // 1초, 2초, 4초... 지수 백오프
    autoCreateTopics = "false",
    topicSuffixingStrategy = TopicSuffixingStrategy.SUFFIX_WITH_INDEX_VALUE
)
@KafkaListener(topics = "orders", groupId = "order-group")
public void consumeWithNonBlockingRetry(String message) {
    // ...
}
```

---

## 💡 배운 점

1.  **메시지 유실 제로에 도전**: 단순히 `try-catch`로 에러를 로그만 찍고 넘어가던 습관을 버려야 합니다. DLQ는 시스템이 처리하지 못한 '부채'를 안전한 금고에 보관하는 것과 같으며, 이를 통해 데이터 정합성을 끝까지 책임질 수 있게 되었습니다.
2.  **재시도 할 것인가, 말 것인가**: 모든 에러가 재시도 대상은 아닙니다. `NullPointerException`이나 `ParsingException` 같은 코드 레벨의 버그나 잘못된 데이터는 백만 번 재시도해도 실패합니다. `NotRetryableException`을 명확히 구분하는 것이 리소스 낭비를 막는 핵심입니다.
3.  **Recoverer의 역할**: `DeadLetterPublishingRecoverer`가 단순히 토픽을 옮겨주는 역할뿐만 아니라, 헤더에 **원본 에러 메시지와 스택트레이스**를 추가해준다는 점을 알았습니다. 덕분에 DLQ 메시지만 분석해도 왜 실패했는지 추적하기가 매우 수월해집니다.

---

## 🔗 참고 자료

-   [Spring for Apache Kafka - Error Handling](https://docs.spring.io/spring-kafka/reference/kafka/annotation-error-handling.html)
-   [Dead Letter Queue in Kafka (Baeldung)](https://www.baeldung.com/spring-retry-kafka-consumer)
-   [Kafka Reliable Data Delivery](https://www.confluent.io/blog/error-handling-patterns-in-kafka/)