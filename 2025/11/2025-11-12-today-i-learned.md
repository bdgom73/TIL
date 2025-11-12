---
title: "Spring Boot 유효성 검사(Validation) 심층 분석: @Valid vs. @Validated, 그리고 커스텀 Validator"
date: 2025-11-12
categories: [Spring, Test]
tags: [Validation, @Valid, @Validated, ConstraintValidator, AOP, Spring Boot, TIL]
excerpt: "Controller 계층의 DTO 유효성 검사를 넘어, @Valid와 @Validated의 차이점을 AOP 관점에서 학습하고, 비즈니스 로직이 포함된 커스텀 애노테이션을 만드는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot 유효성 검사(Validation) 심층 분석: @Valid vs. @Validated, 그리고 커스텀 Validator

## 📚 오늘 학습한 내용

Controller에서 `@RequestBody`로 DTO를 받을 때 `jakarta.validation`의 `@NotNull`, `@Email`, `@Size` 같은 애노테이션을 습관적으로 사용해왔습니다. 하지만 오늘은 이 기능이 **어떻게 동작하는지**, 그리고 **`@Valid`와 `@Validated`의 혼란스러운 차이점**은 무엇인지, 나아가 단순한 폼 검증을 넘어 **비즈니스 로직이 포함된 커스텀 Validator**는 어떻게 만드는지 깊이 있게 학습했습니다.

---

### 1. **기본 동작: `@Valid`와 `MethodArgumentNotValidException`**

Spring Boot는 `spring-boot-starter-validation`을 통해 Jakarta Bean Validation(JSR-303)을 자동으로 지원합니다.

-   **Controller에서의 동작**:
    1.  `@RestController`의 메서드 파라미터에 `@Valid`를 붙입니다.
    2.  HTTP 요청이 오면, Spring의 `DispatcherServlet`이 해당 DTO의 유효성 검사를 **자동으로 수행**합니다.
    3.  만약 유효성 검사에 실패하면(e.g., `@Email` 형식 위반), 메서드를 실행하지 않고 **`MethodArgumentNotValidException`** 예외를 발생시킵니다.
    4.  이 예외는 `@RestControllerAdvice` (`@ExceptionHandler`)에서 공통으로 처리하여 400 Bad Request 응답을 반환하는 것이 일반적인 패턴입니다.

```java
// UserRequestDto.java
public class UserRequestDto {
    @NotBlank(message = "이메일은 필수입니다.")
    @Email(message = "유효한 이메일 형식이 아닙니다.")
    private String email;
    
    @Size(min = 8, message = "비밀번호는 8자 이상이어야 합니다.")
    private String password;
}

// UserController.java
@RestController
public class UserController {
    @PostMapping("/users")
    public ResponseEntity<Void> signUp(@Valid @RequestBody UserRequestDto requestDto) {
        // 유효성 검사를 통과한 DTO만 이 메서드로 들어옴
        userService.signUp(requestDto);
        return ResponseEntity.ok().build();
    }
}
```

---

### 2. **3~4년차의 단골 실수: `@Valid` vs. `@Validated` ⚡️**

가장 혼란스러웠던 지점입니다. "왜 `@Service` 계층의 메서드에는 `@Valid`가 동작하지 않을까?"

**1. `@Valid` (JSR-303 표준)**
-   Jakarta Bean Validation의 **표준 애노테이션**입니다.
-   Spring에서 `@Valid`는 **Controller의 `@RequestBody`**나 `@ModelAttribute`와 결합될 때 **데이터 바인딩** 과정에서 특별히 동작합니다.
-   **단점**: 유효성 검사 '그룹(Group)'을 지정할 수 없고, **AOP 기반의 메서드 유효성 검사에 사용될 수 없습니다.**

**2. `@Validated` (Spring 전용)**
-   Spring 프레임워크가 제공하는 **전용 애노테이션**입니다.
-   **핵심**: **AOP(관점 지향 프로그래밍)**를 기반으로 동작합니다.
-   `@Service`나 `@Component` 같은 빈(Bean)의 클래스나 메서드에 `@Validated`를 붙이면, Spring이 해당 빈에 대한 **프록시(Proxy)**를 생성합니다.
-   메서드가 호출될 때 프록시가 요청을 가로채서, 파라미터에 대한 유효성 검사를 **먼저 수행**하고, 실패 시 **`ConstraintViolationException`**을 발생시킵니다.
-   **장점**: 유효성 검사 '그룹'을 지정하여 "생성 시 검증 룰"과 "수정 시 검증 룰"을 분리할 수 있습니다.

