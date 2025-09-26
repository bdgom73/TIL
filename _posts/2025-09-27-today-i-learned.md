---
title: "Spring Core 심층 분석: IoC 컨테이너와 Bean 생명주기"
date: 2025-09-27
categories: [Java, Spring]
tags: [Spring Core, IoC, DI, Bean Lifecycle, PostConstruct, PreDestroy, TIL]
excerpt: "스프링 프레임워크의 핵심인 IoC 컨테이너가 DI(의존성 주입)를 통해 객체를 관리하는 원리를 알아봅니다. Bean이 생성되고 소멸하기까지의 생명주기(Lifecycle) 각 단계를 분석하고, @PostConstruct와 @PreDestroy를 활용해 특정 시점에 원하는 로직을 실행하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Core 심층 분석: IoC 컨테이너와 Bean 생명주기

## 📚 오늘 학습한 내용

스프링 프레임워크를 사용하면 개발자는 `new` 키워드로 객체를 직접 생성하고 관리하는 대신, 필요한 객체를 프레임워크로부터 '주입'받습니다. 이 마법과 같은 일의 중심에는 **IoC(Inversion of Control) 컨테이너**가 있습니다. 오늘은 스프링의 심장부인 IoC 컨테이너의 동작 원리와, 컨테이너가 관리하는 객체, 즉 **Bean(빈)**이 생성되고 소멸하기까지의 여정인 **생명주기(Lifecycle)**에 대해 깊이 있게 탐구했습니다.

---

### 1. **스프링의 핵심 엔진: IoC 컨테이너와 DI**

-   **제어의 역전 (Inversion of Control, IoC)**: 전통적인 프로그래밍에서는 개발자가 작성한 코드가 객체의 생성과 생명주기를 직접 제어합니다. 반면, IoC에서는 객체의 생성, 관리, 소멸에 대한 제어권이 개발자가 아닌 프레임워크(IoC 컨테이너)로 넘어갑니다.
    -   **비유**: 내가 직접 요리 재료를 사고, 다듬고, 요리하는 것(전통 방식)이 아니라, 레스토랑의 주방(IoC 컨테이너)에 "스테이크 주세요"라고 주문만 하면 주방에서 알아서 모든 것을 준비해서 주는 것과 같습니다.

-   **의존성 주입 (Dependency Injection, DI)**: DI는 IoC 개념을 구현하는 핵심적인 디자인 패턴입니다. 객체가 필요로 하는 다른 객체(의존성)를 외부(컨테이너)에서 주입해주는 방식입니다. `@Autowired`가 바로 이 역할을 수행하는 대표적인 애노테이션입니다.

-   **IoC 컨테이너 (`ApplicationContext`)**: 스프링에서 IoC를 담당하는 실질적인 컨테이너입니다. Bean의 정의를 읽어와서 객체를 생성(`new`), 의존성을 주입하고, 생명주기 전체를 관리하는 역할을 수행합니다.

---

### 2. **Bean의 여정: 생명주기(Bean Lifecycle)**

`ApplicationContext`가 시작되고 종료될 때까지, 그 안의 Bean들은 다음과 같은 체계적인 생명주기를 거칩니다.



1.  **① 스프링 컨테이너 생성**: `new AnnotationConfigApplicationContext(...)` 와 같이 `ApplicationContext`가 생성되며 컨테이너가 시작됩니다.

2.  **② 스프링 빈 생성**: 컨테이너는 `@Component`와 같은 애노테이션을 스캔하여 Bean으로 등록할 클래스를 찾고, 각 클래스의 인스턴스를 생성합니다. (객체 생성)

3.  **③ 의존성 주입**: `@Autowired` 등을 통해 해당 Bean이 필요로 하는 다른 Bean들을 찾아 주입합니다. 이때까지는 Bean이 생성되었지만, 아직 '사용 준비'가 완료된 상태는 아닙니다.

4.  **④ 초기화 콜백 (Initialization Callbacks)**: 의존성 주입까지 완료된 후, Bean이 실질적인 작업을 수행하기 전에 개발자가 원하는 '초기화' 로직을 실행할 수 있는 단계를 제공합니다.
    -   **`@PostConstruct` (권장)**: JSR-250 표준 애노테이션. 메서드에 붙이면 의존성 주입 직후 딱 한 번 호출됩니다.
    -   **`InitializingBean` 인터페이스**: `afterPropertiesSet()` 메서드를 오버라이드하는 방식. 스프링 코드에 의존적이게 되므로 최근에는 잘 사용하지 않습니다.

