---
title: "Spring Cloud Config: Git으로 MSA 설정파일 중앙 관리하기"
date: 2025-10-30
categories: [DevOps, Spring]
tags: [Spring Cloud Config, MSA, Config Server, DevOps, CI/CD, Spring Boot, TIL]
excerpt: "수십 개의 마이크로서비스에 흩어져 있는 'application.yml' 설정 파일들을 Git 저장소 한 곳에서 중앙 관리하는 Spring Cloud Config의 원리를 학습합니다. Config Server와 Client 설정 방법, 그리고 서비스 재시작 없이 설정을 동적으로 갱신하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Cloud Config: Git으로 MSA 설정파일 중앙 관리하기

## 📚 오늘 학습한 내용

저는 3~4년차 개발자로서 MSA(마이크로서비스 아키텍처) 환경에서 여러 서비스를 개발하고 있습니다. 하지만 서비스가 10개, 20개로 늘어나면서 심각한 문제에 부딪혔습니다. 바로 **설정(Configuration) 관리**입니다.

DB 접속 정보, Kafka 브로커 주소, 외부 API 키 등 공통 설정이 변경될 때마다, 관련된 모든 서비스의 `application.yml` 파일을 일일이 수정하고, 다시 빌드하여 재배포하는 작업을 반복해야 했습니다.

오늘은 이 지옥 같은 문제를 해결하기 위해, 모든 설정 파일을 **Git 저장소** 한 곳에서 중앙 관리할 수 있게 해주는 **Spring Cloud Config**에 대해 학습했습니다.

---

### 1. **Spring Cloud Config란 무엇인가? 🏦**

**Spring Cloud Config**는 분산 시스템(MSA)에서 설정 정보를 외부의 중앙 저장소에서 관리할 수 있도록 해주는 프로젝트입니다.

-   **Config Server**: Git, SVN, HashiCorp Vault 등에 저장된 설정 파일들을 읽어와 API 엔드포인트(`/{appName}/{profile}`)로 제공하는 **중앙 설정 관리 서버**입니다.
-   **Config Client**: 우리가 개발하는 각각의 마이크로서비스입니다. 애플리케이션이 시작될 때, Config Server에 접속하여 자신에게 필요한 설정 정보(e.g., `my-service-prod.yml`)를 가져와서 Spring Environment에 주입받습니다.



이 구조를 통해, 모든 설정의 **"신뢰할 수 있는 단일 소스(Single Source of Truth)"**가 Git 저장소로 통일됩니다.

---

### 2. **어떻게 동작하는가? (단계별 구축)**

#### **Step 1: 설정 파일을 저장할 Git Repository 생성**
먼저, 모든 설정 파일을 저장할 별도의 Git 저장소를 준비합니다. (e.g., `https://github.com/my-org/msa-config-repo`)

이 저장소에 서비스별 설정 파일을 생성합니다. 파일 이름은 `{애플리케이션 이름}-{프로필}.yml` 형식을 따릅니다.

**`user-service-prod.yml`** (in Git Repo)
```yaml
database:
  url: "jdbc:mysql://prod-db:3306/user_db"
  username: "prod_user"
```

**`order-service-prod.yml`** (in Git Repo)
```yaml
database:
  url: "jdbc:mysql://prod-db:3306/order_db"
  username: "prod_user"
kafka:
  bootstrap-servers: "kafka-prod:9092"
```

#### **Step 2: Config Server 구축 (별도의 Spring Boot 앱)**
`spring-cloud-config-server` 의존성을 가진 Spring Boot 앱을 하나 만듭니다.

**`build.gradle`**
```groovy
implementation 'org.springframework.cloud:spring-cloud-config-server'
```

**`ConfigServerApplication.java`**
```java
@SpringBootApplication
@EnableConfigServer // Config Server 기능을 활성화!
public class ConfigServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(ConfigServerApplication.class, args);
    }
}
```

