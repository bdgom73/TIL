---
title: "Mockito를 사용한 단위 테스트"
date: 2025-09-18
categories: [테스트]
tags: [JUnit, Mockito, Unit Test, TDD]
excerpt: "Mockito를 이용하여 Java에서 단위 테스트를 작성하고 모의 객체(Mock)를 효과적으로 활용하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Mockito를 사용한 단위 테스트

## 📚 오늘 학습한 내용

### 1. Mockito란?
- **Mockito**는 Java에서 널리 사용되는 테스트 프레임워크로, 객체의 동작을 시뮬레이션할 수 있는 **Mock 객체**를 생성하여 단위 테스트를 지원합니다.
- 실제 객체를 사용하지 않아도 모듈 간 의존성을 분리하여 독립적으로 테스트할 수 있습니다.
- 예를 들어, 데이터베이스 서비스와 같이 실행 속도가 느리거나 분리된 컴포넌트를 Mock으로 대체합니다.

---

### 2. Mockito 주요 기능

1. **모의 객체(Mock) 생성**
    - `@Mock`: Mock 객체를 생성합니다.
    - `when()`: Mock 객체의 행위를 지정합니다.

2. **행위 검증**
    - `verify()`: 메서드가 지정된 횟수만큼 호출되었는지 검증합니다.

3. **Stub 생성**
    - 주어진 조건에서 반환값을 설정하여 다양한 테스트 시나리오를 구현합니다.

4. **ArgumentCaptor를 활용한 인자 캡처**
    - 메서드 호출 시 전달된 매개변수를 검증할 때 사용합니다.

> 예: HTTP 요청을 보내는 객체 대신 Mock으로 대체하여 테스트 중 네트워크 호출을 제거합니다.

---

### 3. `Mockito`와 JUnit 5 통합 사용

**기본 설정**
- `Mockito` 사용 시 Gradle에 아래 의존성을 포함합니다:

```groovy
dependencies {
    testImplementation 'org.mockito:mockito-core:5.6.0'
    testImplementation 'org.mockito:mockito-junit-jupiter:5.6.0'
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.0'
}
```

---

## 💻 코드 예시

아래는 `UserService`와 `UserRepository` 간 의존성을 Mock으로 처리하는 예제입니다.

### 테스트 대상 클래스

```java
public class UserService {
    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public User findUserByEmail(String email) {
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found"));
    }
}
```

### 테스트 코드

```java
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class UserServiceTest {

    @Test
    void testFindUserByEmail_Success() {
        // Mock 객체 생성
        UserRepository mockRepository = mock(UserRepository.class);

        // Stub 설정
        User mockUser = new User("test@example.com", "Test User");
        when(mockRepository.findByEmail("test@example.com"))
                .thenReturn(Optional.of(mockUser));

        UserService userService = new UserService(mockRepository);

        // 실행 및 결과 검증
        User result = userService.findUserByEmail("test@example.com");
        assertNotNull(result);
        assertEquals("Test User", result.getName());

        // 행위 검증
        verify(mockRepository, times(1)).findByEmail("test@example.com");
    }

    @Test
    void testFindUserByEmail_UserNotFound() {
        // Mock 객체 생성
        UserRepository mockRepository = mock(UserRepository.class);

        // Stub 설정
        when(mockRepository.findByEmail("test@example.com"))
                .thenReturn(Optional.empty());

        UserService userService = new UserService(mockRepository);

        // 예외 검증
        RuntimeException exception = assertThrows(RuntimeException.class, () ->
                userService.findUserByEmail("test@example.com")
        );
        assertEquals("User not found", exception.getMessage());
    }
}
```

---

### 예제 설명
1. **Stub 생성**  
   `when(mockRepository.findByEmail("test@example.com"))`은 특정 상황에서 반환값을 설정합니다.

2. **행위 검증**  
   `verify(mockRepository, times(1)).findByEmail("test@example.com")`을 통해 메서드 호출 횟수를 확인했습니다.

3. **예외 상황 테스트**  
   유저가 없는 경우 예외가 발생하도록 설계하고, 테스트에서 이를 검증했습니다.

---

## 🔍 문제 상황 및 해결 과정

### 문제 상황
- 다른 서비스나 DB와 상호작용하는 클래스는 테스트의 복잡도를 높였습니다.
- 실제 데이터베이스를 연결하여 테스트를 수행하는 경우, 속도가 느리고 외부 환경에 영향을 받을 수 있는 문제가 있었습니다.

### 해결 과정
- 의존성을 **Mockito** Mock 객체로 대체하여 독립적으로 서비스를 검증했습니다.
- 반환값 및 메서드 호출을 시뮬레이션함으로써 외부 환경과 분리된 테스트를 구현했습니다.

---

## 💡 배운 점

- Mockito를 통해 의존성을 Mock으로 처리하고 독립적인 단위 테스트를 작성할 수 있었습니다.
- 실제 객체 대신 Mock을 이용하면 실행 속도와 유연성을 크게 향상할 수 있습니다.
- 행위 검증 및 다양한 예외 상황을 테스트하기에 효과적이었습니다.

---

## 🔗 참고 자료

- [Mockito Official Documentation](https://javadoc.io/doc/org.mockito/mockito-core/latest/index.html)
- [JUnit 5 User Guide](https://junit.org/junit5/docs/current/user-guide/)

