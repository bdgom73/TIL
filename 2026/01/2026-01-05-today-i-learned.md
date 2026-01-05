---
title: "Spring Security: 커스텀 필터(Filter)가 두 번 실행되는 이유와 해결 방법"
date: 2026-01-05
categories: [Spring, Security]
tags: [Spring Security, Filter Chain, OncePerRequestFilter, DelegatingFilterProxy, TroubleShooting, TIL]
excerpt: "Spring Security에 JWT 인증 필터나 로깅 필터를 추가했을 때, 예상과 달리 필터가 두 번씩 실행되는 현상의 원인을 파악합니다. Servlet Context와 Application Context의 필터 등록 메커니즘 차이를 이해하고, @Component와 SecurityConfig 설정 간의 간섭을 피하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Security: 커스텀 필터(Filter)가 두 번 실행되는 이유와 해결 방법

## 📚 오늘 학습한 내용

Spring Security를 이용하여 JWT 인증 로직을 구현하던 중, 로그가 두 번씩 찍히는 기이한 현상을 발견했습니다. 처음에는 `OncePerRequestFilter`를 상속받았으니 당연히 한 번만 실행될 것이라 생각했지만, Spring Boot의 자동 설정 메커니즘을 간과한 것이 원인이었습니다.

오늘은 Spring Security의 **Filter Chain** 구조와, 커스텀 필터를 빈(Bean)으로 등록할 때 발생하는 **중복 등록 이슈**, 그리고 이를 해결하는 올바른 설정을 정리했습니다.

---

### 1. **문제 상황: 필터의 중복 실행 🔄**

JWT 토큰을 검증하기 위해 `JwtAuthenticationFilter`를 만들고 `@Component`로 등록한 뒤, `SecurityConfig`에도 추가했습니다.

**JwtAuthenticationFilter.java**
```java
@Component // 1. 스프링 빈으로 등록
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(...) {
        log.info("JWT Filter Executed"); // 이 로그가 요청마다 2번 찍힘
        // ... 인증 로직 ...
    }
}
```

**SecurityConfig.java**
```java
@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter; // 주입 받음

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(...)
            // 2. 시큐리티 필터 체인에 추가
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
}
```

---

### 2. **원인 분석: 서블릿 컨테이너 vs 시큐리티 체인**

이 현상의 원인은 Spring Boot가 **`@Component`로 등록된 모든 `Filter` 타입의 빈을 자동으로 서블릿 컨테이너의 필터로 등록**하기 때문입니다.



1.  **실행 1 (General Filter)**: `@Component` 때문에 Spring Boot가 이를 감지하여 일반 서블릿 필터(Global Filter)로 등록합니다. (모든 요청에 대해 실행됨)
2.  **실행 2 (Security Filter)**: `SecurityConfig`에서 `.addFilterBefore()`를 했기 때문에, Spring Security의 `FilterChainProxy` 내부에서도 실행됩니다.

결과적으로 하나의 요청이 들어오면 **서블릿 필터 단계에서 한 번, 시큐리티 체인 내부에서 또 한 번** 실행되는 것입니다. `OncePerRequestFilter`는 "한 요청 내에서 동일한 필터 체인을 탈 때" 중복을 막아주지만, 등록된 경로가 아예 다르면(서블릿 레벨 vs 시큐리티 레벨) 막지 못하는 경우가 있습니다.

---

### 3. **해결 방법**

#### **방법 1: `@Component` 제거 (권장)**

필터를 스프링 빈으로 컴포넌트 스캔하지 않고, `SecurityConfig` 내부에서 직접 생성하여 등록합니다. 만약 필터 내부에서 다른 Service 빈을 주입받아야 한다면, Config 클래스에서 주입받아 생성자로 넘겨주면 됩니다.

```java
// @Component 제거
public class JwtAuthenticationFilter extends OncePerRequestFilter { ... }

@Configuration
public class SecurityConfig {
    
    private final JwtProvider jwtProvider; // 필요한 의존성은 여기서 주입

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        // 직접 new로 생성
        JwtAuthenticationFilter jwtFilter = new JwtAuthenticationFilter(jwtProvider);
        
        http.addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
}
```

#### **방법 2: `FilterRegistrationBean` 사용**

만약 필터를 반드시 빈으로 등록해야 한다면(AOP 적용 등), `FilterRegistrationBean`을 사용하여 **서블릿 컨테이너 자동 등록을 비활성화**해야 합니다.

```java
@Configuration
public class FilterConfig {

    @Bean
    public FilterRegistrationBean<JwtAuthenticationFilter> registration(JwtAuthenticationFilter filter) {
        FilterRegistrationBean<JwtAuthenticationFilter> registration = new FilterRegistrationBean<>(filter);
        // 서블릿 컨테이너의 필터로는 등록하지 않음 (SecurityConfig에서만 쓰겠다)
        registration.setEnabled(false); 
        return registration;
    }
}
```

---

### 4. **심화: DelegatingFilterProxy의 역할**

Spring Security는 톰캣 같은 WAS 입장에서는 단 하나의 필터(`DelegatingFilterProxy`)일 뿐입니다.
-   요청 -> `DelegatingFilterProxy` -> `FilterChainProxy` -> `SecurityFilterChain` (여기에 우리가 추가한 필터들이 있음)

우리가 만든 커스텀 필터는 **Spring Security의 관리 하에 있을 때(SecurityContext 접근 등)** 가장 안전하고 의도대로 동작합니다. 따라서 일반 서블릿 필터로 빠져나가지 않도록 설정하는 것이 중요합니다.

---

## 💡 배운 점

1.  **편리함의 이면**: Spring Boot의 Auto Configuration은 매우 편리하지만, "모든 Filter 빈을 자동 등록한다"는 동작 방식을 모르면 이런 중복 실행 이슈에 빠질 수 있음을 깨달았습니다.
2.  **명시적 구성의 중요성**: 보안과 관련된 컴포넌트는 `@Component`로 암묵적으로 등록하기보다, Security 설정 클래스 내에서 명시적으로 생성하고 조립하는 것이 가독성과 제어 측면에서 훨씬 낫다는 것을 알게 되었습니다.
3.  **로그의 생활화**: "당연히 되겠지"라고 넘기지 않고 로그를 확인했기에 망정이지, 만약 DB 조회 로직이 있는 필터였다면 쿼리가 2배로 나가는 성능 문제를 방치할 뻔했습니다.

---

## 🔗 참고 자료

-   [Spring Security Architecture (Filters)](https://docs.spring.io/spring-security/reference/servlet/architecture.html#servlet-filters-review)
-   [Spring Boot Filter Registration](https://docs.spring.io/spring-boot/docs/current/reference/html/application-properties.html#server.servlet.context-path)
-   [Troubleshooting Duplicate Filter Execution](https://www.baeldung.com/spring-boot-add-filter)