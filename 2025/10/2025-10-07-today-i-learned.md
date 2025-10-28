---
title: "쿠버네티스 패키지 매니저: Helm으로 애플리케이션 관리하기"
date: 2025-10-07
categories: [DevOps, Kubernetes]
tags: [Helm, Kubernetes, Package Manager, Chart, CI/CD, TIL]
excerpt: "쿠버네티스 애플리케이션을 배포할 때 발생하는 복잡한 YAML 파일 관리 문제를 해결하는 패키지 매니저 Helm의 필요성과 핵심 개념을 학습합니다. Chart, Release 등 Helm의 구성 요소를 이해하고, 템플릿을 활용한 효율적인 배포 관리 방법을 탐구합니다."
author_profile: true
---

# Today I Learned: 쿠버네티스 패키지 매니저: Helm으로 애플리케이션 관리하기

## 📚 오늘 학습한 내용

쿠버네티스에 애플리케이션 하나를 배포하려면 `Deployment`, `Service`, `ConfigMap`, `Secret`, `Ingress` 등 수많은 YAML 파일을 작성하고 관리해야 합니다. 애플리케이션이 복잡해질수록 이 파일들은 서로 의존성을 가지며 관리하기가 매우 어려워집니다. 오늘은 이러한 문제를 해결하고 쿠버네티스 애플리케이션의 설치, 업그레이드, 롤백을 표준화된 방식으로 관리해주는 **쿠버네티스 패키지 매니저, Helm**에 대해 학습했습니다.

---

### 1. **왜 Helm이 필요한가? YAML 관리의 어려움**

-   **중복과 비일관성**: 개발, 스테이징, 운영 환경마다 미묘하게 다른 설정(DB 주소, 복제본 수 등)을 가진 YAML 파일들을 별도로 관리해야 합니다. 이 과정에서 설정이 누락되거나 실수할 가능성이 매우 높습니다.
-   **복잡한 의존성**: 내 애플리케이션이 `Redis`나 `MySQL` 같은 다른 애플리케이션에 의존할 경우, 이들의 YAML 파일까지 함께 관리해야 합니다.
-   **배포 관리의 어려움**: 애플리케이션을 새로운 버전으로 업그레이드하거나, 문제가 생겼을 때 이전 버전으로 롤백하는 과정이 복잡하고 실수가 발생하기 쉽습니다.

Helm은 이러한 문제들을 `apt`(Ubuntu)나 `yum`(CentOS) 같은 리눅스 패키지 매니저처럼, 쿠버네티스 애플리케이션을 하나의 **'패키지'**로 묶어 해결합니다.

---

### 2. **Helm의 핵심 개념**

Helm은 세 가지 핵심 개념으로 이루어져 있습니다.

-   **Chart (차트) 📦**
    -   **의미**: 쿠버네티스 애플리케이션을 배포하는 데 필요한 모든 리소스(YAML 파일, 설정 값 등)를 모아놓은 **패키지**입니다. 차트는 정해진 디렉토리 구조를 가집니다.
    -   `Chart.yaml`: 차트의 이름, 버전 등 메타데이터 정보.
    -   `templates/`: 쿠버네티스 리소스 YAML 파일들의 **템플릿**이 위치하는 곳.
    -   `values.yaml`: 템플릿에 주입될 **기본 설정 값**들을 정의하는 파일.

-   **Release (릴리즈) 🚀**
    -   **의미**: 특정 설정 값(`values.yaml`)을 사용하여 클러스터에 배포된 **실행 중인 차트의 인스턴스**입니다.
    -   하나의 차트를 여러 다른 설정으로 여러 번 배포할 수 있으며, 각각은 고유한 이름의 릴리즈가 됩니다. (e.g., `my-app-staging`, `my-app-production`)

-   **Repository (리포지토리) 📚**
    -   **의미**: 배포하고 공유할 수 있는 차트들을 모아놓은 **저장소**입니다. 공개적으로 사용 가능한 리포지토리(e.g., Bitnami)를 추가하거나, 사내용 비공개 리포지토리를 구축할 수도 있습니다.



---

### 3. **Helm의 동작 방식: 템플릿과 값의 조합**

Helm의 가장 강력한 기능은 **템플릿(Templating)**입니다. `templates/` 디렉토리의 YAML 파일들은 고정된 값이 아닌, 변수를 가진 템플릿 형태입니다. 실제 배포 시 이 변수들은 `values.yaml` 파일의 값으로 채워져 최종 YAML 파일이 생성됩니다.

#### **예시: `values.yaml`과 `deployment.yaml` 템플릿**

**`values.yaml` (설정 값 정의)**
```yaml
replicaCount: 1 # 배포할 Pod의 개수

image:
  repository: nginx
  tag: stable
  pullPolicy: IfNotPresent
```

**`templates/deployment.yaml` (템플릿)**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx-deployment
spec:
  # {{ .Values.replicaCount }} : values.yaml 파일의 replicaCount 값을 가져와 사용
  replicas: {{ .Values.replicaCount }} 
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          # 이미지 정보도 values.yaml에서 가져옴
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
```

-   **배포 (Install)**: `helm install my-release ./my-chart` 명령을 실행하면, Helm은 `values.yaml`의 값을 `deployment.yaml` 템플릿에 적용하여 `replicas: 1` 과 `image: "nginx:stable"` 을 가진 최종 YAML을 생성하고 클러스터에 배포합니다.

-   **업그레이드 (Upgrade)**: 스테이징 환경에 배포할 때, `values.yaml`을 복사하여 `values-staging.yaml`을 만들고 `replicaCount: 3`으로 변경한 뒤, `helm upgrade my-release ./my-chart -f values-staging.yaml` 명령으로 쉽게 설정을 변경하여 배포할 수 있습니다.

-   **롤백 (Rollback)**: `helm rollback my-release 1` 명령으로 간단하게 이전 버전(리비전 1)으로 되돌릴 수 있습니다.

---

## 💡 배운 점

1.  **YAML은 코드가 아닌 설정이다**: Helm을 사용하면서 쿠버네티스 YAML을 '한 번 작성하고 끝나는 코드'가 아니라, 환경에 따라 동적으로 변경될 수 있는 '설정'으로 바라보게 되었습니다. 템플릿과 값 파일을 분리하는 접근 방식은 설정 관리의 복잡성을 크게 낮춰줍니다.
2.  **재사용성과 표준화의 힘**: 잘 만들어진 차트는 팀 내에서, 혹은 커뮤니티 전체에서 재사용될 수 있습니다. Redis나 Jenkins 같은 복잡한 애플리케이션도 `helm install` 명령어 한 줄로 설치할 수 있다는 것은 배포 프로세스의 표준화와 생산성 향상에 엄청난 이점임을 깨달았습니다.
3.  **배포는 '관리'의 영역이다**: 단순히 리소스를 클러스터에 적용하는 것을 넘어, Helm은 배포된 애플리케이션의 버전을 추적(리비전 관리)하고, 업그레이드와 롤백을 체계적으로 관리할 수 있게 해줍니다. 이는 안정적인 서비스 운영을 위한 필수적인 기능임을 알게 되었습니다.

---

## 🔗 참고 자료

-   [Helm 공식 문서](https://helm.sh/docs/)
-   [Artifact Hub (공개 Helm Chart 검색)](https://artifacthub.io/)
-   [Introduction to Helm (Kubernetes.io)](https://kubernetes.io/blog/2016/10/helm-an-introduction/)