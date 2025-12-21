---
title: "웹소켓은 너무 무겁다면? Server-Sent Events(SSE)로 실시간 알림 구현하기"
date: 2025-12-21
categories: [Spring, Web, Network]
tags: [SSE, Server-Sent Events, SseEmitter, Real-time, Notification, HTTP, TIL]
excerpt: "양방향 통신이 필요 없는 단순 알림 시스템에서 WebSocket 대신 가벼운 SSE(Server-Sent Events)를 선택하는 기준을 학습합니다. Spring의 SseEmitter 사용법과 커넥션 타임아웃, 메모리 누수 방지, 그리고 Nginx 리버스 프록시 사용 시 주의할 점을 알아봅니다."
author_profile: true
---

# Today I Learned: 웹소켓은 너무 무겁다면? Server-Sent Events(SSE)로 실시간 알림 구현하기

## 📚 오늘 학습한 내용

"주문이 완료되었습니다", "배송이 시작되었습니다" 같은 실시간 알림 기능을 구현할 때, 무작정 **WebSocket**을 도입하는 것은 오버엔지니어링일 수 있습니다. WebSocket은 양방향 통신을 위한 별도의 프로토콜 핸드셰이크가 필요하고, 상태 관리가 복잡하기 때문입니다.

오늘은 클라이언트에서 서버로 데이터를 보낼 필요 없이, **서버에서 클라이언트로 단방향**으로 데이터를 흘려보내는 표준 기술인 **SSE(Server-Sent Events)**와 Spring Boot에서의 구현 전략을 학습했습니다.

---

### 1. **WebSocket vs SSE 비교 ⚖️**

| 특징 | **WebSocket** | **Server-Sent Events (SSE)** |
| :--- | :--- | :--- |
| **통신 방향** | 양방향 (Client ↔ Server) | 단방향 (Server → Client) |
| **프로토콜** | ws:// (별도 프로토콜) | http:// (표준 HTTP) |
| **재접속** | 직접 구현 필요 | 브라우저가 자동 재접속 지원 |
| **데이터 형태** | Text, Binary | Text (UTF-8) |
| **사용 사례** | 채팅, 주식 트레이딩, 멀티플레이 게임 | 알림(Notification), 뉴스 피드, 진행률 바 |

> **결론**: 단순히 서버의 이벤트를 클라이언트에게 알려주는 용도라면 HTTP 기반이라 방화벽 친화적이고 구현이 쉬운 SSE가 훨씬 효율적입니다.

---

### 2. **Spring Boot로 구현하기 (`SseEmitter`)**

Spring MVC는 `SseEmitter` 클래스를 통해 SSE를 지원합니다. 핵심은 **"연결을 맺는 API"**와 **"알림을 보내는 로직"**을 분리하여 관리하는 것입니다.

#### **Step 1: Emitter 저장소 (Repository)**
SSE 연결 객체(`SseEmitter`)는 비동기적으로 동작하므로, 알림을 보낼 때 찾을 수 있도록 메모리(또는 Redis)에 저장해야 합니다.

```java
@Repository
public class EmitterRepository {
    // 동시성 이슈 방지를 위해 ConcurrentHashMap 사용
    private final Map<String, SseEmitter> emitters = new ConcurrentHashMap<>();

    public SseEmitter save(String id, SseEmitter emitter) {
        emitters.put(id, emitter);
        return emitter;
    }

    public void deleteById(String id) {
        emitters.remove(id);
    }

    public SseEmitter get(String id) {
        return emitters.get(id);
    }
}
```

#### **Step 2: 연결(Subscribe) 컨트롤러**
클라이언트가 최초 연결을 맺는 엔드포인트입니다. `text/event-stream` 미디어 타입을 사용합니다.

