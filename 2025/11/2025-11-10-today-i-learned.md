---
title: "Spring Boot와 WebSocket (STOMP)을 이용한 실시간 통신"
date: 2025-11-10
categories: [Spring, WebSocket]
tags: [WebSocket, STOMP, Spring Boot, Real-time, Messaging, TIL]
excerpt: "HTTP의 단방향 요청/응답 모델의 한계를 넘어, 실시간 양방향 통신을 가능하게 하는 WebSocket의 개념을 학습합니다. 특히 STOMP 프로토콜을 Spring Boot에 적용하여 메시지 브로커를 구성하고, 채팅이나 알림 기능을 구현하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot와 WebSocket (STOMP)을 이용한 실시간 통신

## 📚 오늘 학습한 내용

대부분의 API를 HTTP 기반의 RESTful하게 설계해왔습니다. 이는 클라이언트의 요청(Request)이 있을 때만 서버가 응답(Response)하는 단방향 통신에 최적화되어 있습니다. 하지만 실시간 채팅, 주식 시세 알림, 라이브 대시보드처럼 **서버가 클라이언트에게 먼저 데이터를 밀어넣어야(Push) 하는** 요구사항에는 적합하지 않습니다.

오늘은 이 문제를 해결하기 위한 **WebSocket** 기술과, 이를 Spring Boot 환경에서 더 쉽게 다룰 수 있게 해주는 **STOMP** 프로토콜에 대해 학습했습니다.

---

### 1. **WebSocket과 STOMP: 왜 둘 다 필요할까?**

-   **WebSocket (웹소켓)**:
    -   HTML5 표준 기술로, **하나의 TCP 연결** 위에서 클라이언트와 서버가 실시간으로 데이터를 주고받을 수 있는 **양방향(Full-Duplex) 통신 채널**입니다.
    -   HTTP와 달리 연결이 한 번 수립되면 계속 유지됩니다.
    -   **한계**: WebSocket 자체는 "데이터를 보낸다/받는다"라는 기능만 정의할 뿐, 메시지의 형식이나 목적지(e.g., "A 채팅방 구독", "B 유저에게 메시지 전송")를 구분하는 표준적인 방법이 없습니다.

-   **STOMP (Simple Text Oriented Messaging Protocol)**:
    -   WebSocket 위에서 동작하는 **메시징 프로토콜**입니다. (HTTP가 TCP 위에서 동작하듯)
    -   WebSocket이라는 '통로'에 '구조'를 더해줍니다.
    -   **주요 기능**:
        -   `SUBSCRIBE`: 특정 '목적지(Destination)'를 구독.
        -   `SEND`: 특정 목적지로 메시지 전송.
        -   `MESSAGE`: 브로커가 구독자에게 메시지 전달.
    -   **결론**: STOMP를 사용하면 Spring의 `@MessageMapping` 애노테이션과 메시지 브로커(Broker)를 활용하여 Pub/Sub 모델을 손쉽게 구현할 수 있습니다.

---

### 2. **Spring Boot WebSocket + STOMP 아키텍처**

Spring에서 STOMP를 사용하면, 시스템 내부에 간단한 **메시지 브로커**가 내장됩니다.



-   **`WebSocketConfig.java` (핵심 설정)**:
    1.  `@EnableWebSocketMessageBroker`: 메시지 브로커 기능을 활성화합니다.
    2.  `registerStompEndpoints()`: WebSocket **연결을 위한 엔드포인트**를 설정합니다. 클라이언트가 최초로 WebSocket 핸드셰이크를 시도하는 URL입니다. (e.g., `/ws-chat`)
    3.  `configureMessageBroker()`: 메시지 브로커의 동작을 설정합니다.
        -   **`enableSimpleBroker("/topic", "/queue")`**:
            -   `/topic`, `/queue` 프리픽스가 붙은 목적지(Destination)를 가진 메시지를 **브로커**가 처리하도록 설정합니다.
            -   브로커는 이 메시지를 해당 목적지를 구독 중인 모든 클라이언트에게 **브로드캐스팅(Broadcast)**합니다. (메모리 기반 브로커)
        -   **`setApplicationDestinationPrefixes("/app")`**:
            -   `/app` 프리픽스가 붙은 메시지를 **애플리케이션(Controller)**이 처리하도록 설정합니다.
            -   클라이언트가 서버의 비즈니스 로직을 호출할 때 사용합니다.

