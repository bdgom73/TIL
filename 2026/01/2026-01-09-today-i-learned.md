---
title: "Spring Cloud OpenFeign: RestTemplate 지옥에서 탈출하여 선언적 HTTP 클라이언트 구축하기"
date: 2026-01-09
categories: [Spring, MSA, Network]
tags: [OpenFeign, Spring Cloud, RestTemplate, HTTP Client, MSA, ErrorDecoder, TIL]
excerpt: "MSA 환경에서 다른 마이크로서비스를 호출할 때 발생하는 반복적인 RestTemplate/WebClient 코드를 제거하기 위해 OpenFeign을 도입합니다. 인터페이스 선언만으로 HTTP 요청을 처리하는 방법과, ErrorDecoder를 활용해 외부 API의 에러 응답을 내 서비스의 예외로 우아하게 매핑하는 전략을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Cloud OpenFeign: RestTemplate 지옥에서 탈출하여 선언적 HTTP 클라이언트 구축하기

## 📚 오늘 학습한 내용

외부 API나 내부 마이크로서비스를 호출할 때 `RestTemplate`이나 `WebClient`를 사용하면 URL 생성, 헤더 설정, 바디 변환 등 반복적인 보일러플레이트 코드가 너무 많이 발생합니다. 비즈니스 로직보다 통신 코드가 더 길어지는 주객전도 현상을 해결하기 위해, Netflix가 만들고 Spring Cloud가 채택한 **Declarative(선언적) HTTP Client**인 **OpenFeign**을 적용했습니다.

---

### 1. **OpenFeign이란? 📞**

Spring Data JPA가 인터페이스만으로 DB 쿼리를 수행하듯, **OpenFeign은 인터페이스와 애노테이션만으로 HTTP 요청을 수행**하는 라이브러리입니다.

-   **장점**:
    -   구현체 없이 인터페이스만 작성하면 됨.
    -   Spring MVC 애노테이션(`@GetMapping` 등)을 그대로 재사용 가능.
    -   가독성이 뛰어나고 테스트 Mocking이 쉬움.
-   **주의**: 내부적으로 Reflection과 Proxy를 사용하므로 극강의 성능이 필요한 곳에는 적합하지 않을 수 있음 (WebClient 권장).

---

### 2. **Spring Boot에 적용하기**

#### **Step 1: 의존성 추가 및 활성화**

```groovy
implementation 'org.springframework.cloud:spring-cloud-starter-openfeign'
```

메인 클래스에 `@EnableFeignClients`를 붙여야 스캔이 동작합니다.

```java
@SpringBootApplication
@EnableFeignClients // 필수 설정
public class OrderApplication {
    public static void main(String[] args) {
        SpringApplication.run(OrderApplication.class, args);
    }
}
```

#### **Step 2: Feign Client 인터페이스 작성**

마치 컨트롤러를 짜듯이 인터페이스를 정의합니다.

```java
@FeignClient(name = "product-service", url = "${external.product-api.url}") // Eureka 사용 시 url 생략 가능
public interface ProductClient {

    @GetMapping("/api/products/{id}")
    ProductResponse getProduct(@PathVariable("id") Long id);

    @PostMapping("/api/products/stock/decrease")
    void decreaseStock(@RequestBody StockDecreaseRequest request);
}
```

#### **Step 3: 서비스에서 사용**

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final ProductClient productClient; // 자동 주입됨

    public void createOrder(OrderDto dto) {
        // HTTP 통신 코드가 마치 메서드 호출처럼 깔끔해짐
        ProductResponse product = productClient.getProduct(dto.getProductId());
        // ...
    }
}
```

---

### 3. **심화 1: 공통 헤더 처리 (RequestInterceptor)**

MSA 환경에서는 인증 토큰(JWT)이나 추적 ID(TraceId)를 하위 서비스로 계속 전파해야 합니다. 요청마다 `@RequestHeader`를 붙이는 대신 **Interceptor**를 사용하면 전역적으로 처리할 수 있습니다.

```java
@Configuration
public class FeignConfig {

    @Bean
    public RequestInterceptor requestInterceptor() {
        return requestTemplate -> {
            // 현재 요청의 Authorization 헤더를 가져와서 하위 요청에 그대로 토스
            ServletRequestAttributes attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            if (attributes != null) {
                String token = attributes.getRequest().getHeader("Authorization");
                if (token != null) {
                    requestTemplate.header("Authorization", token);
                }
            }
        };
    }
}
```

---

### 4. **심화 2: 에러 핸들링 (ErrorDecoder)**

Feign은 기본적으로 4xx, 5xx 에러가 발생하면 `FeignException`을 던집니다. 하지만 비즈니스 로직에서는 "상품 없음 Exception"이나 "재고 부족 Exception"처럼 **우리 서비스의 커스텀 예외로 변환**해서 받고 싶을 때가 많습니다.

이때 **`ErrorDecoder`**를 구현하면 상태 코드별로 예외를 매핑할 수 있습니다.

```java
@Slf4j
public class FeignErrorDecoder implements ErrorDecoder {

    @Override
    public Exception decode(String methodKey, Response response) {
        // 응답 바디 읽기 등 상세 로직 생략
        
        switch (response.status()) {
            case 400:
                return new IllegalArgumentException("잘못된 요청입니다.");
            case 404:
                if (methodKey.contains("getProduct")) {
                    return new ProductNotFoundException("상품을 찾을 수 없습니다.");
                }
                break;
            case 500:
                return new RetryableException(...); // 재시도 트리거
            default:
                return new Exception("외부 서비스 오류");
        }
        return new Exception("Generic Error");
    }
}
```

---

## 💡 배운 점

1.  **코드의 응집도 향상**: `RestTemplate`을 쓸 때는 비즈니스 로직 중간에 URL을 조립하고 예외를 `try-catch` 하는 잡음이 섞여 있었는데, Feign을 도입하니 비즈니스 로직이 순수해지고 통신 관심사가 인터페이스로 격리되었습니다.
2.  **타임아웃의 중요성**: Feign의 기본 타임아웃은 꽤 깁니다. 외부 서비스가 응답하지 않을 때 내 스레드가 다 잠식당하지 않으려면 `connectTimeout`과 `readTimeout`을 `application.yml`에서 반드시 짧게(예: 3초) 설정해야 함을 알았습니다.
3.  **로깅 레벨 조정**: 개발 중에는 `feign.logger.level: FULL`로 설정하여 주고받는 HTTP 패킷을 모두 봐야 디버깅이 편하지만, 운영 환경에서는 성능과 개인정보 이슈로 `BASIC`이나 `NONE`으로 낮춰야 한다는 운영 팁을 얻었습니다.

---

## 🔗 참고 자료

-   [Spring Cloud OpenFeign Docs](https://docs.spring.io/spring-cloud-openfeign/docs/current/reference/html/)
-   [Common Feign Configuration (Baeldung)](https://www.baeldung.com/spring-cloud-openfeign)
-   [Handling Feign Exceptions](https://www.baeldung.com/spring-cloud-feign-exception-handling)