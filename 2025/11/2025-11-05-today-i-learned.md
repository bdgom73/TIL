---
title: "R2DBC: Spring Boot에서 반응형 SQL 데이터베이스 접근하기"
date: 2025-11-05
categories: [Spring, Reactive, Database]
tags: [R2DBC, Spring Data, Reactive SQL, MySQL, Non-blocking, WebFlux, TIL]
excerpt: "Spring WebFlux 환경에서 JPA/JDBC를 사용할 때 발생하는 블로킹 문제를 해결하기 위한 R2DBC(Reactive Relational Database Connectivity)의 개념을 학습합니다. DatabaseClient와 ReactiveCrudRepository의 사용법, 그리고 반응형 트랜잭션 처리 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: R2DBC: Spring Boot에서 반응형 SQL 데이터베이스 접근하기

## 📚 오늘 학습한 내용

저는 Spring WebFlux와 `Mono`, `Flux`를 사용하는 반응형 프로그래밍에 대해 학습했지만, 한 가지 큰 의문이 있었습니다. **"Spring Data JPA(JDBC)는 본질적으로 블로킹(Blocking) 방식인데, 어떻게 WebFlux와 함께 사용할 수 있지?"**

결론부터 말하면, WebFlux 스택에서 JPA를 사용하는 것은 반응형 프로그래밍의 이점을 스스로 무너뜨리는 행위입니다. (`subscribeOn(Schedulers.boundedElastic())`을 통해 블로킹 호출을 별도 스레드 풀로 옮길 순 있지만, 이는 근본적인 해결책이 아닙니다.)

오늘은 이 문제를 해결하기 위해 등장한 **R2DBC(Reactive Relational Database Connectivity)**, 즉 **반응형 SQL DB 연동 기술**에 대해 학습했습니다.

---

### 1. **R2DBC란 무엇인가? 🌊**

-   **JDBC의 한계**: `java.sql.Connection`을 포함한 모든 JDBC API는 스레드를 차단(Block)하도록 설계되었습니다. DB 응답이 올 때까지 스레드는 기다려야 합니다.
-   **R2DBC**: 반응형 스트림(Reactive Streams) 표준을 준수하는 **논블로킹(Non-blocking)** DB 접근을 위한 새로운 API 스펙입니다. Netty와 같은 이벤트 루프 기반 서버에서 적은 스레드로 높은 처리량을 낼 수 있도록 설계되었습니다.
-   **핵심**: `r2dbc-mysql`, `r2dbc-postgresql` 등 각 벤더사가 R2DBC 스펙을 구현한 논블로킹 드라이버를 제공합니다.

---

### 2. **Spring Data R2DBC의 두 가지 접근 방식**

Spring Data R2DBC는 두 가지 수준의 API를 제공합니다.

#### **① `DatabaseClient`: 반응형 `JdbcTemplate`**
`DatabaseClient`는 SQL 쿼리를 유연하게 작성하고 실행할 수 있는 논블로킹 API입니다. (JPA보다는 JdbcTemplate에 가깝습니다.)

**1. 의존성 및 설정**
```groovy
// build.gradle
implementation 'org.springframework.boot:spring-boot-starter-data-r2dbc'
implementation 'dev.miku:r2dbc-mysql' // MySQL R2DBC 드라이버
```
```yaml
# application.yml
spring:
  r2dbc:
    url: r2dbc:mysql://localhost:3306/mydb
    username: user
    password: pw
```

**2. `DatabaseClient` 사용 예**
```java
@Component
@RequiredArgsConstructor
public class MyR2dbcService {

    private final DatabaseClient databaseClient;

    public Flux<User> findUsersByAge(int age) {
        return this.databaseClient
                .sql("SELECT id, name, age FROM users WHERE age = :age")
                .bind("age", age)
                .map((row, rowMetadata) -> new User(
                        row.get("id", Long.class),
                        row.get("name", String.class),
                        row.get("age", Integer.class)
                ))
                .all(); // Flux<User> 반환
    }

    public Mono<Void> saveUser(User user) {
        return this.databaseClient
                .sql("INSERT INTO users (name, age) VALUES (:name, :age)")
                .bind("name", user.getName())
                .bind("age", user.getAge())
                .then(); // Mono<Void> 반환
    }
}
```