```java
@RestController
@RequiredArgsConstructor
@Slf4j
public class NotificationController {

    private final EmitterRepository emitterRepository;
    private static final Long DEFAULT_TIMEOUT = 60L * 1000 * 60; // 1시간

    @GetMapping(value = "/subscribe/{userId}", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter subscribe(@PathVariable String userId) {
        // 1. Emitter 생성 (타임아웃 설정 필수)
        SseEmitter emitter = new SseEmitter(DEFAULT_TIMEOUT);
        String emitterId = userId + "_" + System.currentTimeMillis();

        // 2. 생성 및 만료 시 콜백 등록 (메모리 누수 방지)
        emitter.onCompletion(() -> emitterRepository.deleteById(emitterId));
        emitter.onTimeout(() -> emitterRepository.deleteById(emitterId));
        emitter.onError((e) -> emitterRepository.deleteById(emitterId));

        // 3. 저장
        emitterRepository.save(emitterId, emitter);

        // 4. (중요) 연결 직후 더미 데이터 전송
        // 503 Service Unavailable 방지: 아무 데이터도 안 보내면 연결이 끊길 수 있음
        sendToClient(emitter, emitterId, "EventStream Created. [userId=" + userId + "]");

        return emitter;
    }

    private void sendToClient(SseEmitter emitter, String id, Object data) {
        try {
            emitter.send(SseEmitter.event()
                    .id(id)
                    .name("sse")
                    .data(data));
        } catch (IOException exception) {
            emitterRepository.deleteById(id);
            log.error("SSE 연결 오류", exception);
        }
    }
}
```

#### **Step 3: 알림 발송 (Service)**
다른 서비스 로직에서 이벤트를 발생시킬 때 호출하는 메서드입니다.

```java
@Service
@RequiredArgsConstructor
public class NotificationService {
    private final EmitterRepository emitterRepository;

    public void send(String userId, String message) {
        // 해당 유저의 모든 Emitter를 찾아서 발송 (멀티 디바이스 고려 시 리스트로 관리 필요)
        // 여기서는 편의상 map 전체 순회 예시
        // 실제로는 userId로 필터링된 Emitter 목록을 가져와야 함
        // ... 로직 생략 ...
    }
}
```

---

### 3. **주의사항: Nginx 버퍼링 이슈 🚧**

로컬에서는 잘 되는데 배포 서버(Nginx + WAS) 환경에서 동작하지 않는 경우가 많습니다.
Nginx는 기본적으로 백엔드 응답을 버퍼링해서 한 번에 내려주려 하기 때문에, 스트리밍 방식인 SSE가 막힙니다.

**해결책**: 응답 헤더에 `X-Accel-Buffering: no`를 추가해야 합니다.

```java
@GetMapping(value = "/subscribe", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public ResponseEntity<SseEmitter> subscribe() {
    SseEmitter emitter = new SseEmitter();
    // ... 설정 ...
    return ResponseEntity.ok()
            .header("X-Accel-Buffering", "no") // Nginx 버퍼링 끄기
            .body(emitter);
}
```

---

### 4. **Scale-out 시의 문제점**

SSE는 **Stateful**한 연결입니다. 서버 A에 연결된 사용자에게 서버 B가 알림을 보낼 수는 없습니다.
따라서 서버를 여러 대(Scale-out)로 확장한다면, **Redis Pub/Sub**을 이용해 이벤트를 전파해야 합니다.

1.  서버 B에서 "User A에게 알림 보내줘"라고 Redis 채널에 Publish.
2.  모든 서버(A, B, C)가 해당 채널을 Subscribe.
3.  서버 A가 메시지를 받고, 자기 메모리에 User A의 Emitter가 있는지 확인.
4.  있으면 `emitter.send()` 수행.

---

## 💡 배운 점

1.  **기술 선택의 유연성**: "실시간 = 웹소켓"이라는 고정관념을 버려야 합니다. 채팅처럼 빈번한 양방향 통신이 아니라면, HTTP 프로토콜을 그대로 쓰면서 가볍게 구현할 수 있는 SSE가 유지보수나 인프라 관점에서 훨씬 유리함을 깨달았습니다.
2.  **더미 이벤트의 중요성**: SSE 연결 후 아무런 데이터도 보내지 않으면, 로드밸런서나 브라우저가 타임아웃으로 연결을 끊어버릴 수 있습니다. 최초 연결 시점에 더미 데이터를 보내주는 것이 연결 안정성을 높이는 꿀팁이었습니다.
3.  **리소스 정리**: `onCompletion`, `onTimeout` 콜백을 통해 사용이 끝난 Emitter를 명시적으로 제거해주지 않으면, 서버 힙 메모리에 객체가 계속 쌓여 **OOM(Out Of Memory)**의 원인이 될 수 있음을 주의해야 합니다.

---

## 🔗 참고 자료

-   [MDN Web Docs - Server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)
-   [Spring SseEmitter Javadoc](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/servlet/mvc/method/annotation/SseEmitter.html)
-   [Nginx SSE Configuration](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering)