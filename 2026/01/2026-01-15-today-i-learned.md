---
title: "H2는 그만: Testcontainers로 신뢰할 수 있는 통합 테스트 환경 구축하기"
date: 2026-01-16
categories: [Testing, DevOps, Spring]
tags: [Testcontainers, JUnit5, Integration Test, Docker, Spring Boot 3, MySQL, TIL]
excerpt: "프로덕션 환경과 다른 H2 데이터베이스로 테스트하며 겪는 문법 호환성 문제와 신뢰성 저하를 해결하기 위해 Testcontainers를 도입합니다. Spring Boot 3.1의 @ServiceConnection을 활용하여 복잡한 설정 없이 Docker 컨테이너 기반의 리얼한 통합 테스트 환경을 구축하는 방법을 학습합니다."
author_profile: true
---

# Today I Learned: H2는 그만: Testcontainers로 신뢰할 수 있는 통합 테스트 환경 구축하기

## 📚 오늘 학습한 내용

로컬 개발과 테스트에서는 가벼운 **H2 (In-memory DB)**를 사용하고, 배포 환경에서는 **MySQL**을 사용하는 전략은 흔합니다. 하지만 최근 프로젝트에서 MySQL 전용 함수(`GROUP_CONCAT`이나 `Spatial Index`)를 사용하거나, 락(Lock) 동작 방식이 미묘하게 달라 테스트는 통과했는데 배포하면 에러가 터지는 **"환경 불일치"** 문제를 겪었습니다.

오늘은 "테스트 환경도 프로덕션과 동일해야 한다"는 원칙을 지키기 위해, 자바 코드만으로 도커 컨테이너를 띄워 테스트하는 **Testcontainers**를 적용했습니다. 특히 Spring Boot 3.1부터 도입된 기능을 사용하여 설정을 획기적으로 줄이는 방법을 정리했습니다.

---

### 1. **왜 Testcontainers인가? 🐳**

-   **H2의 한계**: MySQL의 특정 버전 문법이나 고유 기능(JSON 타입, GIS 등)을 H2가 100% 모방하지 못합니다.
-   **외부 의존성**: Redis, Kafka, Elasticsearch 등 DB 외의 인프라도 테스트해야 하는데, 이를 로컬에 다 설치해두는 것은 관리 포인트가 늘어납니다.
-   **격리성**: Testcontainers는 테스트 실행 시 컨테이너를 띄우고 종료 시 파기하므로, 항상 깨끗한 상태(Clean State)에서 테스트할 수 있습니다.

---

### 2. **Spring Boot 3.1+ 적용 방법 (`@ServiceConnection`)**

예전에는 `DynamicPropertySource`를 써서 포트를 동적으로 바인딩해주는 귀찮은 설정이 필요했지만, Spring Boot 3.1부터는 **`@ServiceConnection`** 애노테이션 하나로 해결됩니다.

#### **Step 1: 의존성 추가**

```groovy
testImplementation 'org.springframework.boot:spring-boot-testcontainers'
testImplementation 'org.testcontainers:junit-jupiter'
testImplementation 'org.testcontainers:mysql'
```

#### **Step 2: 통합 테스트 베이스 클래스 작성**

매번 컨테이너를 띄우면 느리므로, `static`으로 선언하여 모든 테스트가 하나의 컨테이너를 공유하게(Singleton Pattern) 하는 것이 일반적입니다.

```java
@SpringBootTest
@Transactional
@Testcontainers // JUnit 5 확장 기능 활성화
public abstract class IntegrationTestSupport {

    // 1. 도커 이미지 지정 (프로덕션과 동일한 버전 사용 권장)
    @Container
    @ServiceConnection // 2. Spring이 알아서 DataSource 설정을 이 컨테이너로 연결해줌 (Magic!)
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0.33");

    // Redis도 필요하다면?
    // @Container
    // @ServiceConnection
    // static GenericContainer<?> redis = new GenericContainer<>("redis:7.0").withExposedPorts(6379);
}
```

#### **Step 3: 실제 테스트 코드**

이제 `application-test.yml`에 DB 접속 정보를 적을 필요가 없습니다. 테스트가 실행되면 도커가 뜨고, Spring이 그 도커 주소를 바라보며 부트스트랩 합니다.

```java
class OrderRepositoryTest extends IntegrationTestSupport {

    @Autowired
    private OrderRepository orderRepository;

    @Test
    @DisplayName("MySQL 전용 함수인 ST_Distance_Sphere도 문제없이 테스트 가능하다")
    void spatialQueryTest() {
        // given
        Point location = ...;
        
        // when
        // H2 모드였다면 여기서 "Function not found" 에러가 났을 것임
        List<Order> result = orderRepository.findNearBy(location); 
        
        // then
        assertThat(result).isNotEmpty();
    }
}
```

---

### 3. **성능 최적화: 컨테이너 재사용 (Reuse)**

Testcontainers의 단점은 **느린 구동 속도**입니다. 테스트를 돌릴 때마다 컨테이너를 띄우는 시간(약 3~5초)이 걸립니다.
로컬 반복 개발 시 이를 단축하기 위해 **전역 재사용(Reusable)** 옵션을 켤 수 있습니다.

1.  **홈 디렉토리 설정 파일 생성 (`~/.testcontainers.properties`)**
    ```properties
    testcontainers.reuse.enable=true
    ```

2.  **코드 수정 (`withReuse(true)`)**
    ```java
    @Bean
    @ServiceConnection
    public MySQLContainer<?> mysqlContainer() {
        return new MySQLContainer<>("mysql:8.0")
            .withReuse(true); // 테스트가 끝나도 컨테이너를 끄지 않음 (다음 실행 때 재활용)
    }
    ```

이렇게 하면 첫 실행만 느리고, 두 번째부터는 켜져 있는 컨테이너를 바로 붙여서 쓰므로 H2만큼 빠릅니다.

---

### 4. **CI/CD 파이프라인 고려사항**

Github Actions나 Jenkins에서 Testcontainers를 돌리려면 **Docker-in-Docker (DinD)** 혹은 **Docker Socket Binding** 설정이 필요합니다.
-   CI 환경에서는 호스트의 Docker 데몬을 빌드 컨테이너와 공유하도록 설정해야 테스트 코드가 컨테이너를 띄울 수 있습니다.

---

## 💡 배운 점

1.  **환경 일치성**: "내 컴퓨터에선 되는데?"라는 변명을 원천 차단했습니다. 로컬, CI, 프로덕션 모두 리얼 MySQL을 쓰게 되어, DB 벤더별 방언(Dialect) 문제에서 완전히 해방되었습니다.
2.  **설정의 간소화**: Spring Boot 3.1의 `@ServiceConnection`은 혁명입니다. 예전처럼 포트 매핑하고 `System.setProperty` 하던 코드가 싹 사라져서 테스트 설정 코드가 매우 깔끔해졌습니다.
3.  **테스트의 신뢰도**: H2를 쓸 때는 "이 쿼리가 진짜 나가나?" 의심하며 로그를 확인했지만, 이제는 테스트가 통과하면 배포해도 된다는 확신을 가질 수 있게 되었습니다.

---

## 🔗 참고 자료

-   [Spring Boot 3.1 Connection Details](https://spring.io/blog/2023/06/23/improved-testcontainers-support-in-spring-boot-3-1)
-   [Testcontainers Official Docs](https://java.testcontainers.org/)
-   [Testing Spring Boot Applications with Testcontainers](https://www.baeldung.com/spring-boot-testcontainers-integration-test)