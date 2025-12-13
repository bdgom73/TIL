---
title: "Testcontainers: H2의 한계를 넘어 실제 환경과 동일한 통합 테스트 구축하기"
date: 2025-12-13
categories: [Testing, DevOps]
tags: [Testcontainers, Integration Test, JUnit 5, Docker, Spring Boot Testing, MySQL, Redis, TIL]
excerpt: "운영 환경과 다른 H2 인메모리 DB로 인해 발생하는 '거짓 양성' 테스트 문제를 해결합니다. Docker를 활용해 테스트 실행 시점에 실제 DB 컨테이너를 띄우고 제거하는 Testcontainers 라이브러리의 적용 방법과 성능 최적화(Singleton Container) 패턴을 학습합니다."
author_profile: true
---

# Today I Learned: Testcontainers: H2의 한계를 넘어 실제 환경과 동일한 통합 테스트 구축하기

## 📚 오늘 학습한 내용

통합 테스트를 작성할 때, 빠르고 간편하다는 이유로 H2 같은 인메모리 DB를 자주 사용해왔습니다. 하지만 최근 배포 과정에서 **"로컬 테스트는 통과했는데, 운영 환경(MySQL)에서는 문법 오류로 실패하는"** 아찔한 경험을 했습니다. (예: MySQL의 특정 함수나 Window Function 미지원, 예약어 차이 등)

오늘은 이러한 환경 불일치 문제를 해결하기 위해, 테스트 코드가 실행될 때 **Docker 컨테이너로 실제 운영 환경과 동일한 DB**를 띄워 테스트하는 **Testcontainers** 라이브러리를 학습하고 적용했습니다.

---

### 1. **Testcontainers란? 🐳**

Testcontainers는 JUnit 테스트를 지원하는 Java 라이브러리로, Docker API를 사용하여 데이터베이스, 메시지 브로커(Kafka, RabbitMQ), 웹 브라우저(Selenium) 등을 경량 컨테이너로 제공해줍니다.

-   **장점**:
    -   **환경 일치성**: 운영 환경과 100% 동일한 DB(버전 포함)에서 테스트하므로 신뢰도가 높습니다.
    -   **격리성**: 테스트가 끝나면 컨테이너가 파기되므로 데이터 오염 걱정이 없습니다.
    -   **편의성**: 별도로 로컬에 DB를 설치하거나 `docker-compose up`을 할 필요 없이, 코드만 실행하면 알아서 떴다 사라집니다.

---

### 2. **Spring Boot에 적용하기 (MySQL 예제)**

#### **Step 1: 의존성 추가**

```groovy
testImplementation 'org.springframework.boot:spring-boot-testcontainers' // Spring Boot 3.1+ 지원 기능
testImplementation 'org.testcontainers:junit-jupiter'
testImplementation 'org.testcontainers:mysql'
```

#### **Step 2: 기본 사용법 (`@Testcontainers`, `@Container`)**

가장 기본적인 형태는 테스트 클래스마다 컨테이너를 띄우는 방식입니다.

```java
@SpringBootTest
@Testcontainers // 1. Testcontainers 활성화
class OrderIntegrationTest {

    // 2. 사용할 컨테이너 정의 (MySQL 8.0)
    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test");

    // 3. 동적으로 생성된 컨테이너 정보를 Spring 프로퍼티에 주입
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
    }

    @Test
    void createOrder() {
        // 실제 MySQL 컨테이너 위에서 실행되는 테스트
    }
}
```

---

### 3. **성능 최적화: Singleton Container 패턴 🚀**

위의 방식(`@Container` static 필드)은 테스트 클래스마다 컨테이너를 새로 띄우고 끄기 때문에 테스트 속도가 매우 느려집니다. (MySQL 시동에만 수 초 소요)

이를 해결하기 위해 **모든 테스트가 하나의 컨테이너를 공유(Singleton)**하여 재사용하는 패턴을 적용해야 합니다.

**`AbstractContainerBaseTest.java` (공통 부모 클래스)**

```java
public abstract class AbstractContainerBaseTest {

    static final MySQLContainer<?> MYSQL_CONTAINER;

    static {
        // 1. static 블록에서 컨테이너를 수동으로 시작
        MYSQL_CONTAINER = new MySQLContainer<>("mysql:8.0")
                .withDatabaseName("testdb")
                .withUsername("test")
                .withPassword("test")
                .withReuse(true); // (선택) 로컬 개발 시 컨테이너 재사용 옵션
        
        MYSQL_CONTAINER.start();
    }

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL_CONTAINER::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL_CONTAINER::getUsername);
        registry.add("spring.datasource.password", MYSQL_CONTAINER::getPassword);
    }
}
```

**실제 테스트 클래스**
```java
@SpringBootTest
class ProductServiceTest extends AbstractContainerBaseTest { // 상속만 받으면 끝
    
    @Test
    void test1() { ... }
}

@SpringBootTest
class OrderServiceTest extends AbstractContainerBaseTest { // 같은 컨테이너 재사용
    
    @Test
    void test2() { ... }
}
```
이제 전체 테스트 스위트가 실행될 때 **컨테이너는 딱 한 번만 뜹니다.** 다만, 데이터가 공유되므로 각 테스트 메서드 실행 후 데이터를 초기화(`@Transactional` 롤백 또는 테이블 Truncate)하는 전략이 중요해집니다.

---

### 4. **Spring Boot 3.1의 혁신: Service Connection**

Spring Boot 3.1부터는 `@ServiceConnection`이 도입되어, 복잡한 `@DynamicPropertySource` 설정조차 필요 없어졌습니다.

```java
@TestConfiguration(proxyBeanMethods = false)
public class TestContainersConfig {

    @Bean
    @ServiceConnection // Spring이 알아서 DataSource 프로퍼티를 이 컨테이너로 연결해줌
    public MySQLContainer<?> mysqlContainer() {
        return new MySQLContainer<>("mysql:8.0");
    }
    
    @Bean
    @ServiceConnection(name = "redis") // Redis도 가능
    public GenericContainer<?> redisContainer() {
        return new GenericContainer<>("redis:7.0").withExposedPorts(6379);
    }
}
```

---

## 💡 배운 점

1.  **Mocking의 한계 탈피**: Mock 객체로 도배된 테스트는 구현 세부 사항에 의존하게 되어 리팩토링을 방해합니다. Testcontainers를 사용하면 **"인프라는 실제와 똑같이, 로직만 검증"**하는 진정한 의미의 블랙박스 통합 테스트가 가능해집니다.
2.  **데이터베이스 특화 기능 테스트 가능**: MySQL의 `Spatial Index`, `Full Text Search`나 Redis의 `Geo` 기능 등 인메모리 DB가 흉내 낼 수 없는 벤더 특화 기능을 마음껏 테스트 코드에 녹여낼 수 있게 되었습니다.
3.  **CI/CD 파이프라인의 단순화**: 별도의 DB 서버를 구축하고 관리할 필요 없이, Docker가 설치된 CI 환경(Github Actions 등)이라면 어디서든 동일한 테스트 환경을 보장받을 수 있다는 점이 DevOps 관점에서도 큰 이점입니다.

---

## 🔗 참고 자료

-   [Testcontainers Official Docs](https://java.testcontainers.org/)
-   [Spring Boot 3.1 ConnectionDetails & Testcontainers](https://spring.io/blog/2023/06/23/improved-testcontainers-support-in-spring-boot-3-1)
-   [Testing with Testcontainers (Baeldung)](https://www.baeldung.com/docker-test-containers)