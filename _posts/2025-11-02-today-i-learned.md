---
title: "Spring Security와 CORS: 브라우저가 'Access-Control-Allow-Origin'을 요청하는 이유"
date: 2025-11-02
categories: [Spring, Security]
tags: [Spring Security, CORS, SOP, Web, Security, TIL]
excerpt: "Postman에서는 잘 되던 API가 브라우저에서만 실패하는 이유, CORS(Cross-Origin Resource Sharing) 에러의 근본 원인인 SOP(Same-Origin Policy)를 이해하고, Spring Security를 통해 전역적으로 CORS를 안전하게 설정하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Security와 CORS: 브라우저가 'Access-Control-Allow-Origin'을 요청하는 이유

## 📚 오늘 학습한 내용

3~4년차 개발자로 일하면서 가장 당혹스러운 순간 중 하나는, Postman이나 `curl`로 테스트할 때는 완벽하게 동작하던 API가 프론트엔드(React, Vue 등)와 연동하자마자 브라우저 콘솔에 **`Access-Control-Allow-Origin`** 에러를 뿜어내며 실패하는 순간입니다.

오늘은 이 문제가 Spring Boot의 버그가 아니라 **브라우저의 핵심 보안 정책** 때문에 발생한다는 것을 명확히 이해하고, `@CrossOrigin` 애노테이션을 남발하는 대신 Spring Security를 통해 중앙에서 우아하게 처리하는 방법을 학습했습니다.

---

### 1. **모든 문제의 근원: SOP (Same-Origin Policy)**

CORS 에러를 이해하려면 **SOP(동일 출처 정책)**를 먼저 알아야 합니다.

-   **SOP란?**: "한 출처(Origin)에서 로드된 문서나 스크립트는 다른 출처의 리소스와 상호작용할 수 없다"는 브라우저의 근본적인 보안 정책입니다.
-   **출처(Origin)란?**: `Protocol` (http, https) + `Host` (domain) + `Port` (포트 번호) 세 가지가 모두 같아야 '동일 출처'입니다.

| URL | 비교 대상 (`http://api.myservice.com:8080`) | 동일 출처 여부 |
| :--- | :--- | :--- |
| `http://api.myservice.com:8080/users` | (모두 동일) | **O** |
| `https://api.myservice.com:8080` | `https` (프로토콜 다름) | **X** |
| `http://www.myservice.com:8080` | `www.myservice.com` (호스트 다름) | **X** |
| `http://api.myservice.com:3000` | `3000` (포트 다름) | **X** |

우리가 개발 환경에서 겪는 `http://localhost:3000` (프론트엔드)와 `http://localhost:8080` (백엔드)는 포트가 다르므로 **명백히 다른 출처(Cross-Origin)**입니다.

-   **왜 필요한가?**: 만약 SOP가 없다면, 우리가 `mybank.com`에 로그인한 상태에서 악의적인 `evil.com`에 접속했을 때, `evil.com`의 스크립트가 `mybank.com`의 API를 마음대로 호출하여 우리 계좌 정보를 탈취할 수 있습니다. SOP는 이를 원천적으로 차단합니다.

---

### 2. **CORS: SOP를 넘어서는 협상의 기술**

**CORS(Cross-Origin Resource Sharing)**는 이 엄격한 SOP 정책에 대한 예외를 허용해주는 **서버와 브라우저 간의 협상 메커니즘**입니다. "다른 출처라도, 내가 허락한 애들은 괜찮아"라고 서버가 명시적으로 알려주는 방식입니다.

#### **Preflight Request (사전 요청)**
브라우저는 '위험한' 요청(e.g., `POST`, `PUT`, `DELETE` 또는 `Authorization` 헤더가 포함된 요청)을 보내기 전에, 먼저 **`OPTIONS`** 메서드로 서버에 "사전 요청(Preflight)"을 보냅니다.

> **브라우저(localhost:3000) ➡️ 서버(localhost:8080)**
>
> **[OPTIONS /api/users]**
> "안녕, 나 `localhost:3000`인데, 혹시 `POST` 메서드랑 `Authorization` 헤더 써서 요청 보내도 돼?"

이때 서버는 이 `OPTIONS` 요청에 대한 응답 헤더에 "허가증"을 실어 보내야 합니다.

> **서버(localhost:8080) ➡️ 브라우저(localhost:3000)**
>
> **[HTTP/1.1 200 OK]**
> `Access-Control-Allow-Origin: http://localhost:3000` (너는 허용해줄게)
> `Access-Control-Allow-Methods: GET, POST, OPTIONS` (이 메서드들만 써)
> `Access-Control-Allow-Headers: Authorization, Content-Type` (이 헤더들도 허용)

브라우저가 이 '허가증'을 확인하고 만족하면, 그제서야 **본 요청(Actual Request)**인 `POST /api/users`를 보냅니다. Postman은 브라우저가 아니므로 SOP/CORS 정책을 따르지 않아 이 과정이 없는 것입니다.

---

### 3. **Spring Security로 전역 CORS 설정하기 (Best Practice)**

컨트롤러마다 `@CrossOrigin` 애노테이션을 붙이는 것은 반복적이고 관리하기 어렵습니다. Spring Security를 사용하면 **보안 필터 체인** 레벨에서 모든 CORS 정책을 중앙 관리할 수 있습니다.

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // 1. (가장 중요) CORS 설정을 SecurityFilterChain에 적용
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            
            // 2. CSRF는 STATELESS 환경(JWT 등)에서는 비활성화
            .csrf(AbstractHttpConfigurer::disable)
            
            .authorizeHttpRequests(auth -> auth
                // OPTIONS 메서드는 Preflight 요청이므로 인증 없이 모두 허용
                // .cors() 설정 시 Spring Security가 알아서 처리해줌
                .requestMatchers(HttpMethod.OPTIONS).permitAll() 
                .anyRequest().authenticated()
            );
        
        return http.build();
    }

    /**
     * CorsConfigurationSource 빈을 등록하여 CORS 정책을 전역적으로 설정
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();

        // 1. 자격 증명(쿠키, 인증 헤더) 허용 여부
        config.setAllowCredentials(true); 
        
        // 2. 허용할 출처(Origin) 설정
        config.setAllowedOrigins(List.of("http://localhost:3000", "https://my-frontend.com"));
        
        // 3. 허용할 HTTP 메서드 설정
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        
        // 4. 허용할 HTTP 헤더 설정
        config.setAllowedHeaders(List.of("*"));
        
        // (선택) 브라우저에 노출할 헤더 설정 (e.g., 커스텀 JWT 헤더)
        config.setExposedHeaders(List.of("Authorization-Token"));

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        // 5. 모든 경로("/**")에 대해 위에서 정의한 config 적용
        source.registerCorsConfiguration("/**", config); 
        
        return source;
    }
}
```

---

## 💡 배운 점

1.  **CORS 에러는 브라우저의 열일이다**: CORS 에러는 서버의 버그가 아니라, SOP 정책을 기반으로 브라우저가 우리의 애플리케이션을 보호하기 위해 "성공적으로" 차단한 결과임을 이해했습니다.
2.  **`OPTIONS` 요청을 잊지 말자**: API가 실패할 때, Postman으로 `POST`만 테스트할 것이 아니라 `OPTIONS` 메서드로도 요청을 보내 서버가 올바른 `Access-Control-*` 헤더를 응답하는지 확인하는 디버깅 습관이 필요합니다.
3.  **설정은 중앙에서 관리해야 한다**: `@CrossOrigin`을 컨트롤러마다 사용하는 것은 편리하지만, 허용할 Origin이나 Method 정책이 변경될 때마다 모든 코드를 수정해야 합니다. 3~4년차 개발자로서, `SecurityFilterChain`에 `CorsConfigurationSource` 빈을 등록하여 보안 정책과 함께 중앙에서 관리하는 것이 장기적으로 훨씬 유지보수하기 좋은 구조임을 깨달았습니다.

---

## 🔗 참고 자료

-   [MDN - Cross-Origin Resource Sharing (CORS)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
-   [Spring Security - CORS Support](https://docs.spring.io/spring-security/reference/servlet/integrations/cors.html)
-   [SOP (Same-Origin Policy) (MDN)](https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy)