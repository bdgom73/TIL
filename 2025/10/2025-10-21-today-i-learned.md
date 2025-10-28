---
title: "Spring Boot의 마법 해부: 나만의 Custom Starter 만들기"
date: 2025-10-21
categories: [Spring, DevOps]
tags: [Spring Boot, AutoConfiguration, Starter, @Conditional, DevOps, TIL]
excerpt: "Spring Boot가 '그냥' 동작하는 원리인 자동 구성(@EnableAutoConfiguration)을 이해하고, 회사 내부의 여러 마이크로서비스에서 공통으로 사용될 로직을 재사용 가능한 'Starter'로 만드는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Boot의 마법 해부: 나만의 Custom Starter 만들기

## 📚 오늘 학습한 내용

우리는 `spring-boot-starter-data-jpa` 의존성을 추가하는 것만으로 `DataSource`나 `EntityManagerFactory` 같은 복잡한 빈들이 자동으로 등록되는 Spring Boot의 마법을 매일 경험하고 있습니다. 오늘은 이 마법의 배후인 **자동 구성(Auto-Configuration)**의 원리를 파헤치고, 한발 더 나아가 우리 회사(혹은 내 개인 프로젝트)의 여러 마이크로서비스에서 공통으로 사용할 기능을 **나만의 Starter**로 만드는 방법을 학습했습니다.

---

### 1. **Spring Boot의 자동 구성은 어떻게 동작하는가? 🔮**

Spring Boot의 핵심은 `@SpringBootApplication` 애노테이션 안에 숨어있는 **`@EnableAutoConfiguration`**입니다.

1.  **`@EnableAutoConfiguration`**: Spring Boot가 시작될 때, 클래스패스에 있는 모든 `spring-boot-autoconfigure.jar` 라이브러리를 스캔합니다.
2.  **구성 파일 로드**: 각 라이브러리의 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` (Spring Boot 3.x 기준, 이전에는 `spring.factories`) 파일을 읽어옵니다. 이 파일에는 수많은 자동 구성 클래스(`...AutoConfiguration`)의 목록이 들어있습니다.
3.  **조건부 빈 등록 (`@ConditionalOn...`)**: Spring Boot는 이 목록의 모든 구성 클래스를 무작정 로드하는 것이 아니라, **`@Conditional`** 애노테이션을 통해 **"조건이 맞을 때만"** 빈을 등록합니다.

    -   **`@ConditionalOnClass(DataSource.class)`**: "클래스패스에 `DataSource` 클래스가 있을 때만 이 설정을 활성화해라." (이것이 `spring-boot-starter-jdbc`를 추가하면 DB 설정이 활성화되는 이유입니다.)
    -   **`@ConditionalOnProperty(name = "logging.level")`**: "application.properties에 `logging.level` 속성이 설정되어 있을 때만 활성화해라."
    -   **`@ConditionalOnMissingBean(ObjectMapper.class)`**: "개발자가 직접 `ObjectMapper` 빈을 등록하지 않았을 경우에만, 우리가 기본 빈을 등록해 주겠다."

---

### 2. **왜 Custom Starter가 필요한가? 🚀**

여러 마이크로서비스를 개발하다 보면, 반복적으로 작성하는 공통 코드가 생깁니다.

-   공통 로깅 모듈 (e.g., Logback 설정 + Slack 연동)
-   공통 보안 설정 (e.g., 사내 JWT 검증 로직)
-   공통 에러 핸들링 로직
-   자주 사용하는 유틸리티 빈 (`RestTemplate`, `ObjectMapper` 커스텀 설정 등)

이러한 코드들을 각 서비스에 복사/붙여넣기 하는 대신, **Custom Starter**로 만들어 의존성 추가 한 번으로 해결할 수 있습니다. 이는 "관심사의 분리(SoC)"와 "관례에 의한 설정(Convention over Configuration)"을 실현하는 스프링 부트다운 방식입니다.

---

### 3. **나만의 Custom Starter 만들기 (단계별)**

사내 모든 서비스에서 공통으로 사용할 `CommonLogService`를 빈으로 등록해주는 `common-logging-starter`를 만들어보겠습니다.

#### **Step 1: 자동 구성(Auto-Configuration) 모듈 생성**
먼저, 실제 빈을 등록하는 로직을 담을 `common-logging-autoconfigure` 모듈을 만듭니다.

**1-1. `CommonLogProperties` (설정 클래스)**
`application.properties`에서 값을 받을 수 있도록 `@ConfigurationProperties`를 만듭니다.

```java
@ConfigurationProperties(prefix = "common.log")
public class CommonLogProperties {
    /**
     * 로그 레벨 (e.g., INFO, DEBUG)
     */
    private String level = "INFO";
    
    // ... getters and setters ...
}
```

**1-2. `CommonLogAutoConfiguration` (자동 구성 클래스)**
핵심 로직입니다. `@Conditional`을 사용하여 빈을 등록합니다.

```java
@Configuration
// "common.log.enabled" 속성이 true일 때만 이 설정을 활성화 (기본값은 true)
@ConditionalOnProperty(name = "common.log.enabled", havingValue = "true", matchIfMissing = true)
// 위에서 만든 Properties 클래스를 빈으로 등록하고 바인딩
@EnableConfigurationProperties(CommonLogProperties.class) 
public class CommonLogAutoConfiguration {

    private final CommonLogProperties properties;

    public CommonLogAutoConfiguration(CommonLogProperties properties) {
        this.properties = properties;
    }

    // 개발자가 CommonLogService 빈을 직접 등록하지 않았을 경우에만
    // 이 기본 빈을 등록한다.
    @Bean
    @ConditionalOnMissingBean 
    public CommonLogService commonLogService() {
        return new CommonLogService(properties.getLevel());
    }
}
```

**1-3. 자동 구성 등록**
Spring Boot가 이 `CommonLogAutoConfiguration`을 인식할 수 있도록 `resources/META-INF/spring/` 경로에 `org.springframework.boot.autoconfigure.AutoConfiguration.imports` 파일을 생성합니다.

```text
# src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports

com.example.common.logging.CommonLogAutoConfiguration
```

#### **Step 2: Starter 모듈 생성**
`common-logging-starter` 모듈을 생성합니다. 이 모듈은 **코드가 없는 껍데기**이며, 오직 의존성을 전파하는 역할만 합니다.

**`build.gradle` (Starter 모듈)**
```groovy
dependencies {
    // 1. 우리가 만든 자동 구성 모듈을 의존성으로 추가
    api 'com.example:common-logging-autoconfigure:1.0.0'
    
    // 2. 이 스타터가 동작하기 위해 필요한 다른 라이브러리 추가 (선택)
    // api 'org.springframework.boot:spring-boot-starter-aop'
}
```

#### **Step 3: 실제 서비스에서 사용하기**
이제 `my-api-service` 프로젝트에서 방금 만든 Starter를 의존성으로 추가합니다.

**`build.gradle` (My Api Service)**
```groovy
dependencies {
    implementation 'com.example:common-logging-starter:1.0.0'
}
```
이제 `my-api-service`를 실행하면, `@EnableAutoConfiguration`이 `common-logging-starter`를 발견하고, `common-logging-autoconfigure`를 로드하여 `CommonLogService` 빈을 자동으로 등록해줍니다!

---

## 💡 배운 점

1.  **Spring Boot의 '마법'은 '약속'이다**: `@ConditionalOn...`과 `META-INF`의 특정 파일을 스캔하는 것은 Spring Boot와 개발자 간의 '약속(Convention)'입니다. 이 약속을 이해함으로써 Spring Boot가 왜 이렇게 동작하는지 명확히 알게 되었고, 문제 발생 시 내부 동작을 추적할 수 있는 자신감을 얻었습니다.
2.  **Starter는 공통 모듈 관리의 정답이다**: 여러 프로젝트에 흩어져 있던 공통 설정과 유틸리티 클래스들을 Starter로 통합함으로써, 중복 코드를 제거하고 모든 서비스의 공통 로직을 한 곳에서 중앙 관리(버전 관리)할 수 있게 되었습니다.
3.  **`@ConditionalOnMissingBean`의 중요성**: 무조건 빈을 등록하는 것이 아니라, `@ConditionalOnMissingBean`을 통해 개발자가 원하면 언제든지 기본 설정을 오버라이드(Override)할 수 있도록 '선택권'을 주는 것이 잘 만든 Starter의 핵심임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Boot Docs - Creating Your Own Auto-configuration](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.developing-auto-configuration)
-   [Conditional Annotations in Spring (Baeldung)](https://www.baeldung.com/spring-conditional-annotations)