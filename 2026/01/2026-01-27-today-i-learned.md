---
title: "WebSocket 서버의 확장이 불가능하다? Redis Pub/Sub으로 채팅 서버 클러스터링(Scale-out) 구현하기"
date: 2026-01-27
categories: [Spring, WebSocket, Redis]
tags: [WebSocket, STOMP, Redis Pub/Sub, Scale-out, Chat System, Message Broker, TIL]
excerpt: "단일 서버에서 잘 동작하던 WebSocket 채팅 기능이 로드 밸런서 뒤에서 서버를 증설하자마자 메시지가 전달되지 않는 문제를 분석합니다. 세션의 지역성(Locality) 한계를 극복하기 위해 Redis Pub/Sub을 메시지 브로커로 활용하여 분산 환경에서도 실시간 통신이 가능한 아키텍처를 구현합니다."
author_profile: true
---

# Today I Learned: WebSocket 서버의 확장이 불가능하다? Redis Pub/Sub으로 채팅 서버 클러스터링(Scale-out) 구현하기

## 📚 오늘 학습한 내용

사내 메신저 기능을 개발하여 단일 서버에서 테스트할 때는 완벽하게 동작했습니다. 하지만 사용자가 늘어 서버를 2대로 증설(Scale-out)하고 L4 로드 밸런서를 붙이자마자 **"A 사용자가 보낸 메시지를 B 사용자가 못 받는"** 간헐적인 이슈가 터졌습니다.

원인은 **WebSocket 세션이 서버 메모리에 종속**되기 때문입니다. A는 1번 서버에, B는 2번 서버에 연결되어 있다면, 1번 서버는 B가 어디 있는지 모르기 때문에 메시지를 전달할 수 없습니다.

오늘은 이 문제를 해결하기 위해 **Redis Pub/Sub**을 도입하여, 어떤 서버에 연결되어 있든 메시지를 실시간으로 동기화하는 구조를 구축했습니다.

---

### 1. **문제의 핵심: WebSocket 세션의 격리 🏝️**

* **Server 1**: User A 접속 중 (Session Map에 A 정보 있음)
* **Server 2**: User B 접속 중 (Session Map에 B 정보 있음)

User A가 Server 1에게 "B에게 안녕이라고 전해줘"라고 메시지를 보내면, Server 1은 자신의 메모리를 뒤져보지만 B가 없습니다. 결과적으로 메시지는 증발합니다.

!

---

### 2. **해결책: 외부 메시지 브로커 (Redis Pub/Sub)**

서버끼리 대화를 할 수 있는 공용 채널(Bus)이 필요합니다. Redis의 **Publish/Subscribe** 기능이 딱입니다.

1.  **Server 1**: A의 메시지를 받으면, WebSocket으로 바로 쏘지 않고 **Redis의 특정 토픽(Topic)에 발행(Publish)**합니다.
2.  **Server 2**: 해당 토픽을 구독(Subscribe)하고 있다가, Redis로부터 메시지가 오면 **자신의 접속자 목록**에서 수신자를 찾아 메시지를 전달합니다.

---

### 3. **Spring Boot 구현**

순수 WebSocket보다는 메시지 규격이 정의된 **STOMP** 프로토콜을 사용하면 구현이 훨씬 수월합니다.

#### **Step 1: 의존성 추가**

```groovy
implementation 'org.springframework.boot:spring-boot-starter-websocket'
implementation 'org.springframework.boot:spring-boot-starter-data-redis'
```

#### **Step 2: Redis 설정 (MessageListenerAdapter)**

Redis에서 메시지가 오면 처리할 리스너를 등록합니다.

```java
@Configuration
public class RedisConfig {

    // 1. 메시지를 받을 리스너 빈 등록 (Subscriber)
    @Bean
    MessageListenerAdapter listenerAdapter(RedisSubscriber subscriber) {
        return new MessageListenerAdapter(subscriber, "onMessage");
    }

    // 2. Redis 컨테이너 설정 (Pub/Sub 연결)
    @Bean
    RedisMessageListenerContainer redisContainer(RedisConnectionFactory connectionFactory,
                                                 MessageListenerAdapter listenerAdapter) {
        RedisMessageListenerContainer container = new RedisMessageListenerContainer();
        container.setConnectionFactory(connectionFactory);
        container.addMessageListener(listenerAdapter, new ChannelTopic("chat-room"));
        return container;
    }
}
```

