---
title: "배포 중 502 에러 박멸하기: Spring Boot Graceful Shutdown과 Kubernetes 라이프사이클"
date: 2025-12-29
categories: [Spring, DevOps, Kubernetes]
tags: [Graceful Shutdown, Kubernetes, Zero Downtime, Spring Boot, SIGTERM, Lifecycle, TIL]
excerpt: "무중단 배포를 지향하지만 롤링 업데이트 시 간헐적으로 발생하는 502 Bad Gateway 에러의 원인을 분석합니다. Spring Boot 2.3+의 Graceful Shutdown 설정과 Kubernetes의 Pod 라이프사이클(SIGTERM 전파 지연)을 이해하고, preStop 훅을 이용해 완벽한 종료 전략을 구현합니다."
author_profile: true
---

# Today I Learned: 배포 중 502 에러 박멸하기: Spring Boot Graceful Shutdown과 Kubernetes 라이프사이클

## 📚 오늘 학습한 내용

Kubernetes 환경에서 롤링 업데이트(Rolling Update)로 배포를 진행할 때, 파드(Pod)가 교체되는 찰나의 순간에 **502 Bad Gateway**나 **Connection Refused** 에러가 발생한다는 CS 문의를 받았습니다.

단순히 "파드가 켜지고 꺼질 때 트래픽이 새는구나"라고 넘기기엔 3년 차 개발자로서 자존심이 허락하지 않아, Spring Boot 애플리케이션이 **종료 신호(SIGTERM)**를 받았을 때 어떻게 동작하는지, 그리고 k8s의 트래픽 차단 시점과 어떻게 조화를 이뤄야 하는지 깊게 파고들었습니다.

---

### 1. **문제의 원인: SIGTERM과 트래픽 차단의 시차 📉**

쿠버네티스가 파드를 종료할 때 보내는 `SIGTERM` 신호와, 로드밸런서(Service/Ingress)가 해당 파드로 트래픽을 차단하는 시점은 **비동기적**으로 일어납니다.

1.  K8s가 파드 삭제 명령을 내림 -> 파드 상태를 `Terminating`으로 변경.
2.  (동시에) Endpoint 컨트롤러가 Service의 Endpoint 목록에서 해당 파드 IP를 제거 (트래픽 차단 시작).
3.  (동시에) Kubelet이 컨테이너에 `SIGTERM` 전송.

**문제점**: 2번(트래픽 차단)이 전파되기 전에 3번(앱 종료)이 먼저 일어나면, **여전히 트래픽은 들어오는데 애플리케이션은 이미 죽어있는 상황**이 발생합니다. 이것이 배포 중 간헐적 502 에러의 주범입니다.

---

### 2. **해결책 1: Spring Boot Graceful Shutdown 🍃**

Spring Boot 2.3부터는 설정 한 줄로 **우아한 종료(Graceful Shutdown)**를 지원합니다.

**application.yml**
```yaml
server:
  shutdown: graceful # 기본값은 immediate (즉시 종료)
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s # 최대 30초까지 기다림
```

**동작 방식**:
1.  `SIGTERM`을 받으면 즉시 톰캣(Tomcat)의 **새로운 요청 접수를 중단**합니다.
2.  하지만 **이미 처리 중인(In-flight) 요청**이 있다면, 처리가 끝날 때까지 기다려줍니다.
3.  모든 요청이 처리되거나 타임아웃(30s)이 지나면 그때 프로세스를 종료합니다.

---

### 3. **해결책 2: Kubernetes preStop Hook ⚓️**

Spring Boot 설정을 해도, 앞서 말한 "트래픽 차단보다 앱 종료가 빨라버리는 문제"는 해결되지 않습니다. 이를 위해 **`preStop`** 훅을 사용해 SIGTERM 수신을 고의로 지연시켜야 합니다.

**deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
spec:
  template:
    spec:
      containers:
        - name: my-api
          image: my-repo/my-api:v1
          # ...
          lifecycle:
            preStop:
              exec:
                # SIGTERM을 받기 전에 20초 동안 대기
                # 이 시간 동안 K8s는 Endpoint 목록에서 파드를 제거하고 iptables를 갱신함
                command: ["/bin/sh", "-c", "sleep 20"]
```

---

### 4. **완벽한 종료 시퀀스 정리 🎬**

이 두 가지 설정을 모두 적용했을 때의 이상적인 종료 흐름입니다.



1.  **K8s**: 파드 종료 시작 (`Terminating`).
2.  **K8s**: `preStop` 훅 실행 (`sleep 20`).
    -   애플리케이션은 아직 정상 동작 중 (요청 처리 가능).
    -   동시에 K8s는 로드밸런서에서 파드 IP 제거 중 (약 5~10초 소요).
3.  **K8s**: 20초 후 `sleep` 종료 -> 컨테이너에 `SIGTERM` 전송.
4.  **Spring Boot**: `SIGTERM` 감지 -> **Graceful Shutdown** 시작.
    -   새로운 요청 거부 (이미 LB에서 차단되어 거의 안 들어옴).
    -   처리 중이던 마지막 요청들 마무리.
5.  **Spring Boot**: 모든 스레드 정리 완료 -> 앱 종료.
6.  **K8s**: 파드 완전 삭제.

---

### 5. **주의사항: 타임아웃 계산 🧮**

K8s의 `terminationGracePeriodSeconds`(기본 30초) 설정은 `preStop` 시간과 `Spring Boot Shutdown` 시간을 합친 것보다 길어야 합니다.

-   **공식**: `terminationGracePeriodSeconds` > `preStop(sleep)` + `spring.lifecycle.timeout`
-   **예시**:
    -   `preStop`: 20s
    -   `spring timeout`: 30s
    -   **K8s `terminationGracePeriodSeconds`**: 최소 **60s** 이상으로 설정 권장.

```yaml
spec:
  terminationGracePeriodSeconds: 60 # 넉넉하게 설정
  containers:
    - name: my-api
      # ...
```

---

## 💡 배운 점

1.  **배포는 속도가 아니라 안정성**: 배포 시간이 20초 늘어나는 것보다, 단 1건의 사용자 요청이라도 에러 없이 처리하는 것이 훨씬 중요하다는 것을 깨달았습니다.
2.  **인프라와 코드의 2인 3각**: 단순히 Spring 설정만 한다고 되는 것도 아니고, K8s 설정만 한다고 되는 것도 아닙니다. 애플리케이션 레벨(Spring)과 오케스트레이션 레벨(K8s)의 라이프사이클이 맞물려야 진정한 무중단이 완성됩니다.
3.  **TCP Connection Draining**: Graceful Shutdown은 단순히 HTTP 요청뿐만 아니라, DB 커넥션 풀이나 Kafka 컨슈머 스레드도 안전하게 닫을 수 있는 시간을 벌어주어 데이터 정합성 유지에도 큰 도움이 됩니다.

---

## 🔗 참고 자료

-   [Spring Boot Reference - Graceful Shutdown](https://docs.spring.io/spring-boot/docs/current/reference/html/web.html#web.graceful-shutdown)
-   [Kubernetes Pod Lifecycle - Termination of Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination)
-   [Google Cloud - Best practices for building containers (Signal handling)](https://cloud.google.com/architecture/best-practices-for-building-containers#signal-handling)