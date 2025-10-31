---
title: "Testcontainers: Spring Boot 통합 테스트의 혁명"
date: 2025-10-30
categories: [Test, DevOps]
tags: [Testcontainers, Integration Testing, Spring Boot, JUnit, Docker, MySQL, TIL]
excerpt: "JPA Repository나 DB 의존성이 있는 통합 테스트 시, H2 같은 인메모리 DB의 한계를 알아보고, Testcontainers를 사용하여 실제 운영 환경과 '동일한' DB(MySQL)를 Docker 컨테이너로 띄워 테스트하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Testcontainers: Spring Boot 통합 테스트의 혁명

## 📚 오늘 학습한 내용

저는 3~4년차 개발자로서 `@SpringBootTest`나 `@DataJpaTest`를 이용한 통합 테스트를 꾸준히 작성해왔습니다. 이때 DB 의존성을 해결하기 위해 주로 `H2` 인메모리 데이터베이스를 사용했습니다. H2는 빠르고 가볍다는 장점이 있지만, 실제 운영 환경에서 사용하는 MySQL이나 PostgreSQL과는 근본적으로 다릅니다.

-   **H2의 한계**:
    -   MySQL 전용 SQL 문법(e.g., `JSON_EXTRACT`, `GROUP_CONCAT`)이나 함수가 동작하지 않습니다.
    -   테이블 생성 DDL이나 데이터 타입의 미묘한 차이로 인해, H2에서는 성공한 테스트가 운영 DB에서는 실패하는 경우가 발생합니다.
    -   결국, **"테스트의 신뢰도"**가 떨어지게 됩니다.

오늘은 이 문제를 해결하기 위해, **실제 DB를 Docker 컨테이너로 띄워서** 테스트를 수행하게 해주는 **Testcontainers** 라이브러리에 대해 학습했습니다.

---

### 1. **Testcontainers란 무엇인가? 🐳**

**Testcontainers**는 JUnit과 같은 테스트 프레임워크와 통합되어, 테스트 코드 내에서 **프로그래밍 방식으로 Docker 컨테이너를 시작하고 관리**할 수 있게 해주는 Java 라이브러리입니다.

-   **핵심 원리**:
    1.  테스트가 시작되면, Testcontainers가 Docker에게 `mysql:8.0`과 같은 지정된 이미지로 컨테이너를 실행하도록 명령합니다.
    2.  컨테이너가 실행되고 랜덤 포트가 할당되면, Testcontainers가 이 컨테이너의 동적 주소(JDBC URL, 포트 등)를 가져옵니다.
    3.  Spring Boot의 `DataSource` 설정을 이 **동적 주소로 덮어쓰기(override)**합니다.
    4.  테스트 코드는 H2가 아닌, 방금 뜬 **실제 MySQL Docker 컨테이너**에 연결되어 실행됩니다.
    5.  테스트가 종료되면, Testcontainers가 해당 컨테이너를 자동으로 종료하고 삭제합니다.

---

### 2. **Spring Boot와 Testcontainers 연동하기**

Spring Boot는 `spring-boot-testcontainers` 모듈을 통해 Testcontainers와의 연동을 매우 쉽게 지원합니다.

#### **1. `build.gradle` 의존성 추가**
```groovy
testImplementation 'org.springframework.boot:spring-boot-testcontainers'
testImplementation 'org.testcontainers:junit-jupiter' // Testcontainers JUnit 5 지원
testImplementation 'org.testcontainers:mysql'       // MySQL 모듈
```

#### **2. 테스트 코드 작성 (`@Testcontainers`)**
JPA Repository를 테스트하는 `@DataJpaTest` 예시입니다.