5.  **⑤ 빈 사용**: 모든 초기화 과정이 끝난 Bean은 이제 애플리케이션의 다른 부분에서 호출되어 사용될 준비를 마칩니다.

6.  **⑥ 소멸 콜백 (Destruction Callbacks)**: `ApplicationContext`가 `close()` 메서드로 종료되면, 컨테이너는 관리하던 Bean들을 소멸시킵니다. 소멸 직전에 자원을 해제하는 등의 '후처리' 로직을 실행할 수 있습니다.
    -   **`@PreDestroy` (권장)**: JSR-250 표준 애노테이션. Bean이 소멸되기 직전에 딱 한 번 호출됩니다.
    -   **`DisposableBean` 인터페이스**: `destroy()` 메서드를 오버라이드하는 방식. 마찬가지로 스프링 코드에 의존적이 됩니다.

---

### 3. **초기화/소멸 콜백은 언제 사용할까? (실용 예제)**

생명주기 콜백은 **의존성이 모두 주입된 이후에만 수행할 수 있는 초기화 작업**을 할 때 매우 유용합니다.

예를 들어, 데이터베이스 연결 정보를 주입받아 커넥션 풀을 생성하는 `DatabaseConnector` 클래스를 생각해 봅시다.

```java
@Component
public class DatabaseConnector {

    private final String url;
    private final String username;
    // ... Connection Pool 객체

    // 1. 생성자에서 의존성 주입 (이 시점에는 url, username만 세팅됨)
    public DatabaseConnector(@Value("${db.url}") String url, @Value("${db.username}") String username) {
        this.url = url;
        this.username = username;
        System.out.println("생성자 호출: url, username 주입 완료. 아직 연결은 안됨.");
    }

    // 2. @PostConstruct: 의존성 주입이 끝난 후 호출됨
    @PostConstruct
    public void connect() {
        System.out.println("초기화 콜백(@PostConstruct): DB 연결 및 커넥션 풀 생성 시작...");
        // 이 시점에는 url, username 값이 보장되므로, 이를 이용해 실제 DB 연결 로직 수행
        // this.connectionPool = new ConnectionPool(this.url, this.username);
        System.out.println("DB 연결 성공!");
    }

    // 3. @PreDestroy: 컨테이너가 종료될 때 호출됨
    @PreDestroy
    public void disconnect() {
        System.out.println("소멸 콜백(@PreDestroy): 모든 DB 커넥션 자원 해제...");
        // this.connectionPool.closeAll();
        System.out.println("자원 해제 완료.");
    }
}
```

생성자에서는 필드 값만 세팅될 뿐, 실제 DB 연결을 시도하기에는 이릅니다. `@PostConstruct`를 사용하면 **모든 의존성 주입이 끝났음을 보장**받는 시점에서 안전하게 초기화 로직을 수행할 수 있습니다.

---

## 💡 배운 점

1.  **DI는 IoC를 위한 '수단'이다**: IoC라는 '제어의 역전'이라는 큰 개념을 스프링이 구현하는 방식이 바로 DI임을 명확히 이해했습니다. 프레임워크가 객체를 관리하기 때문에 개발자는 비즈니스 로직에 더 집중할 수 있습니다.
2.  **생성자와 `@PostConstruct`의 명확한 역할 구분**: 생성자는 객체 생성과 필수 의존성(final 필드 등)을 주입받는 역할에 집중하고, 주입받은 의존성을 활용한 실질적인 초기화 작업은 `@PostConstruct` 콜백 메서드에서 수행하는 것이 좋은 설계라는 것을 깨달았습니다.
3.  **스프링은 '관리자'다**: Bean의 탄생부터 죽음까지 전 과정을 스프링 컨테이너가 체계적으로 관리한다는 것을 알게 되었습니다. 생명주기 콜백을 이해함으로써, 이 관리 흐름의 특정 시점에 우리가 원하는 코드를 끼워 넣어 더욱 정교한 제어를 할 수 있게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Framework Documentation - The IoC Container](https://docs.spring.io/spring-framework/reference/core/ioc-container.html)
-   [Spring Bean Lifecycle (Baeldung)](https://www.baeldung.com/spring-bean-life-cycle)