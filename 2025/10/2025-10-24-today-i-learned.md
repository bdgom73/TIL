---
title: "Spring WebFlux 시작하기: 반응형 프로그래밍과 논블로킹 I/O"
date: 2025-10-24
categories: [Spring, Reactive]
tags: [Spring WebFlux, Reactive Programming, Non-blocking I/O, Mono, Flux, Project Reactor, TIL]
excerpt: "기존의 동기/블로킹 방식(Servlet 기반 Spring MVC)의 한계를 알아보고, 더 적은 리소스로 더 많은 트래픽을 처리하기 위한 반응형 프로그래밍(Reactive Programming)과 Spring WebFlux의 핵심 개념을 학습합니다. Mono와 Flux를 이용한 비동기 데이터 스트림 처리 방식을 탐구합니다."
author_profile: true
---

# Today I Learned: Spring WebFlux 시작하기: 반응형 프로그래밍과 논블로킹 I/O

## 📚 오늘 학습한 내용

저는 3년 넘게 서블릿(Servlet) 기반의 **Spring MVC**를 사용하여 동기/블로킹 방식으로 웹 애플리케이션을 개발하는 데 익숙했습니다. 이 방식은 "요청 당 스레드(Thread-per-request)" 모델을 사용하며 코드를 이해하고 작성하기 쉽다는 장점이 있습니다. 하지만 I/O 작업(DB 조회, 외부 API 호출 등)이 발생할 때마다 해당 스레드가 **차단(Blocked)**되어 대기해야 하므로, 동시 사용자가 많아지면 스레드 수가 급증하고 시스템 리소스가 빠르게 고갈되는 한계가 있습니다.

오늘은 이러한 한계를 극복하고 **더 적은 스레드로 더 높은 처리량**을 달성하기 위한 **반응형 프로그래밍(Reactive Programming)** 패러다임과 이를 Spring에서 구현한 **Spring WebFlux**에 대해 학습했습니다.

---

### 1. **왜 반응형(Reactive)인가? 논블로킹(Non-blocking) I/O의 힘 💪**

-   **동기/블로킹 (Sync/Blocking) - Spring MVC**:
    -   요청이 오면 스레드가 할당됩니다.
    -   DB 조회와 같은 I/O 작업 시, 스레드는 DB 응답이 올 때까지 **멈춰서 기다립니다(Blocked)**. 이 시간 동안 스레드는 아무 일도 못 하고 CPU 자원만 점유합니다.
    -   동시 요청이 1000개 오면, 최소 1000개의 스레드가 필요합니다.

-   **비동기/논블로킹 (Async/Non-blocking) - Spring WebFlux**:
    -   요청이 오면 **이벤트 루프(Event Loop)** (보통 적은 수의 고정된 스레드, e.g., CPU 코어 수만큼)가 요청을 받습니다.
    -   DB 조회와 같은 I/O 작업을 요청하고, 스레드는 **기다리지 않고 즉시 다른 요청을 처리하러 갑니다.**
    -   DB 작업이 완료되면 **콜백(Callback)** 방식으로 이벤트 루프에게 알립니다.
    -   이벤트 루프는 완료된 결과를 받아 응답을 생성합니다.
    -   적은 수의 스레드로 수많은 동시 요청을 효율적으로 처리할 수 있습니다.

**비유**:
-   **블로킹**: 전화 주문을 받고 음식이 나올 때까지 수화기를 들고 계속 기다리는 직원 1000명.
-   **논블로킹**: 진동벨 주문 시스템. 주문만 받고 진동벨을 준 뒤 다른 손님 주문을 계속 받는 직원 몇 명. 음식이 나오면 진동벨로 알려줌.

---

### 2. **Spring WebFlux와 Project Reactor: Mono & Flux 💧🌊**

Spring WebFlux는 내부적으로 **Project Reactor**라는 반응형 라이브러리를 사용하여 비동기 데이터 스트림을 처리합니다. Reactor는 두 가지 핵심 **Publisher** 타입을 제공합니다.

-   **`Mono<T>`**: 0개 또는 **1개**의 데이터(결과)를 비동기적으로 전달하는 Publisher입니다. (e.g., 단일 객체 조회 API 응답)
-   **`Flux<T>`**: 0개 또는 **N개**(여러 개 또는 무한 개)의 데이터 시퀀스를 비동기적으로 전달하는 Publisher입니다. (e.g., 리스트 조회 API 응답, 실시간 데이터 스트림)



이 Publisher들은 데이터가 실제로 준비되었을 때 데이터를 **방출(Emit)**하며, 구독자(Subscriber)는 이 데이터를 받아 처리합니다. 모든 연산은 체이닝(Chaining) 방식으로 연결되며, **실제 구독(`subscribe()`)이 발생하기 전까지는 아무런 동작도 하지 않습니다 (Lazy Execution).**

