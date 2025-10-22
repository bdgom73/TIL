---
title: "Apache Kafka 핵심 동작 원리: Topic, Partition, Consumer Group"
date: 2025-10-22
categories: [Architecture, Kafka]
tags: [Kafka, Topic, Partition, Consumer Group, Spring Kafka, MSA, TIL]
excerpt: "대용량 스트리밍 데이터를 처리하는 표준인 Apache Kafka의 핵심 동작 원리를 학습합니다. Kafka가 어떻게 높은 처리량과 확장성을 달성하는지 Topic, Partition, Offset, 그리고 Consumer Group의 관계를 통해 알아봅니다."
author_profile: true
---

# Today I Learned: Apache Kafka 핵심 동작 원리: Topic, Partition, Consumer Group

## 📚 오늘 학습한 내용

MSA 환경에서 서비스 간의 비동기 통신을 위해 Kafka를 사용해왔지만, RabbitMQ와 같은 단순한 메시지 큐(Message Queue)와 Kafka가 근본적으로 어떻게 다른지, '이벤트 스트리밍 플랫폼'이라는 이름이 붙은 이유가 무엇인지 항상 궁금했습니다.

오늘은 Kafka의 단순한 사용법을 넘어, Kafka가 어떻게 대용량 데이터를 빠르고 안정적으로 처리하는지 그 내부 아키텍처, 특히 **Topic, Partition, Consumer Group**의 관계에 대해 깊이 있게 학습했습니다.

---

### 1. **Kafka는 '큐'가 아닌 '분산 로그'다 📜**

가장 큰 오해는 Kafka를 큐로 생각하는 것이었습니다.
-   **전통적인 큐 (e.g., RabbitMQ)**: Consumer가 메시지를 읽어가면, 큐에서 메시지가 **삭제**됩니다.
-   **Kafka (분산 로그)**: Consumer가 메시지를 읽어가도, 데이터가 **삭제되지 않습니다.** 데이터는 정해진 보존 기간(Retention Period) 동안 파일 시스템에 그대로 저장됩니다.

Kafka는 **추가만 가능한(Append-only), 불변의(Immutable) 로그**들의 집합입니다. Consumer는 단지 로그의 특정 위치(Offset)를 '읽고' 자신의 위치를 '기억'할 뿐입니다. 이 덕분에 여러 Consumer가 각기 다른 위치에서 동일한 데이터를 여러 번 읽어갈 수 있습니다.

---

### 2. **Kafka의 핵심 구성 요소**

#### **① Topic, Partition, Offset: 데이터의 저장 구조**

-   **Topic (토픽)**
    -   데이터를 구분하기 위한 카테고리 또는 피드 이름입니다. (e.g., `user-signup`, `order-created`)
-   **Partition (파티션)**
    -   **Kafka 확장성의 핵심입니다.** 하나의 Topic은 여러 개의 파티션으로 나뉘어 분산 저장됩니다.
    -   각 파티션은 하나의 독립적인 로그 파일이며, 데이터가 저장되는 실제 물리적 단위입니다.
    -   **순서 보장**: Kafka는 **파티션 내에서만** 데이터의 순서를 보장합니다.
-   **Offset (오프셋)**
    -   파티션 내에서 각 메시지가 가지는 **순차적인 ID(번호)**입니다.
    -   Consumer는 이 Offset을 기준으로 자신이 어디까지 데이터를 읽었는지 Kafka 브로커에 기록(Commit)합니다.



#### **② Producer와 Key**
-   **Producer (생산자)**: Topic으로 메시지를 전송하는 주체입니다.
-   **메시지 분배 (Routing)**:
    -   **Key가 없는 경우**: Producer는 메시지를 각 파티션에 **라운드 로빈(Round-Robin)** 방식으로 분배하여 균등하게 저장합니다.
    -   **Key가 있는 경우 (매우 중요!)**: Producer는 메시지의 **Key를 해시(Hash)하여 특정 파티션을 결정**합니다.
    -   **결과**: **동일한 Key를 가진 메시지들은 항상 동일한 파티션에 저장됩니다.** (e.g., `userId`를 Key로 사용하면, 특정 사용자의 모든 이벤트는 항상 같은 파티션에 순서대로 저장됩니다.)

