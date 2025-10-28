---
title: "Java의 메타프로그래밍: 리플렉션과 동적 프록시"
date: 2025-09-30
categories: [Java, JVM]
tags: [Reflection, Dynamic Proxy, AOP, JPA, Spring Core, Metaprogramming, TIL]
excerpt: "Java의 강력한 메타프로그래밍 기능인 리플렉션(Reflection)과 동적 프록시(Dynamic Proxy)의 원리를 학습합니다. 스프링 AOP와 JPA 지연 로딩이 어떤 기술을 기반으로 동작하는지, 그 내부 원리를 파헤쳐봅니다."
author_profile: true
---

# Today I Learned: Java의 메타프로그래밍: 리플렉션과 동적 프록시

## 📚 오늘 학습한 내용

스프링 프레임워크를 사용하다 보면 `@Autowired`로 의존성을 주입받거나, `@Transactional` 애노테이션 하나로 트랜잭션을 처리하는 등, 마치 마법처럼 보이는 기능들을 당연하게 사용하게 됩니다. 이 편리한 기능들의 이면에는 Java가 가진 강력한 동적 기능인 **리플렉션(Reflection)**과 **동적 프록시(Dynamic Proxy)**가 있습니다. 오늘은 이 두 가지 기술의 원리와 스프링, JPA에서 어떻게 활용되는지 학습했습니다.

---

### 1. **리플렉션 (Reflection): 런타임에 클래스를 해부하는 기술**

**리플렉션**은 프로그램이 실행 중(Runtime)에 자기 자신(클래스, 메서드, 필드 등)을 되돌아보고, 그 구조를 분석하고 수정할 수 있는 기능입니다. 컴파일 시간에는 알 수 없는 클래스의 정보를 런타임에 알아내어 객체를 생성하거나 메서드를 호출하는 등의 작업을 가능하게 합니다.

-   **핵심 원리**: Java의 모든 클래스는 로드될 때 해당 클래스에 대한 모든 정보(메서드, 필드, 생성자 등)를 담고 있는 `Class` 객체를 생성합니다. 리플렉션 API는 이 `Class` 객체를 통해 클래스의 내부 정보를 조작하는 것입니다.
-   **주요 기능**:
    -   런타임에 특정 클래스의 인스턴스 생성하기
    -   클래스의 필드(private 포함)에 직접 접근하여 값 읽기/쓰기
    -   클래스의 메서드(private 포함)를 동적으로 호출하기

#### **리플렉션 예제 코드**
```java
public class User {
    private String name = "John";
    private void sayHello() {
        System.out.println("Hello, I'm " + name);
    }
}

public class ReflectionExample {
    public static void main(String[] args) throws Exception {
        User user = new User();
        // user.sayHello(); // 컴파일 에러: private 메서드는 직접 호출 불가

        // 리플렉션으로 private 메서드 호출하기
        Class<?> userClass = user.getClass();
        Method privateMethod = userClass.getDeclaredMethod("sayHello");
        privateMethod.setAccessible(true); // private 접근 제한 해제
        privateMethod.invoke(user); // 메서드 호출 -> "Hello, I'm John"
    }
}
```
> **단점**: 리플렉션은 매우 강력하지만, 컴파일 시점의 타입 체크 이점을 잃게 되고, 캡슐화를 깨뜨리며, 일반적인 메서드 호출보다 성능이 느리다는 단점이 있어 신중하게 사용해야 합니다.

---

### 2. **동적 프록시 (Dynamic Proxy): 기능을 동적으로 추가하는 대리인**

**프록시(Proxy)**는 '대리인'이라는 뜻으로, 실제 객체(Target)를 대신하여 그에 대한 접근을 제어하고 부가 기능을 추가하는 객체입니다. **동적 프록시**는 이러한 프록시 객체를 컴파일 시점이 아닌, **런타임에 동적으로 생성**하는 기술입니다.

-   **핵심 원리**: `java.lang.reflect.Proxy` 클래스와 `InvocationHandler` 인터페이스를 사용합니다.
    1.  프록시 객체에 대한 모든 메서드 호출은 `InvocationHandler`의 `invoke` 메서드로 전달됩니다.
    2.  개발자는 이 `invoke` 메서드 안에 원하는 부가 기능(로깅, 트랜잭션 등)을 구현합니다.
    3.  부가 기능 실행 후, 실제 타겟 객체의 메서드를 호출하여 원래의 기능을 수행합니다.

