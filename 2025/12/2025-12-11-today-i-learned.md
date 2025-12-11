---
title: "Spring Boot에서 Jackson ObjectMapper 완벽 제어하기: 커스텀 Serializer와 모듈 설정"
date: 2025-12-11
categories: [Java, Spring, Library]
tags: [Jackson, ObjectMapper, JSON, Serialization, Spring Boot, Custom Serializer, Masking, TIL]
excerpt: "Spring Boot의 기본 JSON 라이브러리인 Jackson을 프로젝트 표준에 맞게 커스터마이징하는 방법을 학습합니다. 전역 설정(Global Configuration) 방법과 개인정보 마스킹을 위한 커스텀 Serializer 구현, 그리고 @JsonComponent를 활용한 간편한 등록법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot에서 Jackson ObjectMapper 완벽 제어하기: 커스텀 Serializer와 모듈 설정

## 📚 오늘 학습한 내용

API를 개발하다 보면 외부 시스템과 연동하거나, 보안 요구사항(개인정보 마스킹)을 맞추기 위해 JSON 변환 로직을 커스터마이징해야 할 때가 많습니다. 단순히 DTO마다 `@JsonProperty`나 `@JsonFormat`을 덕지덕지 붙이는 것은 유지보수하기 힘듭니다.

오늘은 Spring Boot의 핵심 JSON 처리기인 **Jackson ObjectMapper**를 전역적으로 설정하고, **Custom Serializer**를 통해 특정 타입의 변환 로직(마스킹 등)을 중앙에서 관리하는 방법을 학습했습니다.

---

### 1. **ObjectMapper 전역 설정: `Jackson2ObjectMapperBuilderCustomizer`**

`application.yml`에서 `spring.jackson.*` 프로퍼티로 설정하는 것은 한계가 있습니다. Java Config를 통해 더 세밀하게 제어할 수 있습니다.

**`JacksonConfig.java`**
```java
@Configuration
public class JacksonConfig {

    @Bean
    public Jackson2ObjectMapperBuilderCustomizer jsonCustomizer() {
        return builder -> builder
                // 1. 알 수 없는 필드가 와도 에러 내지 않기 (유연성)
                .featuresToDisable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                
                // 2. Date를 Timestamp(숫자)가 아닌 ISO-8601 문자열로 직렬화
                .featuresToDisable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
                
                // 3. Snake Case 전략 설정 (외부 API 스펙에 따라)
                // .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
                
                // 4. TimeZone 설정
                .timeZone(TimeZone.getTimeZone("Asia/Seoul"))
                
                // 5. 모듈 등록 (Java 8 Time, Kotlin 등)
                .modules(new JavaTimeModule());
    }
}
```

---

### 2. **민감 정보 마스킹을 위한 Custom Serializer**

"모든 응답에서 전화번호의 가운데 자리는 마스킹(`010-****-1234`)해서 내려주세요"라는 요구사항이 왔을 때, 모든 DTO의 Getter를 수정하는 것은 비효율적입니다. Jackson의 **Custom Serializer**를 사용하면 이를 우아하게 해결할 수 있습니다.

#### **Step 1: 마스킹용 애노테이션 정의**
```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
@JacksonAnnotationsInside // Jackson 애노테이션들을 메타 애노테이션으로 묶음
@JsonSerialize(using = PhoneNumberMaskingSerializer.class) // 이 시리얼라이저를 사용해라
public @interface MaskedPhoneNumber {
}
```

#### **Step 2: Serializer 구현**
```java
public class PhoneNumberMaskingSerializer extends JsonSerializer<String> {

    @Override
    public void serialize(String value, JsonGenerator gen, SerializerProvider serializers) throws IOException {
        if (value == null) {
            gen.writeNull();
            return;
        }
        // 마스킹 로직 (예시: 정규식 사용)
        String maskedValue = value.replaceAll("(\\d{3})-(\\d{4})-(\\d{4})", "$1-****-$3");
        gen.writeString(maskedValue);
    }
}
```

#### **Step 3: DTO에 적용**
```java
public class UserDto {
    private String name;

    @MaskedPhoneNumber // 이제 이 필드는 자동으로 마스킹되어 나감
    private String phoneNumber;
}
```

---

### 3. **Spring Boot의 마법: `@JsonComponent`**

커스텀 Serializer/Deserializer를 만들었다면, 보통은 이를 `SimpleModule`에 담아 `ObjectMapper`에 등록하는 과정이 필요합니다. 하지만 Spring Boot는 **`@JsonComponent`** 애노테이션을 제공하여, 이 클래스를 빈으로 등록하기만 하면 **자동으로 ObjectMapper에 스캔되어 등록**되게 해줍니다.

**특정 타입(e.g., `Money` 객체) 전체에 적용하고 싶을 때 유용합니다.**

```java
@JsonComponent // Spring Boot가 자동으로 감지하여 등록함
public class MoneySerializer extends JsonSerializer<Money> {

    @Override
    public void serialize(Money value, JsonGenerator gen, SerializerProvider serializers) throws IOException {
        // Money 객체(BigDecimal amount, Currency currency)를
        // "1,000 KRW" 형태의 문자열로 변환하여 출력
        gen.writeString(String.format("%,.0f %s", value.getAmount(), value.getCurrency()));
    }
}
```
이제 프로젝트 내의 모든 `Money` 타입 필드는 별도의 애노테이션 없이도 위 로직대로 직렬화됩니다.

---

## 💡 배운 점

1.  **DTO 오염 방지**: 화면 출력 포맷팅(Formatting) 로직을 DTO 내부의 Getter나 서비스 레이어에 두지 않고, JSON 변환 계층(Presentation Layer의 경계)으로 격리함으로써 도메인 로직을 순수하게 유지할 수 있음을 깨달았습니다.
2.  **`@JsonComponent`의 편리함**: `SimpleModule`을 직접 등록하는 번거로움 없이, 컴포넌트 스캔만으로 커스텀 변환 로직을 전역에 적용할 수 있는 Spring Boot의 편의 기능이 매우 강력함을 느꼈습니다.
3.  **일관성 있는 API**: 날짜 포맷이나 Null 처리 정책 등을 `ObjectMapper` 설정 한 곳에서 관리함으로써, API 전체의 응답 포맷 일관성을 손쉽게 보장할 수 있습니다.

---

## 🔗 참고 자료

-   [Spring Boot Docs - JSON Support](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.json)
-   [Jackson Custom Serialization (Baeldung)](https://www.baeldung.com/jackson-custom-serialization)
-   [Spring Boot @JsonComponent](https://www.baeldung.com/spring-boot-jsoncomponent)