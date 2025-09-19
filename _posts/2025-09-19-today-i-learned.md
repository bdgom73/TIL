---
title: "Spring Boot에서 바이브 코딩 시 효과적인 프롬프트 작성 방법"
date: 2025-09-19
categories: [Spring Boot]
tags: [Prompt Writing, Vibe Coding, TIL, Spring]
excerpt: "Spring Boot를 사용한 개발 중 바이브 코딩(실시간 코딩)에서 적합한 프롬프트 작성 및 디버깅 방법에 대해 학습합니다."
author_profile: true
---

# Today I Learned: Spring Boot에서 바이브 코딩 시 효과적인 프롬프트 작성 방법

## 📚 오늘 학습한 내용

### 1. **바이브 코딩이란?**
- **바이브 코딩**은 코드를 작성하며 실시간으로 결과를 확인하고, 잘못된 부분을 즉각 수정해 가는 방식의 코딩입니다.
   - 주로 IDE의 코드 실행 도구, 테스트 도구(JUnit 등)를 이용하여 반복적으로 개발과 수정 작업을 진행합니다.
   - 이러한 방식에서 가장 중요한 것은 **효과적인 "프롬프트 작성" 및 문제 정의** 능력입니다.

> 프롬프트는 코드를 테스트하거나 필요 사항을 정의하여 구체적인 구현을 빠르게 처리하기 위한 "질문" 또는 "명세"를 의미합니다!

---

### 2. 효과적인 프롬프트 작성의 중요한 원칙

바이브 코딩에서 프롬프트는 사람과 도구(IC, 라이브러리 등) 또는 AI 사이의 **의사소통 수단**입니다.  
잘못된 프롬프트는 디버깅 시간을 늘리고 개발 효율을 낮춥니다.  
따라서 아래의 원칙을 지켜 프롬프트를 작성해야 합니다.

#### 2.1. 문제를 **구체적으로** 정의하라
- 문제를 압축적으로 입력하되, 필요한 컨텍스트는 반드시 포함해야 합니다.
- **잘못된 프롬프트 예시**
  > "로그인 기능에서 에러가 발생합니다. 어떻게 해야 하나요?"
- **올바른 프롬프트 예시**
  > "Spring Security를 사용하는 로그인 API 호출 시 `403 Forbidden` 에러가 발생합니다.  
  > 요청 경로는 `/login`, HTTP 메서드는 POST입니다.  
  > Controller와 Security 설정 코드가 아래와 같습니다. 수정 방법을 알려주세요."

#### 2.2. **상황에 맞는 제한 조건을 명시**하라
- 구현할 코드나 테스트의 동작 조건 또는 의도된 결과는 정확하게 명시합니다.
- 예를 들어 "서버 응답 속도를 최적화하라"라는 명령을 전달하는 대신:
  > - **응답 시간은 500ms 미만으로 설정**
  > - **캐싱 활용 여부와 캐시 주기를 반드시 검토**

#### 2.3. 코드는 **단순히 제공**하고 핵심은 **질문에 집중**하라
- 도움 요청이든 자가 텍스트이든, 코드 제공 시 핵심과 관련된 부분만 간략히 제공하세요.
- 예를 들어:
  ```markdown
  @RestController
  public class UserController {
      @GetMapping("/users")
      public List<User> getUsers() {
          return null;  // 여기에 오류 발생 중
      }
  }
  ```
  > "위 `getUsers()` 메서드에서 반환값이 항상 `null`로 나옵니다. UserRepository에서 데이터를 가져오도록 수정하려면 어떻게 해야 할까요?"

---

### 3. Spring Boot에서 "바이브 코딩을 위한 프롬프트 작성" 활용 예제

#### 예제 1: CRUD 애플리케이션 개발 시
**요구사항: `POST /users`로 전달된 Json 데이터를 MySQL DB에 저장하는 API 구현**

