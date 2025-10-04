---
title: "GitOps란 무엇인가: ArgoCD로 구현하는 선언적 배포"
date: 2025-10-05
categories: [DevOps, CI/CD]
tags: [GitOps, ArgoCD, Kubernetes, CI/CD, Declarative, TIL]
excerpt: "현대적인 지속적 배포(CD) 패러다임인 GitOps의 핵심 개념을 학습합니다. Git을 '신뢰할 수 있는 단일 소스(Single Source of Truth)'로 사용하여 쿠버네티스 환경의 상태를 선언적으로 관리하는 방법을 알아보고, 대표적인 GitOps 도구인 ArgoCD의 동작 원리를 탐구합니다."
author_profile: true
---

# Today I Learned: GitOps란 무엇인가: ArgoCD로 구현하는 선언적 배포

## 📚 오늘 학습한 내용

GitHub Actions 같은 CI/CD 도구를 사용하면 빌드와 배포를 자동화할 수 있지만, "현재 운영 환경의 상태는 정확히 어떠한가?"라는 질문에 답하기는 어렵습니다. 스크립트 기반의 배포는 실행 시점의 환경 변수나 작은 실수로 인해 예기치 않은 결과를 낳을 수 있기 때문입니다. 오늘은 이러한 문제를 해결하고 배포의 안정성과 신뢰성을 한 차원 높이는 **GitOps**라는 패러다임과, 이를 구현하는 대표적인 도구 **ArgoCD**에 대해 학습했습니다.

---

### 1. **GitOps: Git으로 운영 환경을 관리하다**

**GitOps**는 애플리케이션과 인프라의 **'원하는 상태(Desired State)'를 Git 저장소에 선언적으로 정의**하고, 이 Git 저장소를 **신뢰할 수 있는 단일 소스(Single Source of Truth)**로 삼아 운영 환경의 상태를 자동으로 동기화하는 방식입니다.

-   **기존 CI/CD (Push 방식) vs. GitOps (Pull 방식)**
    -   **전통적인 방식 (Push-based)**: Jenkins나 GitHub Actions 같은 CI 서버가 빌드가 끝나면 `kubectl apply`와 같은 명령어를 실행하여 쿠버네티스 클러스터에 직접 변경사항을 **밀어 넣습니다(Push)**. 이 방식은 CI 서버가 클러스터에 접근할 수 있는 강력한 권한을 가져야 하므로 보안에 취약할 수 있습니다.
    -   **GitOps 방식 (Pull-based)**: 클러스터 내부에 설치된 에이전트(Operator)가 Git 저장소를 지속적으로 감시하다가, 변경 사항이 발생하면 스스로 클러스터의 상태를 Git에 정의된 상태와 일치하도록 **끌어옵니다(Pull)**. 이 방식은 클러스터 외부에서 직접적인 접근이 필요 없어 훨씬 안전합니다.



> **핵심**: GitOps의 철학은 `git push`가 배포의 유일한 트리거가 되어야 한다는 것입니다. `kubectl`로 직접 클러스터를 변경하는 행위는 금지되며, 모든 변경은 Git의 커밋과 Pull Request를 통해 투명하게 관리됩니다.

---

### 2. **ArgoCD: 쿠버네티스를 위한 GitOps 자동화 도구**

**ArgoCD**는 쿠버네티스 환경을 위한 대표적인 오픈소스 GitOps, 즉 지속적 배포(Continuous Delivery) 도구입니다.

-   **핵심 원리: 자동 동기화와 재조정(Reconciliation)**
    1.  ArgoCD는 쿠버네티스 클러스터에 설치되어 실행됩니다.
    2.  사용자는 ArgoCD에 "이 Git 저장소의 이 폴더에 있는 쿠버네티스 YAML 파일들을 모니터링해줘"라고 애플리케이션을 등록합니다.
    3.  ArgoCD는 주기적으로 Git 저장소에 정의된 **원하는 상태(Desired State)**와 실제 클러스터의 **현재 상태(Live State)**를 비교합니다.
    4.  만약 두 상태가 다르다면(e.g., Git에는 `image: v2`인데 클러스터에는 `v1`이 떠 있는 경우), ArgoCD는 이 상태를 `OutOfSync`로 표시합니다.
    5.  자동 동기화(Auto-Sync) 옵션이 켜져 있다면, ArgoCD는 즉시 클러스터의 상태를 Git과 일치하도록 변경(e.g., `v2` 이미지로 Pod를 업데이트)합니다. 이 과정을 **재조정(Reconciliation)**이라고 합니다.



