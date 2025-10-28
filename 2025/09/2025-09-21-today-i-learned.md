---
title: "컨테이너 오케스트레이션: Docker 최적화, Compose, Kubernetes 배포"
date: 2025-09-21
categories: [DevOps, Container]
tags: [Docker, Docker Compose, Kubernetes, Dockerfile, MSA, TIL]
excerpt: "Dockerfile 최적화를 위한 Multi-stage 빌드, Docker Compose를 활용한 로컬 개발 환경 통일, 그리고 Kubernetes의 핵심 개념(Pod, Service, Deployment)과 실제 Spring Boot 애플리케이션 배포 방법에 대해 학습합니다."
author_profile: true
---

# Today I Learned: 컨테이너 오케스트레이션: Docker 최적화, Compose, Kubernetes 배포

## 📚 오늘 학습한 내용

컨테이너 기술은 현대 백엔드 개발의 표준이 되었습니다. 오늘은 단순히 애플리케이션을 컨테이너로 만드는 것을 넘어, 이미지를 최적화하고, 여러 컨테이너를 효율적으로 관리하며, 최종적으로 Kubernetes 환경에 배포하는 전반적인 과정에 대해 학습했습니다.

---

### 1. **Dockerfile 최적화: Multi-stage 빌드로 경량 Docker 이미지 만들기**

Spring Boot 애플리케이션의 Docker 이미지를 만들 때, 소스코드, 빌드 도구(Gradle/Maven), JDK 등이 모두 포함되면 이미지 크기가 매우 커집니다. **Multi-stage 빌드**는 빌드 단계와 실행 단계를 분리하여 최종 이미지에는 실행에 필요한 최소한의 파일만 포함시키는 기법입니다.

-   **문제점**: 단일 `Dockerfile`에서는 빌드에 사용된 JDK, Gradle/Maven 캐시 등이 최종 이미지에 남아 용량을 차지합니다.
-   **해결책**:
    1.  **빌드 스테이지(Build Stage)**: JDK와 빌드 도구가 포함된 이미지에서 소스코드를 컴파일하고 `.jar` 파일을 생성합니다.
    2.  **실행 스테이지(Runtime Stage)**: 최소한의 JRE(Java Runtime Environment)만 포함된 경량 이미지에 빌드 스테이지에서 생성된 `.jar` 파일만 복사하여 최종 이미지를 만듭니다.

#### **Dockerfile 예시 (Before vs After)**

**❌ Before: 단일 스테이지**
```dockerfile
# 빌드 환경과 실행 환경이 분리되지 않음
FROM openjdk:17
COPY . .
RUN ./gradlew build
# 빌드 후 생성된 불필요한 파일들이 이미지에 남음
EXPOSE 8080
# 최종 이미지 크기: ~700MB+
ENTRYPOINT ["java", "-jar", "build/libs/app.jar"]
```

**✅ After: Multi-stage 빌드 적용**
```dockerfile
# 1. 빌드 스테이지
FROM openjdk:17-jdk-slim as builder
WORKDIR /app
COPY . .
RUN ./gradlew build --no-daemon

# 2. 실행 스테이지
FROM openjdk:17-jre-slim
WORKDIR /app
# 빌드 스테이지(builder)에서 .jar 파일만 복사
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
# 최종 이미지 크기: ~250MB
ENTRYPOINT ["java", "-jar", "app.jar"]
```


> **핵심**: Multi-stage 빌드를 통해 빌드 환경과 실행 환경을 분리함으로써, 최종 배포 이미지의 크기를 획기적으로 줄이고 보안성을 높일 수 있습니다.

---

### 2. **Docker Compose를 활용한 로컬 개발 환경 통일 및 관리**

백엔드 개발 시 애플리케이션 외에도 데이터베이스, 캐시 서버 등 여러 컴포넌트가 필요합니다. **Docker Compose**는 여러 컨테이너 애플리케이션을 정의하고 실행하기 위한 도구로, `docker-compose.yml` 파일 하나로 전체 개발 환경을 손쉽게 구성하고 관리할 수 있게 해줍니다.

-   **역할**: `docker-compose.yml`에 서비스(컨테이너), 네트워크, 볼륨 등을 정의하면, `docker-compose up` 명령어 한 번으로 모든 컨테이너를 실행할 수 있습니다.
-   **장점**:
    -   **환경 통일**: 모든 팀원이 동일한 환경에서 개발하여 "제 PC에선 됐는데..." 하는 문제를 방지합니다.
    -   **편의성**: 복잡한 `docker run` 명령어를 YAML 파일로 명시적으로 관리할 수 있습니다.
    -   **서비스 간 연결**: 내장된 네트워크 기능으로 서비스 이름(`mysql-db`)을 통해 컨테이너 간 통신이 가능합니다.