효과적인 프롬프트 작성:
> "Spring Boot에서 MySQL과 연동하여 간단한 User 등록 API를 작성하려고 합니다. JPA를 사용하여 User 엔티티를 DB에 저장하고, 성공 시 저장된 User 정보를 반환하는 컨트롤러 작성 방법을 알려주세요.  
> 예시 Json 구조는 다음과 같습니다."
```json
{
    "name": "John Doe",
    "email": "john.doe@example.com"
}
```

**불필요한 프롬프트 예시 (비효율적)**
> "User API를 만들고 싶은데 머리가 잘 안 돌아갑니다. 어떻게 해야 하나요?"

---

#### 예제 2: Spring Security 인증 처리
**요구사항: 로그인 실패 시 커스텀 에러 메시지를 반환하도록 구현**

효과적인 프롬프트 작성:
> "Spring Security에서 사용자 인증 실패 시 기본 메시지 대신, JSON 형태로 직접 작성한 커스텀 에러 메시지를 반환하고 싶습니다.  
> 예를 들어:
> - 요청: `{ "username": "invalid_user", "password": "1234" }`
> - 응답: `{ "error": "Invalid login credentials" }`
>
> 이를 구현하기 위한 `AuthenticationFailureHandler` 설정 방법을 자세히 설명해주세요."

---

### 4. 문제 해결과 디버깅 로직 예시
프롬프트를 정확히 작성한 경우, **Spring Boot에서 코딩 및 테스트를 효율적으로 수행할 수 있습니다.**

아래는 **AOP를 적용해 메서드의 실행 시간을 로깅하는 로직이 제대로 작동하지 않을 때** 작성한 프롬프트 예시입니다:

#### 문제 정의
> "Spring AOP로 Controller 메서드의 실행 시간을 로깅하는 기능을 작성했지만, `@Controller`에서 AOP 로직이 실행되지 않습니다. 로그인 컨트롤러에서만 AOP가 동작하도록 설정하려면 어떻게 해야 할까요? 코드의 일부를 첨부합니다."
```java
@Aspect
@Component
public class ExecutionTimeAspect {

    @Before("execution(* com.example.demo.controller.*.*(..))")
    public void logExecutionTime(JoinPoint joinPoint) {
        System.out.println("Executing " + joinPoint.getSignature());
    }
}
```

---

### 5. 바이브 코딩을 위한 팁 모음!

1. **테스트를 항상 작게 나누어 진행하세요.**
   - 하나의 작업이 너무 크면 프롬프트를 작성하기 어렵습니다.
   - "핵심" 동작 단위를 나눠 테스트와 로직을 반복적으로 설계하세요.

2. **버그를 디버깅하는 질문 작성법**
   - 버그 증상을 잘 설명하고, 이 증상이 나타나는 조건과 관련 코드를 명확히 작성합니다.
     > 예: "Repository 호출 시 데이터가 저장되지 않습니다. MySQL 트랜잭션 관리에서 오류가 있는 것 같은데, Spring Boot에서 @Transactional 설정 디버깅 방법을 알려주세요."

3. **스프링 공식 문서와 함께 작업**
   - 스프링의 공식 문서를 항상 곁에 두고 "문맥"에 맞는 키워드 질문을 통해 **구체적인 답변**을 받을 수 있습니다.
   - 예: `Spring Data JPA custom repository method`

---

## 💡 배운 점
1. 바이브 코딩 환경에서는 **구체적이고 핵심을 찌르는 질문 작성 능력**이 개발 속도와 코드 품질을 결정합니다.
2. Spring Boot에서 프롬프트 작성 시 **문제 원인, 영향 범위, 요구사항**을 충분히 문서화하면 디버깅 시간과 코드 품질 문제를 크게 줄일 수 있습니다.
3. 정리되지 않은 요청이나 비구체적인 문제 정의는 개발 효율을 낮출 뿐 아니라, 협업 과정에서도 문제를 키울 수 있습니다.

---

## 🔗 참고 자료

- [Spring Boot 공식 문서](https://spring.io/projects/spring-boot)
- [Effective Debug Logging in Spring](https://www.baeldung.com/spring-boot-logging)  