```java
@Testcontainers // 1. JUnit 5에게 Testcontainers를 사용함을 알림
@DataJpaTest
// 2. (중요) H2 같은 내장 DB를 사용하지 않도록 설정
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE) 
class UserRepositoryTest {

    @Autowired
    private UserRepository userRepository;

    // 3. (정적 필드) 테스트 클래스 전체에서 공유할 MySQL 컨테이너 정의
    //    컨테이너가 한 번만 뜨고 모든 테스트에서 재사용됨 (속도 향상)
    @Container
    private static final MySQLContainer<?> mySQLContainer = 
            new MySQLContainer<>("mysql:8.0.28");

    // 4. (핵심) 동적으로 Spring의 DataSource 설정을 덮어쓰기
    @DynamicPropertySource
    private static void setDatasourceProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mySQLContainer::getJdbcUrl);
        registry.add("spring.datasource.username", mySQLContainer::getUsername);
        registry.add("spring.datasource.password", mySQLContainer::getPassword);
    }

    @Test
    @DisplayName("사용자를 저장하고 ID로 조회하면 정상적으로 조회된다")
    void saveAndFindById() {
        // given
        User newUser = new User("testuser", "test@example.com");

        // when
        User savedUser = userRepository.save(newUser);
        Optional<User> foundUser = userRepository.findById(savedUser.getId());

        // then
        assertThat(foundUser).isPresent();
        assertThat(foundUser.get().getUsername()).isEqualTo("testuser");
        // 이 테스트는 H2가 아닌 실제 MySQL 8.0.28 컨테이너에서 실행됨!
    }
}
```

---

### 3. **Testcontainers의 장점 (오늘 배운 점)**

1.  **궁극의 테스트 신뢰도 (High Fidelity)**
    -   운영 환경과 **동일한 버전**의 DB(MySQL 8.0, Redis 7.0 등)를 사용하여 테스트하므로, H2에서 발생하던 환경 불일치 버그를 원천적으로 차단할 수 있습니다.
    -   MySQL 전용 네이티브 쿼리나 함수를 사용해도 자신 있게 테스트할 수 있습니다.

2.  **완벽한 격리 (Isolation)**
    -   각 테스트(또는 테스트 클래스)마다 깨끗한 상태의 컨테이너를 띄우므로, 다른 테스트의 데이터에 오염될 걱정이 없습니다. (`@DirtiesContext` 불필요)

3.  **DevOps 경험의 통합**
    -   지금까지 저의 DevOps 업무였던 'Docker'가 이제 '테스트' 영역으로 들어왔습니다. 개발 단계에서부터 컨테이너 환경을 다루면서 인프라에 대한 이해도를 높일 수 있습니다.

4.  **DB를 넘어서는 확장성**
    -   Testcontainers는 DB뿐만 아니라 **Redis, Kafka, RabbitMQ, Elasticsearch** 등 거의 모든 것을 컨테이너로 띄울 수 있습니다.
    -   `@MockBean`으로 가짜 객체를 만드는 대신, **실제 Redis 컨테이너**를 띄워 Spring의 캐시(`@Cacheable`)가 만료 시간(TTL)까지 정확하게 동작하는지 검증하는 '진짜' 통합 테스트가 가능해집니다.

---

## 💡 결론

H2를 사용하는 것은 '빠른 피드백'을 얻는 데는 유리했지만, 3~4년차 개발자로서 '신뢰할 수 없는 테스트'에 대한 비용이 더 크다는 것을 깨달았습니다. Testcontainers는 약간의 초기 실행 속도를 희생하는 대신, **"내 테스트가 통과하면, 운영에서도 문제없다"**라는 강력한 자신감을 줍니다. 이는 단순한 테스트 라이브러리를 넘어, MSA 환경의 통합 테스트 표준임을 확신하게 되었습니다.

---

## 🔗 참고 자료

-   [Testcontainers 공식 문서](https://www.testcontainers.org/)
-   [Spring Boot with Testcontainers (Official Docs)](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.testing.testcontainers)
-   [Testcontainers - Spring Boot (Baeldung)](https://www.baeldung.com/spring-boot-testcontainers)