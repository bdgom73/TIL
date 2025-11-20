---
title: "Spring Cloud OpenFeign: 선언적 HTTP 클라이언트의 우아함과 실무 튜닝"
date: 2025-11-20
categories: [Spring, MSA]
tags: [OpenFeign, Spring Cloud, HTTP Client, RestTemplate, MSA, Timeout, ErrorDecoder, TIL]
excerpt: "반복적인 RestTemplate 코드를 인터페이스 선언만으로 대체하는 Spring Cloud OpenFeign의 동작 원리를 학습합니다. 실무에서 반드시 설정해야 하는 Timeout, Retry 정책과 ErrorDecoder를 이용한 우아한 예외 처리 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Cloud OpenFeign: 선언적 HTTP 클라이언트의 우아함과 실무 튜닝

## 📚 오늘 학습한 내용

MSA 환경에서 다른 마이크로서비스를 호출할 때, `RestTemplate`이나 `WebClient`를 사용하면 URL을 문자열로 조립하고, HTTP 메서드를 지정하고, 헤더를 설정하는 등 반복적이고 지저분한 보일러플레이트 코드가 발생합니다.

오늘은 이러한 HTTP 통신을 **자바 인터페이스와 애노테이션**만으로 깔끔하게 처리할 수 있게 해주는 **Spring Cloud OpenFeign**에 대해 학습했습니다. 단순히 "사용법"을 넘어, 운영 환경에서 장애를 막기 위한 **필수 튜닝 포인트**들을 정리했습니다.

---

### 1. **OpenFeign이란 무엇인가? 📢**

OpenFeign은 Netflix가 개발하고 현재는 Spring Cloud 팀이 관리하는 **선언적(Declarative) 웹 서비스 클라이언트**입니다.

-   **핵심**: "HTTP 요청을 보내는 클라이언트 코드"를 작성하는 것이 아니라, "호출할 API의 명세(Interface)"를 작성하면, **Spring이 런타임에 프록시 구현체를 만들어 요청을 수행**합니다.
-   **장점**: Spring MVC 애노테이션(`@GetMapping`, `@PathVariable` 등)을 그대로 재사용할 수 있어 러닝 커브가 낮고 코드 가독성이 극대화됩니다.

#### **기본 사용법**

**1. 의존성 추가 & 활성화**
```java
// 메인 클래스에 추가
@EnableFeignClients
@SpringBootApplication
public class MyApplication { ... }
```

**2. 인터페이스 정의**
```java
// 'product-service'라는 이름의 마이크로서비스 호출
@FeignClient(name = "product-service", url = "${external.product-api.url}")
public interface ProductClient {

    @GetMapping("/api/products/{id}")
    ProductDto getProduct(@PathVariable("id") Long id);

    @PostMapping("/api/products")
    void createProduct(@RequestBody ProductCreateRequest request);
}
```
이제 서비스 로직에서는 `ProductClient`를 주입받아 일반 메서드처럼 호출하면 됩니다.

---

### 2. **실무 필수 튜닝 1: Timeout 설정 (가장 중요!) ⏱️**

OpenFeign의 기본 타임아웃 설정은 매우 보수적이거나(짧거나), 반대로 너무 길어서 문제를 일으킬 수 있습니다. 외부 서비스의 지연이 내 서비스의 스레드 고갈(Thread Pool Exhaustion)로 이어지지 않도록 **반드시 명시적으로 설정**해야 합니다.

**`application.yml`**
```yaml
spring:
  cloud:
    openfeign:
      client:
        config:
          default: # 모든 FeignClient에 적용되는 전역 설정
            connectTimeout: 3000 # 연결 타임아웃 (3초)
            readTimeout: 5000    # 읽기 타임아웃 (5초)
            loggerLevel: BASIC   # 로깅 레벨 (NONE, BASIC, HEADERS, FULL)
          
          product-service: # 특정 클라이언트만 별도 설정
            readTimeout: 10000 # 상품 서비스는 좀 더 길게 10초
```
> **주의**: `readTimeout`이 너무 길면, 장애 발생 시 내 서버의 스레드가 오랫동안 블로킹되어 전체 시스템이 느려질 수 있습니다. 서킷 브레이커(Resilience4j)와 함께 사용하여 타임아웃을 이중으로 관리하는 것이 좋습니다.

---

### 3. **실무 필수 튜닝 2: ErrorDecoder를 이용한 예외 매핑 🚨**

Feign은 호출 실패 시 기본적으로 `FeignException`을 던집니다. 하지만 3~4년차 개발자라면, 이를 우리 시스템의 커스텀 예외(e.g., `ProductNotFoundException`)로 변환하여 일관성 있게 처리하고 싶을 것입니다.

**`ErrorDecoder` 구현**
```java
public class FeignErrorDecoder implements ErrorDecoder {

    @Override
    public Exception decode(String methodKey, Response response) {
        int status = response.status();

        if (status == 400) {
            return new InvalidParameterException("잘못된 요청입니다.");
        }
        
        if (status == 404) {
            if (methodKey.contains("getProduct")) {
                return new ProductNotFoundException("상품을 찾을 수 없습니다.");
            }
        }
        
        if (status >= 500) {
            return new RetryableException(
                status, 
                "서버 일시적 장애", 
                response.request().httpMethod(), 
                null, 
                response.request()
            ); // RetryableException을 던지면 Feign이 재시도를 수행함 (설정 필요)
        }

        return new Default().decode(methodKey, response);
    }
}
```
**Bean 등록**
```java
@Configuration
public class FeignConfig {
    @Bean
    public ErrorDecoder errorDecoder() {
        return new FeignErrorDecoder();
    }
}
```
이렇게 하면 외부 API의 404 에러가 내 서비스 내부 로직에서는 `ProductNotFoundException`으로 깔끔하게 처리됩니다. `try-catch`로 `FeignException`을 잡는 지저분한 코드를 없앨 수 있습니다.

---

## 💡 배운 점

1.  **인터페이스가 곧 문서다**: OpenFeign을 사용하면 외부 API 연동 코드가 곧 명세서가 됩니다. 어떤 URL에 어떤 파라미터가 필요한지 한눈에 파악할 수 있어 유지보수성이 크게 향상됩니다.
2.  **결국은 동기(Synchronous) 블로킹이다**: OpenFeign은 편리하지만 기본적으로 **Blocking I/O** 기반입니다. 트래픽이 매우 많은 서비스라면 WebFlux의 `WebClient`를 고려하거나, Feign 내부 통신 라이브러리를 Apache HttpClient 5 등으로 교체하여 Connection Pool을 최적화해야 함을 깨달았습니다.
3.  **장애 격리의 중요성**: `ErrorDecoder`와 타임아웃 설정을 통해 외부 시스템의 에러가 내 시스템의 알 수 없는 500 에러로 전파되는 것을 막고, 의미 있는 비즈니스 예외로 변환하는 것이 안정적인 MSA 운영의 핵심임을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Cloud OpenFeign (Official Docs)](https://docs.spring.io/spring-cloud-openfeign/docs/current/reference/html/)
-   [Spring Cloud Feign Client Configuration (Baeldung)](https://www.baeldung.com/spring-cloud-openfeign)
-   [Feign Error Handling (Reflectoring)](https://reflectoring.io/spring-cloud-feign-error-handling/)