#### **③ Consumer Group과 확장성 (Scalability)**
-   **Consumer Group (컨슈머 그룹)**
    -   **Kafka 확장성의 두 번째 핵심입니다.**
    -   하나의 Topic을 구독하는 여러 Consumer들의 묶음입니다. (e.g., `my-order-service`라는 이름의 그룹)
    -   **핵심 규칙**: **하나의 파티션은 컨슈머 그룹 내에서 오직 하나의 컨슈머에 의해서만 소비될 수 있습니다.**
-   **동작 방식 (Rebalancing)**:
    -   `my-topic`이 4개의 파티션(P0, P1, P2, P3)을 가지고 있다고 가정해봅시다.
    -   **Case 1 (컨슈머 1개)**: 컨슈머 1이 P0, P1, P2, P3을 모두 구독합니다.
    -   **Case 2 (컨슈머 2개)**: Kafka가 **리밸런싱(Rebalancing)**을 수행합니다. 컨슈머 1이 P0, P1을, 컨슈머 2가 P2, P3을 나눠서 처리합니다. (처리량 2배)
    -   **Case 3 (컨슈머 4개)**: 컨슈머 1(P0), 2(P1), 3(P2), 4(P3)가 각각 하나의 파티션을 맡아 **최대의 병렬성**으로 처리합니다. (처리량 4배)
    -   **Case 4 (컨슈머 5개)**: 컨슈머 5는 할당받을 파티션이 없으므로 **아무 일도 하지 않고 대기**합니다.

---

### 3. **Spring Kafka에서는 어떻게 동작하는가?**

Spring Boot에서 Kafka를 사용하는 것은 놀랍도록 간단합니다.

**application.yml (Consumer 설정)**
```yaml
spring:
  kafka:
    consumer:
      bootstrap-servers: localhost:9092
      # 이 컨슈머가 속할 그룹 ID 정의
      group-id: my-order-service-group
      auto-offset-reset: earliest # 읽을 오프셋이 없을 때 가장 처음부터 읽음
```

**Kafka Consumer (Listener) 구현**
```java
@Service
public class OrderConsumer {

    @KafkaListener(topics = "order-created", groupId = "my-order-service-group")
    public void handleOrderCreated(String message) {
        System.out.println("Received order message: " + message);
        // ... 주문 처리 비즈니스 로직 ...
    }
}
```
> 만약 이 애플리케이션을 3대로 확장(Scale-out)하여 실행하면, 3개의 `OrderConsumer` 인스턴스는 자동으로 `my-order-service-group`이라는 **하나의 컨슈머 그룹**에 속하게 됩니다. Kafka는 Topic의 파티션들을 이 3개의 인스턴스에 자동으로 재분배하여 병렬 처리합니다.

---

## 💡 배운 점

1.  **Kafka는 '로그'다, 큐가 아니다**: 데이터가 읽어도 삭제되지 않는다는 점이 가장 큰 충격이었습니다. 이 덕분에 장애가 발생한 컨슈머가 복구된 후, 마지막으로 커밋한 Offset부터 다시 데이터를 읽어올 수 있어(Exactly-once, At-least-once) 데이터 유실 없는 안정적인 처리가 가능해집니다.
2.  **확장성(Scalability)은 '파티션'이 결정한다**: 컨슈머의 병렬 처리 수준은 전적으로 **토픽의 파티션 수에 의해 제한**됩니다. 컨슈머 인스턴스를 100대로 늘려도 파티션이 4개뿐이라면 4대만 일하고 96대는 놀게 됩니다. 처음 토픽을 설계할 때 예상 처리량에 맞춰 파티션 수를 잘 정하는 것이 매우 중요하다는 것을 깨달았습니다.
3.  **순서 보장은 'Key'로 하는 것이다**: 전체 토픽에 대한 순서 보장은 불가능하며, '파티션 내'에서만 순서가 보장된다는 점을 이해했습니다. 따라서 "사용자별 주문 순서"처럼 특정 단위의 순서 보장이 필요하다면, 반드시 '사용자 ID'를 **메시지 Key로** 지정하여 동일한 파티션에 저장되도록 유도해야 합니다.

---

## 🔗 참고 자료

-   [Apache Kafka 공식 문서 - Introduction](https://kafka.apache.org/introduction)
-   [Kafka: The Definitive Guide (Book)](https://www.oreilly.com/library/view/kafka-the-definitive/9781491936153/)
-   [Spring for Apache Kafka - Reference](https://docs.spring.io/spring-kafka/reference/html/)