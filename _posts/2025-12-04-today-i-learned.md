---
title: "Spring Security의 필터 체인(Filter Chain) 커스터마이징과 디버깅"
date: 2025-12-04
categories: [Spring, Security]
tags: [Spring Security, Filter Chain, DelegatingFilterProxy, SecurityFilterChain, Debugging, TIL]
excerpt: "Spring Security의 핵심인 필터 체인의 동작 원리를 DelegatingFilterProxy와 FilterChainProxy의 관계를 통해 심층적으로 이해합니다. 커스텀 필터의 올바른 등록 위치 선정 방법과 필터 체인 전체를 시각화하여 디버깅하는 노하우를 학습합니다."
author_profile: true
---

# Today I Learned: Spring Security의 필터 체인(Filter Chain) 커스터마이징과 디버깅

## 📚 오늘 학습한 내용

Spring Security를 사용하면서 `UsernamePasswordAuthenticationFilter` 이전에 커스텀 인증 필터를 넣거나, JWT 검증 필터를 추가하는 작업은 종종 해왔습니다. 하지만 "도대체 이 수많은 필터들은 어떤 순서로 실행되는 것이며, 내 필터는 정확히 어디에 껴야 안전한가?"에 대한 명확한 확신이 부족했습니다.

오늘은 Spring Security의 **필터 체인(Filter Chain)** 아키텍처를 해부하고, 복잡한 필터 순서를 눈으로 확인하며 디버깅하는 방법에 대해 학습했습니다.

---

### 1. **Spring Security의 진입점: 서블릿 필터와 스프링 빈의 만남 🌉**

Spring Security는 서블릿 컨테이너(Tomcat)의 필터 기반 위에서 동작하지만, 실제 보안 로직은 스프링 빈(Bean)으로 관리됩니다. 이 둘을 연결하는 것이 핵심입니다.

1.  **`DelegatingFilterProxy`**: 서블릿 컨테이너에 등록되는 표준 서블릿 필터입니다. 스스로 보안 로직을 수행하지 않고, 스프링 컨텍스트에서 `springSecurityFilterChain`이라는 이름의 빈을 찾아 요청을 **위임(Delegate)**합니다.
2.  **`FilterChainProxy`**: 위임을 받는 스프링 빈입니다. 실제 보안 필터 체인(`SecurityFilterChain`) 목록을 관리하고, 요청 URL에 맞는 체인을 선택하여 실행시키는 **보안의 중추**입니다.
3.  **`SecurityFilterChain`**: `SecurityConfig`에서 우리가 설정한(`http.build()`) 결과물입니다. `CsrfFilter`, `UsernamePasswordAuthenticationFilter` 등 실제 보안 로직을 담은 필터들의 리스트를 가지고 있습니다.

---

### 2. **필터 순서의 중요성과 커스텀 필터 배치 🚦**

Spring Security는 약 30개 이상의 기본 필터를 제공하며, 이들은 엄격한 순서를 가집니다. 커스텀 필터를 등록할 때는 `addFilterBefore`, `addFilterAfter`, `addFilterAt`을 사용하여 기준 필터를 명시해야 합니다.

#### **주요 필터 순서 (앞에서 뒤로)**
1.  **`DisableEncodeUrlFilter`**: URL 인코딩 방지
2.  **`WebAsyncManagerIntegrationFilter`**: 비동기 처리 컨텍스트 통합
3.  **`SecurityContextHolderFilter`**: (구 `SecurityContextPersistenceFilter`) `SecurityContext`를 로드/저장
4.  **`HeaderWriterFilter`**: 보안 관련 응답 헤더 추가 (X-Frame-Options 등)
5.  **`CsrfFilter`**: CSRF 공격 방어
6.  **`LogoutFilter`**: 로그아웃 처리
7.  **`UsernamePasswordAuthenticationFilter`**: 폼 로그인 인증 처리 (POST /login)
8.  **`DefaultLoginPageGeneratingFilter`**: 기본 로그인 페이지 생성
9.  **`BearerTokenAuthenticationFilter`**: (OAuth2 Resource Server) JWT 토큰 인증
10. **`BasicAuthenticationFilter`**: HTTP Basic 인증
11. **`ExceptionTranslationFilter`**: 인증/인가 예외(`AccessDeniedException` 등)를 잡아 처리 (로그인 페이지 리다이렉트 등)
12. **`AuthorizationFilter`**: (구 `FilterSecurityInterceptor`) 최종 접근 권한(인가) 검사

