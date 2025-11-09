---
title: "Spring AOP Deep Dive: 나만의 @LogExecutionTime 애노테이션 만들기"
date: 2025-11-09
categories: [Spring, AOP]
tags: [Spring AOP, Aspect, @Aspect, ProceedingJoinPoint, Pointcut, AOP, TIL]
excerpt: "@Transactional, @Cacheable의 동작 원리인 AOP(관점 지향 프로그래밍)를 직접 구현해봅니다. @Aspect와 ProceedingJoinPoint를 사용해 메서드 실행 시간을 측정하는 커스텀 애노테이션을 만드는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring AOP Deep Dive: 나만의 @LogExecutionTime 애노테이션 만들기

## 📚 오늘 학습한 내용

`@Transactional`, `@Cacheable`, `@Async` 등 Spring이 제공하는 강력한 애노테이션들을 매일 사용해왔습니다. 이 기능들은 모두 **AOP(Aspect-Oriented Programming, 관점 지향 프로그래밍)**라는 기술을 기반으로 동작합니다.

지금까지는 AOP를 '사용'하는 입장이었다면, 오늘은 "어떻게 하면 나만의 공통 기능을 애노테이션으로 만들 수 있을까?"라는 질문을 가지고, **메서드의 실행 시간을 측정하는 `@LogExecutionTime`** 애노테이션을 직접 구현해봤습니다.

---

### 1. **AOP(관점 지향 프로그래밍) 핵심 용어 🧩**

AOP는 비즈니스 로직(핵심 관심사)과 공통 기능(횡단 관심사, e.g., 로깅, 트랜잭션, 보안)을 분리하여 모듈화하는 기술입니다.

-   **`Aspect` (관점)**: 횡단 관심사를 정의한 '모듈' 자체. (e.g., `LoggingAspect`)
-   **`Advice` (조언)**: Aspect가 **'무엇을(What)'** 할지 정의한 로직. (e.g., 메서드 실행 시간을 측정하는 로직)
-   **`JoinPoint` (조인포인트)**: Advice가 적용될 수 있는 **'시점'** 또는 '위치'. (e.g., 메서드 실행, 필드 접근). Spring AOP는 프록시 방식이므로 **메서드 실행 시점**만 지원합니다.
-   **`Pointcut` (포인트컷)**: 수많은 JoinPoint 중에서 Advice를 적용할 **'어디에(Where)'**를 선별하는 표현식. (e.g., `"@annotation(com.example.LogExecutionTime)"` -> 이 애노테이션이 붙은 모든 메서드)

---

### 2. **`@LogExecutionTime` 커스텀 애노테이션 만들기 🛠️**

#### **Step 1: `build.gradle` 의존성 추가**
Spring Boot에서 AOP를 사용하려면 `spring-boot-starter-aop` 의존성이 필요합니다.

```groovy
// AOP 스타터 추가
implementation 'org.springframework.boot:spring-boot-starter-aop'
```

#### **Step 2: 커스텀 애노테이션 `@LogExecutionTime` 정의**
우리가 사용할 `@LogExecutionTime` 애노테이션을 만듭니다.

```java
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target(ElementType.METHOD) // 1. 메서드에만 적용
@Retention(RetentionPolicy.RUNTIME) // 2. 런타임에 이 애노테이션 정보를 읽을 수 있도록
public @interface LogExecutionTime {
    // 이 애노테이션은 마커(Marker) 역할만 하므로 내부는 비어있음
}
```

#### **Step 3: `Aspect` 모듈 구현 (핵심 로직)**
이제 이 애노테이션이 붙었을 때 실행될 공통 로직(Advice)을 담은 `Aspect` 클래스를 작성합니다.