#### **코드 비교: Spring MVC vs. Spring WebFlux**

**① Spring MVC (동기/블로킹)**
```java
@RestController
@RequestMapping("/mvc/users")
@RequiredArgsConstructor
public class MvcUserController {
    private final UserRepository userRepository;

    @GetMapping("/{id}")
    public User getUserById(@PathVariable Long id) {
        // findById가 완료될 때까지 스레드 블로킹
        return userRepository.findById(id)
                .orElseThrow(() -> new UserNotFoundException());
    }

    @GetMapping
    public List<User> getAllUsers() {
        // findAll이 완료될 때까지 스레드 블로킹
        return userRepository.findAll();
    }
}
```

**② Spring WebFlux (비동기/논블로킹)**
```java
@RestController
@RequestMapping("/webflux/users")
@RequiredArgsConstructor
public class WebFluxUserController {
    // WebFlux에서는 Reactive Repository를 사용 (e.g., R2DBC, Reactive Mongo)
    private final ReactiveUserRepository userRepository; 

    @GetMapping("/{id}")
    public Mono<User> getUserById(@PathVariable Long id) {
        // findById는 즉시 Mono<User>를 반환하고, DB 결과는 나중에 비동기적으로 채워짐
        return userRepository.findById(id)
                .switchIfEmpty(Mono.error(new UserNotFoundException()));
    }

    @GetMapping
    public Flux<User> getAllUsers() {
        // findAll은 즉시 Flux<User>를 반환하고, DB 결과는 스트림 형태로 비동기적으로 전달됨
        return userRepository.findAll();
    }
}
```
> WebFlux 컨트롤러는 실제 데이터(`User`, `List<User>`) 대신, 데이터의 비동기 스트림을 나타내는 `Mono` 또는 `Flux`를 반환합니다.

---

### 3. **백프레셔 (Backpressure): 넘쳐흐름 방지 댐 🏞️**

Publisher가 너무 빠른 속도로 데이터를 방출하고 Subscriber가 이를 처리하는 속도보다 빠르면 어떻게 될까요? Subscriber는 감당할 수 없는 데이터에 압도되어 결국 메모리 부족 등으로 시스템이 다운될 수 있습니다.

**백프레셔**는 Subscriber가 자신이 처리할 수 있는 만큼의 데이터 개수를 Publisher에게 **요청(request)**하는 메커니즘입니다. Publisher는 요청받은 개수만큼만 데이터를 전달하여 데이터 흐름을 조절합니다. 이는 반응형 스트림(Reactive Streams) 표준의 핵심적인 기능입니다.

---

## 💡 배운 점

1.  **WebFlux는 만병통치약이 아니다**: 논블로킹 I/O는 I/O 작업이 많은 서비스에서 확실한 성능 이점을 제공하지만, CPU 연산 위주의 작업이 많거나 개발팀이 반응형 프로그래밍에 익숙하지 않다면 오히려 개발 복잡성만 증가시킬 수 있습니다. 특히, JDBC와 같은 전통적인 블로킹 라이브러리를 WebFlux 환경에서 잘못 사용하면 성능 이점을 전혀 얻지 못할 수도 있습니다 (별도의 스레드 풀에서 실행해야 함).
2.  **새로운 사고방식의 필요성**: `Mono`와 `Flux`를 다루는 것은 절차적인 코드에 익숙했던 저에게 완전히 새로운 사고방식을 요구했습니다. 데이터 스트림을 선언적으로 정의하고, 구독이 발생할 때까지 아무 일도 일어나지 않는다는 점, 그리고 블로킹 코드를 최대한 피해야 한다는 점을 항상 염두에 두어야 합니다.
3.  **생태계의 중요성**: WebFlux의 진정한 성능을 발휘하려면 데이터베이스 드라이버(R2DBC, Reactive MongoDB Driver), HTTP 클라이언트(`WebClient`) 등 생태계 전반이 논블로킹을 지원해야 합니다. 아직 모든 기술 스택이 반응형을 완벽하게 지원하는 것은 아니므로, 도입 전에 기술적 제약을 충분히 검토해야 합니다.

---

## 🔗 참고 자료

-   [Spring WebFlux 공식 문서](https://docs.spring.io/spring-framework/reference/web/webflux.html)
-   [Project Reactor 공식 문서](https://projectreactor.io/docs/core/release/reference/)
-   [Reactive Streams Specification](https://www.reactive-streams.org/)
-   [WebFlux (Baeldung)](https://www.baeldung.com/spring-webflux)