#### **② `ReactiveCrudRepository`: 반응형 `JpaRepository`**
JPA처럼 인터페이스 정의만으로 CRUD 기능을 사용하고 싶다면 `ReactiveCrudRepository`를 사용합니다.

```java
// JPA의 @Entity 대신 @Table 어노테이션 사용
@Table("users")
public class User {
    @Id
    private Long id;
    private String name;
    private int age;
    // ...
}

// JpaRepository 대신 ReactiveCrudRepository 상속
public interface UserRepository extends ReactiveCrudRepository<User, Long> {
    
    // 쿼리 메서드도 반응형으로 반환
    Flux<User> findByAge(int age);
}
```
> **핵심 차이**: `save`, `findById` 등 모든 메서드가 `Mono` 또는 `Flux`를 반환합니다. 이는 DB 작업이 비동기적으로 실행되고, 그 '결과에 대한 약속(Publisher)'을 즉시 반환한다는 의미입니다.

---

### 3. **가장 큰 함정: 반응형 트랜잭션 (`@Transactional`의 부재)**

3~4년차 개발자로서 가장 충격적인 부분은, **R2DBC에서는 `@Transactional` 애노테이션이 동작하지 않는다**는 것입니다.

-   **이유**: `@Transactional`은 **ThreadLocal**을 기반으로 동작합니다. 하지만 논블로킹 환경에서는 하나의 요청이 여러 스레드(이벤트 루프)를 넘나들며 실행될 수 있으므로, ThreadLocal 기반의 트랜잭션 컨텍스트가 유실됩니다.

-   **해결책: `TransactionalOperator` 사용**
    반응형 트랜잭션을 사용하려면, `TransactionalOperator`를 주입받아 **직접 체인(Chain)에 트랜잭션을 적용**해야 합니다.

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final ReactiveUserRepository userRepository;
    private final TransactionalOperator transactionalOperator; // 1. 주입

    public Mono<User> createUser(String name, int age) {
        User newUser = new User(name, age);

        // 2. 비즈니스 로직(Mono/Flux)을 정의
        Mono<User> businessLogic = userRepository.save(newUser)
                .doOnNext(savedUser -> {
                    if (savedUser.getName().equals("error")) {
                        // 3. 런타임 예외 발생 시, 롤백이 일어나야 함
                        throw new RuntimeException("Simulated error!");
                    }
                });

        // 4. .as(operator::transactional)을 통해 전체 Mono 체인을 트랜잭션으로 묶음
        return businessLogic.as(transactionalOperator::transactional);
    }
}
```

---

## 💡 배운 점

1.  **반응형 스택은 'All or Nothing'이다**: WebFlux를 선택했다는 것은 단순히 Controller의 시그니처를 바꾸는 것이 아니라, DB 접근 방식(JDBC -> R2DBC), 트랜잭션 관리(@Transactional -> TransactionalOperator) 등 생태계 전체를 논블로킹 방식으로 전환해야 함을 의미합니다.
2.  **R2DBC는 JPA가 아니다**: Spring Data R2DBC는 영속성 컨텍스트, 1차 캐시, 변경 감지(Dirty Checking), 지연 로딩(Lazy Loading)과 같은 JPA(ORM)의 고급 기능을 **제공하지 않습니다.** R2DBC는 SQL 매퍼(MyBatis와 유사)에 더 가깝다는 것을 명확히 인지해야 합니다.
3.  **트랜잭션 관리의 패러다임 변화**: `@Transactional`이라는 '마법'에 의존하던 것을 넘어, `TransactionalOperator`를 통해 트랜잭션의 범위를 개발자가 직접 코드 레벨에서 명시적으로 선언하는 방식이 낯설지만, 데이터 흐름을 더 명확하게 제어할 수 있다는 장점도 있다는 것을 깨달았습니다.

---

## 🔗 참고 자료

-   [R2DBC 공식 사이트 (스펙)](https://r2dbc.io/)
-   [Spring Data R2DBC - 공식 문서](https://docs.spring.io/spring-data/r2dbc/docs/current/reference/html/)
-   [R2DBC and Reactive Transactions (Baeldung)](https://www.baeldung.com/spring-r2dbc-transactional)