#### **docker-compose.yml 예시**
```yaml
version: '3.8'

services:
  # Spring Boot Application Service
  spring-app:
    build: . # 현재 디렉토리의 Dockerfile을 사용하여 이미지 빌드
    ports:
      - "8080:8080"
    depends_on: # mysql-db가 먼저 실행되도록 의존성 설정
      - mysql-db
    environment:
      - SPRING_DATASOURCE_URL=jdbc:mysql://mysql-db:3306/mydatabase
      - SPRING_DATASOURCE_USERNAME=user
      - SPRING_DATASOURCE_PASSWORD=password

  # MySQL Database Service
  mysql-db:
    image: mysql:8.0
    ports:
      - "3306:3306"
    environment:
      - MYSQL_DATABASE=mydatabase
      - MYSQL_USER=user
      - MYSQL_PASSWORD=password
      - MYSQL_ROOT_PASSWORD=rootpassword
    volumes:
      - mysql-data:/var/lib/mysql

volumes:
  mysql-data:
```

> **핵심**: Docker Compose는 복잡한 멀티 컨테이너 환경을 코드로 관리(Infrastructure as Code)하게 해주어, 로컬 개발 환경의 일관성과 생산성을 크게 향상시킵니다.

---

### 3. **Kubernetes 기초: Pod, Service, Deployment 개념과 Spring Boot 앱 배포 실습**

**Kubernetes(K8s)**는 컨테이너화된 애플리케이션을 자동으로 배포, 확장 및 관리하는 오픈소스 플랫폼입니다. Kubernetes의 가장 기본적인 핵심 구성요소는 다음과 같습니다.

-   **Pod**:
    -   Kubernetes에서 생성하고 관리하는 **가장 작은 배포 단위**.
    -   하나 이상의 컨테이너 그룹으로, Pod 안의 컨테이너들은 네트워크와 스토리지 같은 리소스를 공유합니다. 보통 1 Pod = 1 Container 구조를 많이 사용합니다.
-   **Service**:
    -   여러 Pod에 대한 **안정적인 단일 엔드포인트(IP 주소와 포트)**를 제공합니다.
    -   Pod는 생성되거나 재시작될 때마다 IP가 바뀔 수 있지만, Service의 IP는 고정되어 외부에서 Pod에 안정적으로 접근할 수 있게 해줍니다. (로드 밸런싱 기능 포함)
-   **Deployment**:
    -   Pod와 ReplicaSet(Pod의 복제본 개수를 유지)에 대한 **선언적인 명세**를 제공합니다.
    -   "애플리케이션 A의 Pod를 3개 유지하라"와 같이 원하는 상태를 정의하면, Deployment 컨트롤러가 현재 상태를 모니터링하며 그 상태를 유지합니다. 롤링 업데이트, 롤백 등의 배포 전략을 관리합니다.


#### **Deployment.yaml 예시**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-boot-app-deployment
spec:
  replicas: 3 # 3개의 Pod를 실행하도록 설정
  selector:
    matchLabels:
      app: spring-boot-app
  template:
    metadata:
      labels:
        app: spring-boot-app
    spec:
      containers:
      - name: my-spring-app
        image: your-docker-hub-id/my-spring-app:1.0 # Docker Hub에 푸시한 이미지
        ports:
        - containerPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: spring-boot-app-service
spec:
  selector:
    app: spring-boot-app # 위 Deployment의 Pod를 타겟으로 함
  ports:
    - protocol: TCP
      port: 80 # 외부에 노출될 포트
      targetPort: 8080 # 컨테이너가 사용하는 포트
  type: LoadBalancer # 외부에서 접근 가능한 로드 밸런서 타입의 서비스 생성
```

> **핵심**: **Deployment**는 애플리케이션의 실행 상태(몇 개의 Pod를 띄울지)를 정의하고, **Service**는 실행된 Pod 그룹에 외부 또는 내부에서 접근할 수 있는 안정적인 방법을 제공합니다.

---

## 💡 배운 점

1.  **이미지 최적화의 중요성**: Multi-stage 빌드는 단순한 용량 절감을 넘어, 배포 속도 향상과 보안 강화에 필수적인 기법임을 깨달았습니다.
2.  **개발 환경의 코드화**: Docker Compose를 통해 모든 팀원이 동일한 환경에서 개발하고 테스트할 수 있어 협업 효율을 극대화할 수 있습니다.
3.  **선언적 인프라 관리**: Kubernetes는 '어떻게'가 아닌 '무엇을' 정의하는 선언적 API를 통해, 복잡한 컨테이너 환경의 상태를 안정적으로 유지하고 자동화하는 강력한 패러다임을 제공한다는 것을 이해했습니다.

---

## 🔗 참고 자료

-   [Docker 공식 문서 - Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
-   [Docker Compose 공식 문서](https://docs.docker.com/compose/)
-   [Kubernetes 공식 문서 - Concepts](https://kubernetes.io/docs/concepts/)