#### **실전 적용: JWT 필터는 어디에?**
JWT 인증 필터는 보통 **`UsernamePasswordAuthenticationFilter` 이전**에 배치합니다.
```java
http.addFilterBefore(new JwtAuthenticationFilter(jwtProvider), UsernamePasswordAuthenticationFilter.class);
```
-   **이유**: 폼 로그인 로직이 실행되기 전에 토큰을 검사하여, 유효한 토큰이 있다면 굳이 폼 로그인 필터를 거치지 않고 인증된 상태(`SecurityContext`)를 만들어주기 위함입니다.

---

### 3. **필터 체인 눈으로 확인하기 (디버깅 꿀팁) 🐞**

"내 필터가 제대로 등록되었나?", "어떤 필터들이 활성화되어 있나?" 궁금할 때 사용하는 방법입니다.

#### **방법 1: `logging.level` 설정**
`application.yml`에 보안 로그 레벨을 `DEBUG`로 설정하면, 요청이 들어올 때마다 **실행되는 필터 목록**이 로그에 출력됩니다.

```yaml
logging:
  level:
    org.springframework.security: DEBUG
```
**출력 예시:**
```text
DEBUG ... Security filter chain: [
  DisableEncodeUrlFilter,
  WebAsyncManagerIntegrationFilter,
  SecurityContextHolderFilter,
  HeaderWriterFilter,
  CorsFilter,
  LogoutFilter,
  JwtAuthenticationFilter,  <-- 내가 등록한 필터 확인!
  RequestCacheAwareFilter,
  SecurityContextHolderAwareRequestFilter,
  AnonymousAuthenticationFilter,
  SessionManagementFilter,
  ExceptionTranslationFilter,
  AuthorizationFilter
]
```

#### **방법 2: `@EnableWebSecurity(debug = true)`**
개발 환경에서만 사용해야 합니다. 요청마다 필터 체인 정보와 세션 정보를 콘솔에 아주 상세하게 출력해줍니다.

```java
@Configuration
@EnableWebSecurity(debug = true) // 디버그 모드 활성화
public class SecurityConfig { ... }
```

---

## 💡 배운 점

1.  **필터의 위치가 동작을 결정한다**: `ExceptionTranslationFilter` 뒤에 위치한 필터에서 발생한 예외는 Spring Security가 처리해주지 않는다는 점을 깨달았습니다. (예외 처리가 안 되어서 500 에러가 났던 경험의 원인) 커스텀 필터에서 발생한 예외를 핸들링하려면, 그보다 앞단에 예외 처리용 필터를 두거나 `ExceptionTranslationFilter`의 동작 방식을 이해하고 활용해야 합니다.
2.  **`DelegatingFilterProxy`의 위임 패턴**: 서블릿 컨테이너와 스프링 컨테이너 사이의 경계를 넘나드는 이 패턴이 Spring Security의 유연성(빈 주입, AOP 적용 등)을 가능하게 한다는 아키텍처적 통찰을 얻었습니다.
3.  **로그는 최고의 문서다**: 막연하게 구글링으로 필터 순서를 찾는 것보다, `DEBUG` 로그 한 번 찍어보는 것이 내 프로젝트에 적용된 정확한 보안 구성을 파악하는 가장 빠른 길임을 다시 한번 느꼈습니다.

---

## 🔗 참고 자료

-   [Spring Security Reference - Architecture](https://docs.spring.io/spring-security/reference/servlet/architecture.html)
-   [Spring Security Filters Order](https://docs.spring.io/spring-security/reference/servlet/architecture.html#servlet-security-filters)
-   [Debugging Spring Security (Baeldung)](https://www.baeldung.com/spring-security-debug)