#### **동적 프록시 예제 코드**
```java
// 1. 공통 인터페이스
public interface UserService {
    void greet();
}

// 2. 실제 타겟 객체
public class UserServiceImpl implements UserService {
    @Override
    public void greet() {
        System.out.println("Hello, User!");
    }
}

// 3. InvocationHandler 구현 (부가 기능 담당)
public class LoggingInvocationHandler implements InvocationHandler {
    private final Object target;

    public LoggingInvocationHandler(Object target) { this.target = target; }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        System.out.println("--- 메서드 실행 전: 로깅 ---");
        Object result = method.invoke(target, args); // 실제 타겟 메서드 호출
        System.out.println("--- 메서드 실행 후: 로깅 ---");
        return result;
    }
}

// 4. 동적 프록시 생성 및 사용
public class ProxyExample {
    public static void main(String[] args) {
        UserService target = new UserServiceImpl();
        UserService proxy = (UserService) Proxy.newProxyInstance(
                UserService.class.getClassLoader(),
                new Class[]{UserService.class},
                new LoggingInvocationHandler(target)
        );

        proxy.greet(); // 프록시 객체의 메서드 호출
    }
}
```


---

### 3. **스프링과 JPA는 이들을 어떻게 사용하는가?**

프레임워크들은 이 두 가지 기술을 적극적으로 활용하여 개발자에게 편리한 기능을 제공합니다.

-   **스프링 AOP (`@Transactional` 등)**
    -   스프링 컨테이너는 `@Transactional`이 붙은 객체(Bean)를 생성할 때, 실제 객체 대신 **동적 프록시 객체**를 생성하여 주입합니다.
    -   개발자가 `proxy.someMethod()`를 호출하면, 프록시의 `InvocationHandler`가 호출을 가로챕니다.
    -   `InvocationHandler`는 **트랜잭션을 시작**하는 부가 기능을 먼저 수행하고, 실제 객체의 `target.someMethod()`를 호출합니다.
    -   메서드 실행이 끝나면 **트랜잭션을 커밋/롤백**하는 부가 기능을 수행합니다. 이 모든 과정이 동적 프록시를 통해 자동으로 처리되는 것입니다.

-   **JPA 지연 로딩 (Lazy Loading)**
    -   `@ManyToOne(fetch = FetchType.LAZY)`와 같이 지연 로딩이 설정된 엔티티를 조회할 때, JPA는 연관된 객체를 즉시 데이터베이스에서 가져오지 않습니다.
    -   대신, 해당 객체 자리에 **동적 프록시 객체**를 채워 넣습니다. (e.g., `user.getTeam()`을 호출하면 Team의 프록시 객체를 반환)
    -   개발자가 실제로 그 프록시 객체의 메서드(e.g., `proxyTeam.getName()`)를 호출하는 **최초의 순간**, 프록시의 `InvocationHandler`가 가로채서 데이터베이스에 실제 데이터를 조회하는 쿼리를 실행하고, 그 결과를 실제 객체에 채워 넣은 뒤 메서드 호출을 위임합니다.

---

## 💡 배운 점

1.  **프레임워크의 '마법'은 기술적 근거가 있다**: 스프링과 JPA의 편리한 기능들은 막연한 마법이 아니라, 리플렉션과 동적 프록시라는 Java의 강력한 메타프로그래밍 기술 위에 정교하게 설계된 결과물임을 이해했습니다.
2.  **프록시는 '관심사의 분리(SoC)'를 실현하는 강력한 도구다**: 동적 프록시를 사용하면 핵심 비즈니스 로직과 로깅, 트랜잭션, 보안 같은 횡단 관심사(Cross-cutting concerns)를 코드 수정 없이 분리할 수 있습니다. 이것이 바로 AOP의 핵심 원리입니다.
3.  **내부 원리 이해의 중요성**: 지연 로딩이 왜 동작하는지, `@Transactional`이 어떻게 트랜잭션을 제어하는지 그 원리를 알게 되니, 단순히 기능을 사용하는 것을 넘어 발생할 수 있는 문제를 예측하고 더 효율적으로 프레임워크를 활용할 수 있겠다는 자신감이 생겼습니다.

---

## 🔗 참고 자료

-   [Oracle Docs - Dynamic Proxy Classes](https://docs.oracle.com/javase/8/docs/technotes/guides/reflection/proxy.html)
-   [The Java™ Tutorials - Reflection APIs](https://docs.oracle.com/javase/tutorial/reflect/index.html)
-   [Spring AOP (Baeldung)](https://www.baeldung.com/spring-aop)