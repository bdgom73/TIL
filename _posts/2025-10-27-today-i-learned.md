---
title: "Spring Boot의 심장, HikariCP: 커넥션 풀(Connection Pool)의 동작 원리"
date: 2025-10-27
categories: [Spring, Database]
tags: [HikariCP, Connection Pool, JDBC, Spring Boot, Performance, TIL]
excerpt: "Spring Boot 애플리케이션의 데이터베이스 성능을 좌우하는 HikariCP(히카리CP) 커넥션 풀의 동작 원리를 학습합니다. 'connection.close()'의 진정한 의미와 3-4년차 개발자가 알아야 할 핵심 튜닝 옵션을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot의 심장, HikariCP: 커넥션 풀(Connection Pool)의 동작 원리

## 📚 오늘 학습한 내용

`spring-boot-starter-data-jpa`나 `spring-boot-starter-jdbc`를 의존성에 추가하면, Spring Boot는 자동으로 **HikariCP**라는 커넥션 풀을 구성해줍니다. 저는 3년 넘게 이 편리함 속에서 `DataSource`를 당연하게 주입받아 사용해왔습니다.

하지만 "왜 DB 커넥션을 직접 만들지 않고 풀(Pool)을 쓸까?", "HikariCP는 왜 이렇게 빠르다고 소문이 났을까?", "그래서 `connection.close()`를 호출하면 정말 닫히는 걸까?"라는 근본적인 질문에 답하기 위해 오늘 커넥션 풀의 내부 동작 원리를 깊이 있게 학습했습니다.

---

### 1. **커넥션 풀은 왜 필요한가? 🚗 (feat. 렌터카 업체)**

데이터베이스 커넥션을 맺는 과정은 생각보다 훨씬 비싼 작업입니다.

1.  **TCP/IP Handshake**: 애플리케이션 서버와 DB 서버 간의 네트워크 연결 수립.
2.  **DB 인증**: 사용자 아이디, 비밀번호, 스키마 정보 등을 확인하는 인증 절차.
3.  **세션 생성**: DB가 이 커넥션을 위한 메모리 공간과 세션을 준비.

만약 사용자의 모든 요청마다 이 과정을 반복한다면, 애플리케이션은 응답 속도가 느려 터져 아무도 사용할 수 없을 것입니다.

**커넥션 풀(Connection Pool)**은 이 문제를 해결합니다.
-   **비유**: 필요할 때마다 차를 직접 조립해서 타는(비쌈, 느림) 대신, **렌터카 업체(Connection Pool)**가 미리 만들어 둔(Pre-established) 차(Connection)를 빌려 타고, 다 쓰면 반납하는 것과 같습니다.
-   **동작**: 애플리케이션 시작 시, HikariCP는 미리 정해진 수(`minimumIdle`)만큼의 커넥션을 생성해서 '풀(Pool)'에 보관합니다.

---

### 2. **`connection.close()`의 진실: "닫는 게 아니라 반납하는 것" 🔄**

이것이 오늘 배운 가장 중요한 핵심입니다.

`@Transactional`이 붙은 서비스 메서드가 실행될 때의 내부 흐름은 다음과 같습니다.

1.  **[요청]**: `userRepository.findById(1L)` 같은 JPA 메서드 호출.
2.  **[대여]**: Spring의 `DataSourceTransactionManager`가 커넥션 풀(HikariCP)에게 `dataSource.getConnection()`을 요청합니다.
3.  HikariCP는 풀에서 놀고 있는(Idle) 커넥션(`Connection #1`)을 하나 꺼내어, "사용 중(Active)"으로 표시하고 Spring에게 빌려줍니다.
4.  **[사용]**: 비즈니스 로직이 실행되고, `Connection #1`을 통해 DB 쿼리가 수행됩니다.
5.  **[반납]**: 트랜잭션이 커밋/롤백되고, Spring은 `connection.close()`를 **호출합니다.**
6.  **[속임수]**: **이때 `connection.close()`는 진짜 TCP 연결을 끊는 `close()`가 아닙니다!** HikariCP는 이 `close()` 호출을 가로채서(Intercept), 대신 **"이 커넥션을 풀에 반납한다"**는 로직을 수행합니다.
7.  **[정비]**: HikariCP는 반납받은 `Connection #1`의 상태를 초기화(e.g., auto-commit=true로 복구, 트랜잭션 롤백 등)한 뒤, 다시 'Idle' 상태로 풀에 돌려놓습니다.

