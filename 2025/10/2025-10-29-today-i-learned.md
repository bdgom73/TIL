---
title: "K8s Liveness/Readiness Probes: 쿠버네티스와 Spring Boot의 '건강 대화법'"
date: 2025-10-29
categories: [DevOps, Kubernetes]
tags: [Kubernetes, Liveness Probe, Readiness Probe, Spring Boot Actuator, DevOps, MSA, TIL]
excerpt: "Spring Boot 애플리케이션을 Kubernetes에 배포할 때, K8s가 앱의 상태를 '정확히' 알 수 있게 하는 Liveness, Readiness, Startup Probes의 차이점과 중요성을 학습합니다. Spring Boot Actuator가 이와 어떻게 완벽하게 통합되는지 알아봅니다."
author_profile: true
---

# Today I Learned: K8s Liveness/Readiness Probes: 쿠버네티스와 Spring Boot의 '건강 대화법'

## 📚 오늘 학습한 내용

Spring Boot 애플리케이션을 개발하고 Docker 이미지를 만들어 Kubernetes(K8s)에 배포하는 것은 익숙한 업무가 되었습니다. 하지만 `Deployment` YAML을 `apply` 하고 나면, K8s는 그저 Pod 내부의 컨테이너가 '실행 중(Running)'이라는 사실만 알 뿐, **"애플리케이션이 정말로 트래픽을 받을 준비가 되었는지"** 혹은 **"지금은 괜찮지만 내부적으로 데드락(Deadlock)에 걸려 멈춘 것은 아닌지"** 알 수 없습니다.

오늘은 K8s가 내 애플리케이션의 '속사정'을 파악하고, 무중단 배포와 자가 치유(Self-healing)를 가능하게 하는 핵심 기능인 **Liveness, Readiness, Startup Probes**에 대해 학습했습니다.

---

### 1. **Probes: K8s가 애플리케이션의 상태를 묻는 방법**

K8s의 `kubelet`은 주기적으로 컨테이너에게 '신호(Probe)'를 보내어 건강 상태를 확인합니다. 이 신호에는 세 가지 종류가 있습니다.

#### **① Startup Probe (시동 확인)**
-   **질문**: "애플리케이션 시동이 오래 걸리는 중이니? 아직 부팅 중이야?"
-   **역할**: Spring Boot처럼 초기 구동 시간이 긴 애플리케이션을 위한 프로브입니다. 이 프로브가 성공할 때까지, K8s는 다른 프로브(Liveness, Readiness)의 실행을 **유예**합니다.
-   **실패 시**: 설정된 `failureThreshold` 횟수만큼 실패하면, K8s는 이 Pod의 시동이 실패했다고 간주하고 **즉시 재시작(Restart)**시킵니다.

#### **② Readiness Probe (영업 준비 확인)**
-   **질문**: "지금 당장 새로운 손님(트래픽)을 받을 준비가 되었니?"
-   **역할**: 이 프로브가 **성공**해야만, K8s는 `Service`의 엔드포인트 목록에 이 Pod를 추가하여 실제 트래픽을 보내기 시작합니다.
-   **실패 시**: K8s는 Pod를 **재시작하지 않습니다.** 대신, `Service`에서 이 Pod를 **일시적으로 제외**하고 트래픽을 보내지 않습니다. 애플리케이션이 일시적으로 과부하 상태이거나(e.g., DB 커넥션 풀 고갈), 캐시를 워밍업하는 중일 때 유용합니다.
-   **핵심**: **무중단 배포(Zero-downtime Rolling Update)**의 핵심입니다. 새 버전의 Pod가 'Ready' 상태가 될 때까지 K8s가 트래픽을 보내지 않고 기다려줍니다.

#### **③ Liveness Probe (생존 확인)**
-   **질문**: "애플리케이션이 아직 살아있니? 응답은 하니?"
-   **역할**: 애플리케이션이 교착 상태(Deadlock)에 빠지는 등, 실행은 되고 있지만 더 이상 정상 작동하지 않는 '좀비 상태'를 감지합니다.
-   **실패 시**: K8s는 이 Pod가 회복 불가능한 상태라고 판단하고, **즉시 재시작(Restart)**시킵니다. (자가 치유)



---

### 2. **Spring Boot Actuator: K8s를 위한 완벽한 파트너 🤝**