#### **Step 3: Publisher (메시지 발행)**

클라이언트가 메시지를 보내면 컨트롤러가 이를 받아 Redis로 쏘아 올립니다.

```java
@Controller
@RequiredArgsConstructor
public class ChatController {

    private final RedisTemplate<String, Object> redisTemplate;

    // 클라이언트가 /app/chat/message 로 전송하면 호출됨
    @MessageMapping("/chat/message")
    public void message(ChatMessage message) {
        // WebSocket으로 바로 보내는 게 아니라, Redis Topic으로 발행!
        // 모든 서버가 이 메시지를 수신하게 됨
        redisTemplate.convertAndSend("chat-room", message);
    }
}
```

#### **Step 4: Subscriber (메시지 수신 및 전달)**

모든 서버는 Redis를 구독하고 있다가, 메시지가 오면 자기한테 연결된 클라이언트에게만 최종적으로 뿌려줍니다.

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisSubscriber {

    private final ObjectMapper objectMapper;
    private final SimpMessageSendingOperations messagingTemplate; // STOMP 전송 도구

    // Redis에서 메시지가 도착하면 실행됨
    public void onMessage(String message, String channel) {
        try {
            ChatMessage chatMessage = objectMapper.readValue(message, ChatMessage.class);
            
            // 여기서 WebSocket 클라이언트에게 전송
            // SimpMessageSendingOperations는 내부적으로 연결된 세션을 찾아줌
            messagingTemplate.convertAndSend("/topic/chat/room/" + chatMessage.getRoomId(), chatMessage);
            
        } catch (Exception e) {
            log.error(e.getMessage());
        }
    }
}
```

---

### 4. **RabbitMQ / Kafka와의 비교 🤔**

* **Redis Pub/Sub**: 메시지를 저장하지 않고(Fire and Forget) 구독자가 없으면 날아갑니다. 하지만 매우 빠르고 가벼워서 실시간 채팅에 적합합니다.
* **Kafka**: 대용량 처리에 좋지만, 실시간 Latency 면에서 Redis보다 느릴 수 있고 오버헤드가 큽니다. 채팅 이력 저장용으로는 좋지만 실시간 전송용으로는 무거울 수 있습니다.
* **RabbitMQ**: STOMP 브로커 기능을 내장하고 있어(External Broker), Redis 없이 Spring 설정만으로도 클러스터링을 지원합니다. 하지만 운영 복잡도가 Redis보다 높습니다.

---

## 💡 배운 점

1.  **Stateful 서버의 확장성**: WebSocket은 대표적인 Stateful 프로토콜입니다. 이를 Stateless한 HTTP 서버처럼 확장하려면 **상태를 공유하는 외부 저장소(Redis)**가 필수적이라는 아키텍처 원칙을 체감했습니다.
2.  **SimpMessageSendingOperations의 역할**: 처음엔 "Redis에서 받으면 내 서버에 그 유저가 있는지 어떻게 알고 보내지?"라고 고민했는데, Spring의 `messagingTemplate`이 알아서 현재 서버에 연결된 세션 중에서 구독자를 찾아 쏴준다는 것을 알았습니다. (없으면 무시함)
3.  **메시지 직렬화**: Redis를 통과할 때 JSON String으로 변환(Serialize)되고, 다시 객체로 변환(Deserialize)되는 과정이 빈번하므로, `ObjectMapper` 설정과 DTO 구조를 잘 잡는 것이 성능에 중요함을 배웠습니다.

---

## 🔗 참고 자료

-   [Spring Boot WebSocket with Redis Pub/Sub](https://www.baeldung.com/spring-boot-redis-topic-message-listener)
-   [Scale-out WebSockets with Message Brokers](https://docs.spring.io/spring-framework/reference/web/websocket/stomp/message-flow.html)
-   [Redis Pub/Sub Official Docs](https://redis.io/docs/manual/pubsub/)