이 모든 과정 덕분에, 다음 요청은 이미 생성된 `Connection #1`을 즉시 재사용하여 DB 인증 등의 비싼 과정을 생략하고 바로 쿼리를 실행할 수 있습니다.

---

### 3. **HikariCP는 왜 기본값이 되었나? ⚡️**

Tomcat CP, Commons DBCP 등 다른 커넥션 풀도 많은데, Spring Boot 2.0부터 HikariCP가 기본값이 된 이유는 **'압도적인 성능과 안정성'** 때문입니다.

-   **`ConcurrentBag`**: 락(Lock) 경합을 최소화하기 위해 독자적으로 설계한 자료구조입니다. 다른 스레드의 방해 없이 커넥션을 가져가고 반납할 수 있도록 최적화되었습니다.
-   **바이트코드 레벨 최적화**: 프록시 생성 방식을 개선하고, 메서드 호출을 인라이닝하는 등 바이트코드 레벨에서 극단적인 최적화를 수행하여 오버헤드를 줄였습니다.
-   **`FastList`**: `ArrayList`에서 범위 체크 등 불필요한 로직을 제거한 커스텀 리스트를 사용하여 속도를 높였습니다.

---

### 4. **3~4년차가 알아야 할 핵심 튜닝 옵션 🔧**

`application.yml`에서 HikariCP의 동작을 미세 조정할 수 있습니다. 무작정 값을 늘리는 것이 아니라, 내 서버 스펙과 DB 스펙을 고려하여 설정하는 것이 중요합니다.

```yaml
spring:
  datasource:
    hikari:
      # (필수) 최대 커넥션 수
      # DB의 max_connections와 내 서버의 CPU 코어 수를 고려해야 함
      # 너무 크면 DB가 죽고, 너무 작으면 스레드들이 대기함.
      maximum-pool-size: 10 
      
      # (선택) 최소 유휴 커넥션 수
      # 이만큼은 항상 DB와 연결을 유지하며 대기함 (Warm-up)
      minimum-idle: 5 
      
      # (필수) 커넥션 타임아웃 (ms)
      # 풀에 가용한 커넥션이 없을 때, 스레드가 얼마나 기다릴지 (기본 30초)
      connection-timeout: 30000 
      
      # (권장) 커넥션 최대 생존 시간 (ms)
      # 방화벽 등에 의해 연결이 끊어지는(Stale) 것을 방지하기 위해
      # 커넥션을 주기적으로 교체해줌 (기본 30분)
      max-lifetime: 1800000
```

---

## 💡 배운 점

1.  **`connection.close()`는 거짓말이다**: 오늘 배운 가장 충격적인 사실입니다. `close()`가 실제 연결 종료가 아닌 '반납'을 의미한다는 것을 이해하고 나니, 커넥션 풀이 어떻게 리소스를 재활용하는지 명확하게 그림이 그려졌습니다.
2.  **풀(Pool) 튜닝은 DB와의 밀당이다**: `maximum-pool-size`는 내 애플리케이션만 생각하고 설정하는 값이 아니었습니다. 내 애플리케이션 인스턴스가 10대고, 풀 사이즈가 10이라면, DB는 최대 100개의 커넥션을 감당할 수 있어야 합니다. DB의 `max_connections` 설정을 반드시 확인하고, 시스템 전체의 관점에서 풀 사이즈를 산정해야 함을 깨달았습니다.
3.  **좋은 라이브러리는 '보이지 않는 곳'에서 일한다**: HikariCP가 왜 빠른지 탐구하면서, `ConcurrentBag`이나 바이트코드 최적화처럼 개발자에게 보이지 않는 낮은 레벨에서 얼마나 치열한 노력이 있었는지 알게 되었습니다. 3~4년차 개발자로서, 이제는 이런 '기본기'의 차이가 명품을 만든다는 것을 이해해야 할 때입니다.

---

## 🔗 참고 자료

-   [HikariCP 공식 GitHub (The Source of Truth)](https://github.com/brettwooldridge/HikariCP)
-   [Spring Boot Docs - Configure a DataSource](https://docs.spring.io/spring-boot/docs/current/reference/html/data.html#data.sql.datasource.production)
-   [The Anatomy of Connection Pooling (Oracle)](https://blogs.oracle.com/dev2dev/post/the-anatomy-of-connection-pooling)