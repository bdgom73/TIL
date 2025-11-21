---
title: "WebSocket이 부담스러울 때: Server-Sent Events (SSE)로 실시간 알림 구현하기"
date: 2025-11-21
categories: [Spring, Web]
tags: [SSE, Server-Sent Events, SseEmitter, Real-time, Notification, Spring Boot, Redis Pub/Sub, TIL]
excerpt: "양방향 통신인 WebSocket보다 가볍고, HTTP 위에서 서버가 클라이언트에게 단방향으로 데이터를 스트리밍하는 SSE(Server-Sent Events) 기술을 학습합니다. Spring의 SseEmitter 사용법과 다중 서버 환경에서의 세션 관리(Redis Pub/Sub) 전략을 알아봅니다."
author_profile: true
---

# Today I Learned: WebSocket이 부담스러울 때: Server-Sent Events (SSE)로 실시간 알림 구현하기

## 📚 오늘 학습한 내용

"좋아요가 눌렸습니다" 또는 "주문 접수가 완료되었습니다"와 같은 **실시간 알림** 기능을 구현해야 할 때, 가장 먼저 떠오르는 기술은 WebSocket입니다. 하지만 단순히 서버에서 클라이언트로 데이터를 보내기만 하면 되는 단방향 통신 상황에서, 양방향 통신인 WebSocket은 프로토콜이 무겁고 구현 복잡도가 높을 수 있습니다.

오늘은 HTTP 프로토콜을 그대로 사용하면서 서버가 클라이언트에게 데이터를 실시간으로 스트리밍할 수 있는 **SSE (Server-Sent Events)** 기술과, Spring Boot에서 `SseEmitter`를 활용한 구현 및 주의사항을 학습했습니다.

---

### 1. **SSE (Server-Sent Events)란? 📡**

SSE는 클라이언트가 서버와 한 번 연결을 맺으면, 서버가 필요할 때마다 데이터를 계속해서 보낼 수 있는 **단방향 통신 표준**입니다.

-   **프로토콜**: 표준 HTTP를 사용합니다.
-   **Content-Type**: `text/event-stream`
-   **특징**:
    -   **단방향**: Server ➡️ Client 전송만 가능합니다. (알림 기능에 최적)
    -   **자동 재연결**: 네트워크가 끊어지면 브라우저가 자동으로 재연결을 시도합니다. (WebSocket은 별도 구현 필요)
    -   **가벼움**: 별도의 프로토콜 핸드셰이크 없이 HTTP 헤더만으로 동작합니다.



---

### 2. **Spring Boot로 SSE 구현하기 (`SseEmitter`)**

Spring MVC는 `SseEmitter` 클래스를 통해 SSE를 매우 쉽게 지원합니다.

#### **Step 1: 클라이언트 연결 (구독)**
클라이언트는 `EventSource` API(JS)를 통해 연결을 요청합니다. 서버는 `SseEmitter`를 생성하여 저장하고 반환합니다.

```java
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/notifications")
public class NotificationController {

    private final NotificationService notificationService;

    @GetMapping(value = "/subscribe/{userId}", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter subscribe(@PathVariable Long userId) {
        // 1. SseEmitter 생성 (타임아웃 설정: 60초)
        SseEmitter emitter = new SseEmitter(60_000L);
        
        // 2. 생성된 Emitter를 저장소(Map 등)에 저장 (나중에 이벤트를 보내기 위해)
        notificationService.save(userId, emitter);

        // 3. Emitter 완료/타임아웃 시 저장소에서 제거하는 콜백 등록 (Memory Leak 방지)
        emitter.onCompletion(() -> notificationService.delete(userId));
        emitter.onTimeout(() -> notificationService.delete(userId));

        // 4. 503 Service Unavailable 에러 방지를 위한 더미 데이터 전송
        try {
            emitter.send(SseEmitter.event().name("connect").data("connected!"));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }

        return emitter;
    }
}
```

#### **Step 2: 알림 전송**
특정 이벤트가 발생하면 저장소에서 해당 사용자의 `SseEmitter`를 찾아 데이터를 전송합니다.

```java
@Service
@Slf4j
public class NotificationService {
    // 실제로는 ConcurrentHashMap 등을 사용하거나 별도 Repository 클래스로 관리
    private final Map<Long, SseEmitter> emitters = new ConcurrentHashMap<>();

    public void save(Long userId, SseEmitter emitter) {
        emitters.put(userId, emitter);
    }

    public void delete(Long userId) {
        emitters.remove(userId);
    }

    public void sendNotification(Long userId, String message) {
        SseEmitter emitter = emitters.get(userId);
        if (emitter != null) {
            try {
                // 이벤트 전송
                emitter.send(SseEmitter.event()
                        .name("notification")
                        .data(message));
            } catch (IOException e) {
                // 전송 실패 시(클라이언트가 연결 끊음 등) Emitter 제거
                emitters.remove(userId);
            }
        }
    }
}
```

---

### 3. **운영 환경(MSA/Scale-out)에서의 문제점과 해결책**

로컬 개발 환경(서버 1대)에서는 `Map`에 Emitter를 저장해도 잘 동작합니다. 하지만 서버가 여러 대(Scale-out)인 환경에서는 심각한 문제가 발생합니다.

-   **문제**: 사용자 A가 **서버 1**에 연결(구독)되어 있는데, 알림을 보내라는 요청이 로드 밸런서에 의해 **서버 2**로 들어온다면? 서버 2의 메모리에는 사용자 A의 `SseEmitter`가 없으므로 알림을 보낼 수 없습니다.

-   **해결책: Redis Pub/Sub 활용**
    1.  알림 발생 시, 해당 서버가 직접 Emitter를 찾지 않습니다.
    2.  대신 **Redis Topic**에 "사용자 A에게 알림 보내줘"라는 메시지를 **발행(Publish)**합니다.
    3.  모든 서버는 이 Redis Topic을 **구독(Subscribe)**하고 있습니다.
    4.  메시지를 수신한 각 서버는 **"내 메모리에 사용자 A의 Emitter가 있는가?"**를 확인합니다.
    5.  사용자 A와 연결된 **서버 1**만이 Emitter를 찾아 실제로 클라이언트에게 알림을 전송합니다.

---

## 💡 배운 점

1.  **기술 선택은 요구사항에 따라**: "실시간"이라고 해서 무조건 WebSocket이 정답은 아닙니다. 채팅처럼 양방향 대화가 필요한 게 아니라면, SSE가 훨씬 가볍고, 방화벽 친화적이며, 구현하기 쉽다는 것을 알게 되었습니다.
2.  **`SseEmitter`는 Stateful하다**: REST API는 Stateless하지만, SSE 연결은 상태(State)를 가집니다. 따라서 서버가 재시작되면 연결이 끊어지고, 다중 서버 환경에서는 세션 관리가 필요하다는 점을 명심해야 합니다.
3.  **Nginx 타임아웃 주의**: Nginx 같은 리버스 프록시는 일정 시간 동안 데이터 전송이 없으면 연결을 끊어버립니다(`proxy_read_timeout`). 이를 방지하기 위해 주기적으로 **Heartbeat** 데이터를 보내거나, Nginx 설정을 튜닝해야 안정적인 연결을 유지할 수 있습니다.

---

## 🔗 참고 자료

-   [MDN Web Docs - Server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)
-   [Spring Boot SseEmitter (Baeldung)](https://www.baeldung.com/spring-server-sent-events)
-   [Scaling SSE with Redis Pub/Sub](https://dzone.com/articles/server-sent-events-with-spring-boot-and-redis-pub)