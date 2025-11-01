---
title: "Chaos Engineering: 의도적으로 장애를 주입해 시스템 회복탄력성 검증하기"
date: 2025-11-01
categories: [DevOps, Architecture]
tags: [Chaos Engineering, Resilience, DevOps, Spring Boot, Chaos Monkey, TIL]
excerpt: "내 시스템의 Circuit Breaker나 Failover가 '정말로' 동작하는지 확인하기 위해 '의도적으로' 장애를 주입하는 Chaos Engineering의 개념을 학습합니다. Netflix의 Chaos Monkey 원리와 Spring Boot 환경에서 이를 적용하는 방법을 탐구합니다."
author_profile: true
---

# Today I Learned: Chaos Engineering: 의도적으로 장애를 주입해 시스템 회복탄력성 검증하기

## 📚 오늘 학습한 내용

저는 3~4년차 개발자로서 Resilience4j로 서킷 브레이커를 설정하고, 로드 밸런서 뒤에 여러 인스턴스를 띄우며 "장애에 대비된(Fault-tolerant)" 시스템을 만들고 있다고 생각했습니다. 하지만 오늘 "내가 만든 이 대비책이 **실제 장애 상황에서 정말 의도대로 동작할까?**"라는 근본적인 질문에 부딪혔습니다.

이론적인 대비를 넘어, 실제 시스템의 회복탄력성(Resilience)을 검증하기 위해 **의도적으로 장애를 주입**하는 **카오스 엔지니어링(Chaos Engineering)**에 대해 학습했습니다.

---

### 1. **카오스 엔지니어링이란? 🐒**

-   **개념**: 운영 환경(또는 Staging 환경)의 시스템에 **통제된 실험**을 통해 **의도적으로 장애(Faults)**를 주입하여, 시스템이 얼마나 잘 견디고 스스로 복구하는지 테스트하는 방법론입니다.
-   **비유**: 소방서가 건물에 경보를 울리고 연기를 피워 실제와 같은 **"소방 훈련"**을 하는 것과 같습니다. 화재 경보기가 잘 울리는지, 비상구가 막히지 않았는지, 사람들이 대피 요령을 아는지 미리 점검하는 것입니다.
-   **목표**: 장애가 실제로 발생하기 **전에** 시스템의 숨겨진 약점(e.g., 잘못 설정된 타임아웃, 전파되지 않는 장애, 동작하지 않는 Fallback)을 찾아내어, 더 강력한 시스템을 구축하는 것입니다.

---

### 2. **카오스 엔지니어링의 원칙 📜**

1.  **가설 수립**: "정상 상태"를 정의하고, 장애 주입 시 어떤 결과가 나올지 가설을 세웁니다.
    -   *가설 예시*: "Order 서비스의 인스턴스 1개를 강제 종료(Kill)시켜도, 로드 밸런서가 트래픽을 나머지 인스턴스로 보내므로, 전체 에러율은 0%를 유지하고 응답 시간은 10% 이내로 증가할 것이다."
2.  **실제 환경에서 실험**: Staging 환경도 좋지만, 가장 정확한 결과는 실제 트래픽이 흐르는 운영 환경(Production)에서 나옵니다. (물론, 매우 신중하게 시작해야 합니다.)
3.  **폭발 반경(Blast Radius) 최소화**: 처음에는 가장 작은 단위(e.g., 특정 Pod 1개, 내부 사용자 트래픽 1%)로 시작하여 실험의 영향을 통제합니다.
4.  **지속적인 자동화**: 시스템은 계속 변경되므로(새로운 코드 배포, 인프라 변경 등), 카오스 실험도 CI/CD 파이프라인의 일부처럼 지속적으로 실행되어야 합니다.

---

### 3. **Spring Boot 개발자를 위한 카오스 툴**

과거 Netflix의 **Chaos Monkey**가 AWS EC2 인스턴스를 무작위로 종료시키는 것으로 유명했지만, 이제는 더 정교한 도구들이 많습니다.

#### **① Chaos Mesh (K8s 환경)**
Kubernetes 네이티브 카오스 엔지니어링 플랫폼입니다. Pod를 죽이거나, 네트워크 지연/유실을 주입하는 등 K8s 환경의 거의 모든 장애를 YAML로 정의하여 실험할 수 있습니다.

```yaml
# 'my-spring-app' Pod 중 하나를 랜덤하게 10분마다 죽이는 실험
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-chaos
  namespace: my-app-ns
spec:
  action: pod-kill
  mode: one # 하나만
  selector:
    labels:
      app: my-spring-boot-app
  scheduler:
    cron: "@every 10m"
```

#### **② Chaos Monkey for Spring Boot (애플리케이션 레벨)**
인프라를 건드리지 않고, Spring Boot 애플리케이션 **내부**에서 직접 장애를 시뮬레이션하는 라이브러리입니다. (de.codecentric:chaos-monkey-spring-boot-starter)

-   **동작**: `@Service`, `@Controller` 등 Spring 컴포넌트의 메서드 호출을 AOP로 가로채어, 설정된 확률에 따라 강제로 지연(Latency)을 발생시키거나 예외(Exception)를 던집니다.
-   **활용**: "DB Repository가 3초간 응답이 없을 때, 내 `@CircuitBreaker`의 Fallback이 제대로 동작하는가?"를 테스트하기에 완벽합니다.

**`application.yml` 설정 예시**
```yaml
chaos:
  monkey:
    enabled: true
    watcher:
      # @Service, @Repository 빈을 공격 대상으로 지정
      service: true
      repository: true
    assaults:
      # 1. 지연(Latency) 주입 설정
      latencyActive: true
      latencyRangeStart: 2000 # 2초
      latencyRangeEnd: 5000   # 5초
      level: 10 # 10%의 요청에 대해 2~5초 사이의 랜덤 지연 발생

      # 2. 예외(Exception) 주입 설정
      exceptionsActive: true
      exceptionsType: java.io.IOException # IOException을 강제로 발생
      level: 5 # 5%의 요청에 대해 예외 발생
```

---

## 💡 배운 점

1.  **회복탄력성은 '가정'이 아닌 '검증'의 영역이다**: 코드로 `@CircuitBreaker`를 추가하고 로드 밸런서를 설정하는 것은 '가정'에 불과했습니다. 카오스 엔지니어링은 이 가정이 맞는지 '검증'하는 과학적인 방법입니다.
2.  **장애는 근무 시간에 일어나야 한다**: 새벽 3시에 장애 알람을 받고 대응하는 것(Reactive)보다, 화요일 오후 3시에 팀원들과 함께 통제된 장애를 발생시키고(Proactive) 대응책을 논의하는 것이 훨씬 생산적이고 안정적입니다.
3.  **`Chaos Monkey for Spring Boot`는 훌륭한 첫걸음이다**: K8s 인프라 전체를 흔드는 것이 두렵다면, `chaos-monkey-spring-boot` 라이브러리를 사용해 내 로컬이나 개발 환경에서부터 "내 코드가 예외 상황을 잘 처리하는지" 테스트하는 것부터 시작할 수 있습니다. 이는 3~4년차 개발자로서 코드의 견고성을 높이는 매우 실용적인 방법입니다.

---

## 🔗 참고 자료

-   [Principles of Chaos Engineering](https://principlesofchaos.org/)
-   [Chaos Mesh - Kubernetes Chaos Engineering](https://chaos-mesh.org/)
-   [Chaos Monkey for Spring Boot (GitHub)](https://github.com/codecentric/chaos-monkey-spring-boot)
-   [Netflix Chaos Monkey (Article)](https://netflix.github.io/chaosmonkey/)