**`application.yml` (Config Server의 설정)**
```yaml
server:
  port: 8888 # Config Server는 8888 포트를 사용

spring:
  cloud:
    config:
      server:
        git:
          uri: https://github.com/my-org/msa-config-repo.git # 1단계에서 만든 Git 저장소 주소
          # private 저장소일 경우 username, password 등 추가
```
이제 이 서버를 실행하면, `http://localhost:8888/user-service/prod`로 접속 시 `user-service-prod.yml` 파일의 내용이 JSON 형태로 반환됩니다.

#### **Step 3: Config Client 적용 (MSA 서비스들)**
이제 `user-service`가 Config Server로부터 설정을 가져오도록 변경합니다.

**`build.gradle` (`user-service`)**
```groovy
implementation 'org.springframework.cloud:spring-cloud-starter-config'
```

**`src/main/resources/bootstrap.yml` (매우 중요!)**
애플리케이션의 설정(`application.yml`)을 읽어오기 **전에** Config Server의 위치를 알아야 하므로, `application.yml`보다 먼저 로드되는 `bootstrap.yml`에 Config Server 정보를 작성합니다.

```yaml
spring:
  application:
    name: user-service # 1. Git에 저장된 파일 이름 (user-service)
  
  cloud:
    config:
      uri: http://localhost:8888 # 2. Config Server의 주소
      profile: prod # 3. 가져올 프로필 (prod.yml)
```
이제 `user-service`를 `prod` 프로필로 실행하면, 이 앱은 `application.yml`을 읽는 대신 `http://localhost:8888/user-service/prod`에서 설정을 가져와서 실행됩니다.

---

### 3. **서비스 재시작 없이 설정 변경: `@RefreshScope`**

DB 접속 정보가 변경되어 Git의 `user-service-prod.yml`을 수정하고 Push했습니다. 그렇다면 `user-service`를 재시작해야 할까요? **그럴 필요 없습니다.**

1.  **Client에 `actuator` 의존성 추가**: `spring-boot-starter-actuator`
2.  **`@RefreshScope`**: 설정이 변경되기를 원하는 Bean(e.g., `@ConfigurationProperties`, `@Value`가 있는 클래스)에 `@RefreshScope` 애노테이션을 붙입니다.
3.  **변경 요청**: Git Push 후, `user-service`의 `/actuator/refresh` 엔드포인트로 `POST` 요청을 보냅니다.
    ```bash
    curl -X POST http://localhost:8081/actuator/refresh
    ```
4.  **동작**: 이 요청을 받은 `user-service`는 Config Server에서 **최신 설정 정보를 다시 가져와서**, `@RefreshScope`가 붙은 빈(Bean)들만 **파괴하고 재생성**합니다.

이 과정을 통해, 전체 애플리케이션을 재시작하는 큰 비용 없이, DB 커넥션 풀 같은 특정 빈만 동적으로 교체할 수 있습니다.

---

## 💡 배운 점

1.  **설정(Config)과 코드(Code)의 분리**: Spring Cloud Config를 사용하면 인프라 정보(DB 주소, API 키 등)를 애플리케이션 배포 아티팩트(JAR/WAR)로부터 완벽하게 분리할 수 있습니다. 이는 DevOps 엔지니어와 개발자 간의 책임을 명확히 나누고, 보안성을 크게 향상시킵니다.
2.  **Git은 최고의 설정 저장소다**: 모든 설정 변경이 Git의 커밋(Commit) 이력으로 남기 때문에, "누가, 언제, 왜" 설정을 변경했는지 추적하기가 매우 용이합니다. 실수로 잘못된 설정을 배포해도 `git revert` 한 번으로 롤백이 가능합니다.
3.  **`@RefreshScope`의 강력함**: 운영 중인 서비스의 로그 레벨을 `INFO`에서 `DEBUG`로 변경하고 싶을 때, 재시작 없이 `/actuator/refresh` 호출만으로 동적 변경이 가능하다는 것은 엄청난 운영상의 이점임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring Cloud Config (Official Documentation)](https://spring.io/projects/spring-cloud-config)
-   [Spring Cloud Config (Baeldung)](https://www.baeldung.com/spring-cloud-configuration)
-   [Externalized Configuration (Spring Cloud Patterns)](https://spring.io/blog/2015/01/20/microservice-infrastructure-with-spring-cloud-config)