**결론**:
-   **Controller (데이터 바인딩)**: `@Valid`를 사용합니다.
-   **Service (AOP 기반 메서드 검증)**: **`@Validated`**를 클래스에 붙이고, 파라미터에 `@Valid`를 붙여야 합니다.

```java
// UserService.java
@Service
@Validated // 1. (핵심) 클래스 레벨에 @Validated를 붙여 AOP 검증을 활성화
public class UserService {

    // 2. 메서드 파라미터에 @Valid를 붙여 유효성 검사 실행
    public void createProduct(@Valid ProductCreateDto dto) {
        // 이 메서드가 외부에서 호출될 때,
        // 프록시가 dto를 먼저 검증하고 예외를 던짐
    }
}
```
> 만약 `@Validated` 없이 `@Service`의 메서드 파라미터에 `@Valid`만 쓴다면, AOP가 동작하지 않아 유효성 검사가 무시됩니다.

---

### 3. **Custom Validator: 비즈니스 로직 검증하기**

`@Email`이나 `@Size`로는 부족한, DB 조회가 필요한 복잡한 비즈니스 룰(e.g., "이미 존재하는 이메일인가?")은 어떻게 처리할까요?

**1. `@UniqueEmail` 애노테이션 정의**
```java
@Constraint(validatedBy = UniqueEmailValidator.class) // 2. 검증 로직을 담을 클래스
@Target({ElementType.FIELD, ElementType.PARAMETER}) // 1. 필드와 파라미터에 사용
@Retention(RetentionPolicy.RUNTIME)
public @interface UniqueEmail {
    String message() default "이미 사용 중인 이메일입니다.";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

**2. `ConstraintValidator` 구현**
실제 DB 조회를 수행하는 Validator 로직을 구현합니다. Spring의 DI(의존성 주입)를 활용할 수 있습니다.

```java
@Component // 3. (핵심) Spring Bean으로 등록하여 DI를 받을 수 있게 함
@RequiredArgsConstructor
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    private final UserRepository userRepository;

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (email == null || email.isBlank()) {
            return false;
        }
        // 4. DB 조회를 통해 비즈니스 로직 검증
        return !userRepository.existsByEmail(email);
    }
}
```

**3. DTO에 적용**
```java
public class UserRequestDto {
    
    @NotBlank(message = "이메일은 필수입니다.")
    @Email(message = "유효한 이메일 형식이 아닙니다.")
    @UniqueEmail // 5. 우리가 만든 커스텀 애노테이션 적용
    private String email;
    
    // ...
}
```

---

## 💡 배운 점

1.  **`@Valid`는 Controller용, `@Validated`는 Service용이다**: 이 둘의 차이를 AOP와 프록시 관점에서 명확히 이해했습니다. 서비스 계층에서 파라미터 검증이 필요할 땐, 반드시 클래스 레벨에 `@Validated`를 붙여 AOP를 활성화해야 합니다.
2.  **`ConstraintViolationException` vs. `MethodArgumentNotValidException`**: Controller에서 실패하면 `MethodArgumentNotValidException`이, `@Validated`가 붙은 Service에서 실패하면 `ConstraintViolationException`이 발생합니다. `@RestControllerAdvice`에서 두 예외를 모두 처리해야 함을 알게 되었습니다.
3.  **검증 로직도 분리(SoC) 대상이다**: '이메일 중복 확인' 같은 비즈니스 로직을 서비스 메서드 안에 `if`문으로 넣는 대신, `@UniqueEmail`이라는 선언적인 애노테이션으로 분리함으로써, DTO 자체만 봐도 이 필드의 비즈니스 규칙을 명확히 알 수 있게 되었습니다. 이는 코드의 가독성과 유지보수성을 크게 향상시킵니다.

---

## 🔗 참고 자료

-   [Jakarta Bean Validation 3.0 Specification](https://beanvalidation.org/3.0/spec/)
-   [Spring Docs - Validation](https://docs.spring.io/spring-framework/reference/core/validation.html)
-   [@Valid vs. @Validated in Spring (Baeldung)](https://www.baeldung.com/spring-valid-vs-validated)