#### **설정 코드 예시**
```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // 1. 클라이언트가 WebSocket 연결을 시작할 엔드포인트
        registry.addEndpoint("/ws-connect") // e.g., new WebSocket("ws://host/ws-connect")
                .withSockJS(); // WebSocket을 지원하지 않는 브라우저를 위해 SockJS 사용
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        // 2. 브로커가 처리할 목적지 (클라이언트에게 메시지 전송)
        //    /topic/room1, /queue/user123 등
        registry.enableSimpleBroker("/topic", "/queue"); 
        
        // 3. 애플리케이션(컨트롤러)이 처리할 목적지 (클라이언트가 메시지 전송)
        //    /app/chat, /app/enter 등
        registry.setApplicationDestinationPrefixes("/app"); 
    }
}
```

---

### 3. **메시지 흐름과 컨트롤러 구현**

**흐름**:
1.  클라이언트가 `/app/chat` 목적지로 메시지(Payload)를 `SEND`합니다.
2.  `setApplicationDestinationPrefixes` 설정에 따라 Spring이 `/app`을 제외한 `/chat` 매핑을 찾습니다.
3.  `@MessageMapping("/chat")`이 붙은 컨트롤러 메서드가 메시지를 받습니다.
4.  메서드가 실행된 후, `@SendTo("/topic/room1")` 설정에 따라 반환값이 `/topic/room1` 목적지로 전송됩니다.
5.  `enableSimpleBroker` 설정에 따라 브로커가 `/topic/room1`을 구독 중인 모든 클라이언트에게 메시지를 `MESSAGE`로 브로드캐스팅합니다.

#### **컨트롤러 코드 예시**
```java
@Controller
public class ChatController {

    // 1. 클라이언트가 "/app/chat"으로 메시지를 보내면 이 메서드가 받음
    @MessageMapping("/chat")
    // 2. 메서드 실행 후, "/topic/room1"을 구독하는 클라이언트들에게 반환값을 보냄
    @SendTo("/topic/room1")
    public ChatMessage handleChatMessage(ChatMessage message) {
        // ... (DB 저장 등 비즈니스 로직) ...
        
        // ChatMessage 객체를 반환하면 JSON으로 변환되어 브로드캐스팅됨
        return new ChatMessage(message.getSender(), message.getContent(), System.currentTimeMillis());
    }
}
```
> `@MessageMapping`은 HTTP의 `@PostMapping`과, `@SendTo`는 응답을 특정 경로로 보내는 것과 유사하게 동작합니다.

---

## 💡 배운 점

1.  **WebSocket과 STOMP의 역할 분리**: 순수 WebSocket(TCP 소켓 통신과 유사)과 STOMP(메시지 스펙 정의)의 차이를 명확히 이해했습니다. STOMP가 없다면, 모든 메시지 형식을 JSON으로 직접 파싱하고 구독자 관리를 수동으로 해야 했을 것입니다.
2.  **핵심은 '프리픽스(Prefix)' 설정이다**: `configureMessageBroker`의 두 설정, `enableSimpleBroker`와 `setApplicationDestinationPrefixes`가 가장 혼란스러웠습니다. 전자는 **서버 -> 클라이언트**로 나가는 브로드캐스팅용(구독), 후자는 **클라이언트 -> 서버**로 들어오는 처리용(발행)임을 명확히 구분하는 것이 핵심입니다.
3.  **인증/인가는 어떻게?**: REST API는 매 요청마다 `Authorization` 헤더를 검사하면 되지만, WebSocket은 한 번 수립된 연결을 계속 사용합니다. 따라서 최초 핸드셰이크 시점이나 STOMP `CONNECT` 프레임의 헤더를 가로채어 JWT 토큰을 검증하는 별도의 보안 로직(e.g., `ChannelInterceptor`)이 필요함을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Docs - WebSocket Support](https://docs.spring.io/spring-framework/reference/web/websocket.html)
-   [Spring Docs - STOMP Over WebSocket](https://docs.spring.io/spring-framework/reference/web/websocket.html#websocket-stomp)
-   [Using STOMP with Spring Boot (Baeldung)](https://www.baeldung.com/spring-websockets-stomp)