K8s가 상태를 물어볼 때, Spring Boot는 **Actuator**의 헬스 체크 엔드포인트를 통해 완벽하게 대답할 수 있습니다.

**1. 의존성 추가**
```groovy
implementation 'org.springframework.boot:spring-boot-starter-actuator'
```

**2. `application.yml` 설정**
K8s 환경에서 Actuator를 사용하기 위한 핵심 설정입니다.
```yaml
management:
  endpoints:
    web:
      exposure:
        # health 엔드포인트만 노출 (보안상)
        include: health
  endpoint:
    health:
      # K8s 프로브가 HTTP /actuator/health/liveness, /actuator/health/readiness를
      # 사용할 수 있도록 활성화
      probes:
        enabled: true
      # DB, Redis 등과의 연결 상태를 readiness에만 포함시킴
      # liveness는 앱 자체의 생존만 확인하도록 함
      group:
        readiness:
          include: db,redis
```

-   **`/actuator/health/liveness`**: 애플리케이션 자체가 실행 중인지(Live) 확인합니다. Spring Boot는 앱이 구동되면 항상 `{"status":"UP"}`을 반환합니다.
-   **`/actuator/health/readiness`**: 애플리케이션이 트래픽을 받을 준비가 되었는지(Ready) 확인합니다. `readiness` 그룹에 포함된 `db`, `redis` 등의 상태가 모두 정상이 되어야만 `{"status":"UP"}`을 반환합니다.

---

### 3. **Kubernetes Deployment YAML에 적용하기**

이제 K8s `Deployment` 파일에 위에서 활성화한 Actuator 엔드포인트를 지정합니다.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-spring-app
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: my-app
        image: my-app-image:v1.0
        ports:
        - containerPort: 8080
        
        # 1. Startup Probe: 8080 포트가 열릴 때까지 기다림 (TCP 방식)
        startupProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 15 # 앱 시작 후 15초 뒤부터 검사 시작
          failureThreshold: 30    # 30번 실패하면(총 5분) 재시작
          periodSeconds: 10
        
        # 2. Readiness Probe: DB, Redis 등이 모두 연결되었는지 확인
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness # Actuator의 Readiness 엔드포인트
            port: 8080
          initialDelaySeconds: 5  # Startup 성공 후 5초 뒤부터 검사
          periodSeconds: 5
        
        # 3. Liveness Probe: 앱이 살아있는지(데드락 등) 확인
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness # Actuator의 Liveness 엔드포인트
            port: 8080
          initialDelaySeconds: 30 # Startup 성공 후 30초 뒤부터 검사
          failureThreshold: 3
          periodSeconds: 10
```

---

## 💡 배운 점

1.  **"Running"과 "Ready"는 완전히 다른 상태다**: Pod의 상태가 `Running`이라고 해서 `Service`가 트래픽을 보내도 된다는 뜻이 아님을 명확히 이해했습니다. `Readiness Probe`가 성공해야만 비로소 '영업 시작' 상태가 되며, 이는 무중단 롤링 업데이트의 핵심 전제 조건입니다.
2.  **Liveness Probe는 함부로 사용하면 위험하다**: Liveness Probe가 실패하면 K8s는 Pod를 즉시 재시작합니다. 만약 DB 장애로 인해 `livenessProbe`가 DB 상태까지 체크하도록 잘못 설정했다면, DB 장애가 발생했을 때 모든 앱 Pod가 동시에 무한 재시작에 빠지는 **'재시작 연쇄 장애(Crash Loop)'**가 발생할 수 있습니다. Liveness는 앱 자체의 생존(데드락 등)만 가볍게 확인하고, 외부 의존성은 Readiness로 분리해야 합니다.
3.  **Spring Boot Actuator는 K8s를 위해 태어났다**: `management.endpoint.health.probes.enabled=true` 설정 하나만으로 Liveness/Readiness 엔드포인트가 분리되고, Spring이 알아서 'Ready' 상태를 관리해준다는 점에서 Actuator가 단순한 모니터링 도구를 넘어, 클라우드 네이티브 환경의 핵심 오케스트레이션 파트너임을 깨달았습니다.

---

## 🔗 참고 자료

-   [K8s Docs - Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
-   [Spring Boot Docs - Kubernetes Probes](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.cloud-native-features.kubernetes-probes)