-   **장점**:
    -   **신뢰성**: Git이 모든 상태를 관리하므로, 언제든지 특정 커밋으로 롤백하거나 시스템 상태를 복구하기 쉽습니다.
    -   **보안**: 클러스터 외부로 인증 정보를 노출할 필요가 없습니다.
    -   **투명성**: 모든 변경 사항은 Git의 커밋 기록으로 남기 때문에, 누가, 언제, 무엇을 변경했는지 추적하기 매우 용이합니다.

---

### 3. **ArgoCD 동작 흐름 예시**

1.  **개발자**: 새로운 기능 개발을 완료하고, 쿠버네티스 `Deployment` YAML 파일의 이미지 태그를 `my-app:1.0`에서 `my-app:1.1`로 변경합니다.

2.  **Git**: 개발자는 변경된 YAML 파일을 Git 저장소의 `main` 브랜치에 `git push`합니다. 이 과정에서 동료의 코드 리뷰를 위해 Pull Request를 생성하고 승인을 받을 수 있습니다.

3.  **ArgoCD**: 클러스터에서 실행 중인 ArgoCD는 Git 저장소의 변경을 감지하고, 현재 클러스터에 배포된 이미지(`1.0`)와 Git에 정의된 이미지(`1.1`)가 다르다는 것을 인지하여 `OutOfSync` 상태로 전환합니다.

4.  **쿠버네티스 클러스터**: ArgoCD가 자동으로 동기화를 실행하여 `Deployment`의 이미지 태그를 `1.1`로 업데이트하는 `kubectl apply` 명령을 내부적으로 수행합니다. 쿠버네티스는 롤링 업데이트 전략에 따라 새로운 버전의 애플리케이션 Pod를 안전하게 배포합니다.

이 모든 과정은 개발자가 Git에 코드를 푸시하는 것만으로 자동으로, 그리고 선언적으로 이루어집니다.

---

## 💡 배운 점

1.  **GitOps는 '무엇을'에 집중한다**: 전통적인 CI/CD 파이프라인이 '어떻게' 배포할 것인지(e.g., 스크립트 실행 순서)에 초점을 맞춘다면, GitOps는 '무엇을' 배포할 것인지(e.g., 최종 상태를 정의한 YAML)에 집중합니다. 이러한 선언적 접근 방식이 시스템의 예측 가능성과 안정성을 크게 높여준다는 것을 알게 되었습니다.
2.  **Git이 단순한 코드 저장소 이상이 되다**: GitOps 환경에서 Git은 코드뿐만 아니라 인프라와 애플리케이션의 상태까지 모두 관리하는 중앙 관제 센터 역할을 합니다. 코드 리뷰, 버전 관리 등 Git의 강력한 기능들을 운영 환경 관리에 그대로 적용할 수 있다는 점이 매우 인상적이었습니다.
3.  **개발자와 운영의 경계를 허물다**: 개발자가 배포 스크립트나 인프라에 대한 깊은 지식 없이도, 익숙한 Git 워크플로우(PR 생성 및 병합)를 통해 직접 배포에 참여할 수 있게 됩니다. 이는 진정한 의미의 DevOps 문화를 촉진하는 강력한 도구가 될 수 있음을 깨달았습니다.

---

## 🔗 참고 자료

-   [Guide To GitOps (Weaveworks)](https://www.weave.works/technologies/gitops/)
-   [ArgoCD - Declarative GitOps CD for Kubernetes (Official Documentation)](https://argo-cd.readthedocs.io/en/stable/)
-   [What is GitOps? (Red Hat)](https://www.redhat.com/en/topics/devops/what-is-gitops)