```java
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Pointcut;
import org.springframework.stereotype.Component;

@Aspect     // 1. 이 클래스가 Aspect임을 선언
@Component  // 2. Spring Bean으로 등록
@Slf4j
public class LoggingAspect {

    // 3. Pointcut: @LogExecutionTime 애노테이션이 붙은 모든 메서드를 대상으로 함
    @Pointcut("@annotation(com.example.aop.LogExecutionTime)")
    private void logExecutionTimePointcut() {
    }

    // 4. Advice: 메서드 실행 전후(Around)에 이 로직을 실행
    @Around("logExecutionTimePointcut()")
    public Object logExecutionTime(ProceedingJoinPoint joinPoint) throws Throwable {
        
        long startTime = System.currentTimeMillis();

        // 5. (핵심) 실제 타겟 메서드(e.g., doSomething())를 실행
        Object result = joinPoint.proceed(); 

        long endTime = System.currentTimeMillis();
        long duration = endTime - startTime;

        // 메서드 시그니처 정보 (e.g., "MyService.doSomething()")
        String methodName = joinPoint.getSignature().toShortString();
        log.info("### [Execution Time] {}: {}ms", methodName, duration);

        return result;
    }
}
```
-   **`@Around`**: 가장 강력한 Advice 타입으로, 메서드 실행 전, 후, 심지어 예외 발생 시점까지 모두 제어할 수 있습니다.
-   **`ProceedingJoinPoint`**: `@Around` Advice에서만 사용하며, 실제 타겟 메서드의 정보를 담고 있습니다. `joinPoint.proceed()`를 호출해야만 실제 메서드가 실행됩니다.

#### **Step 4: 실제 서비스에 적용하기**
이제 AOP를 적용하고 싶은 메서드에 애노테이션 한 줄만 추가하면 됩니다.

```java
@Service
@RequiredArgsConstructor
public class MyService {

    @LogExecutionTime // 6. 우리가 만든 애노테이션 적용!
    public String doSomethingThatTakesTime() throws InterruptedException {
        log.info(">> Business logic starts...");
        Thread.sleep(1500); // 1.5초간 대기하는 비즈니스 로직 시뮬레이션
        log.info(">> Business logic ends...");
        return "OK";
    }
}
```

**실행 결과 로그:**
```log
>> Business logic starts...
>> Business logic ends...
### [Execution Time] MyService.doSomethingThatTakesTime(): 1503ms
```
> 비즈니스 로직 코드(`MyService`)에는 시간 측정 코드가 단 한 줄도 없지만, AOP를 통해 공통 기능이 완벽하게 적용되었습니다.

---

## 💡 배운 점

1.  **AOP는 프록시(Proxy) 기반이다**: 오늘 이 실습을 하면서, 이전에 겪었던 `@Transactional`의 '자기 호출(Self-invocation)' 문제가 왜 발생했는지 다시 한번 명확히 이해했습니다. `@LogExecutionTime`이 붙은 메서드도, 같은 클래스 내부에서 `this.doSomethingThatTakesTime()`으로 호출하면 프록시를 타지 않아 AOP가 동작하지 않습니다.
2.  **`@Around`와 `ProceedingJoinPoint`의 강력함**: `joinPoint.proceed()` 호출을 통해 타겟 메서드의 실행 자체를 제어할 수 있다는 것이 AOP의 핵심이었습니다. 이를 응용하면 실행 시간을 측정하는 것을 넘어, 특정 조건에서는 `proceed()`를 호출하지 않고 메서드 실행을 막거나, 예외를 `try-catch`로 감싸는 등 무궁무진한 활용이 가능합니다.
3.  **핵심 로직의 순수성**: 3~4년차 개발자로서 코드의 '가독성'과 '유지보수성'을 항상 고민합니다. AOP는 `try-finally`로 감싸진 시간 측정 코드, 로깅 코드 등을 비즈니스 로직에서 완벽하게 분리하여, 서비스 클래스를 순수한 비즈니스 로직만 담고 있도록 정제해주는 최고의 도구임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Framework Docs - Aspect Oriented Programming](https://docs.spring.io/spring-framework/reference/core/aop.html)
-   [Spring AOP (Baeldung)](https://www.baeldung.com/spring-aop)
-   [AspectJ Pointcut Expressions](https://www.eclipse.org/aspectj/doc/released/progguide/language-joinPoints.html)