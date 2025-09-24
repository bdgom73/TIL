---
title: "GitHub Actions으로 Spring Boot CI/CD 파이프라인 구축하기"
date: 2025-09-24
categories: [DevOps, CI/CD]
tags: [GitHub Actions, Spring Boot, CI, CD, Gradle, Docker, TIL]
excerpt: "GitHub Actions를 활용하여 Spring Boot 애플리케이션의 빌드, 테스트, 배포 전 과정을 자동화하는 CI/CD 파이프라인을 구축하는 방법을 학습합니다. 워크플로우 YAML 파일 작성부터 Secret 관리까지의 핵심 과정을 다룹니다."
author_profile: true
---

# Today I Learned: GitHub Actions으로 Spring Boot CI/CD 파이프라인 구축하기

## 📚 오늘 학습한 내용

코드를 GitHub에 푸시(Push)하는 것만으로 빌드, 테스트, 배포가 자동으로 이루어진다면 개발 생산성은 크게 향상될 것입니다. **GitHub Actions**는 이러한 CI/CD(지속적 통합/지속적 배포) 파이프라인을 GitHub 저장소 내에서 직접 구축할 수 있게 해주는 강력한 도구입니다. 오늘은 GitHub Actions를 이용해 간단한 Spring Boot 애플리케이션의 CI/CD 파이프라인을 구축하는 과정을 학습했습니다.

---

### 1. **GitHub Actions 핵심 개념**

GitHub Actions는 특정 **이벤트(Event)**가 발생했을 때, 사전에 정의된 일련의 작업 **워크플로우(Workflow)**를 실행시키는 자동화 서비스입니다.

-   **Workflow**: 하나 이상의 잡(Job)으로 구성된 자동화된 프로세스 전체. `.github/workflows/` 디렉토리 아래 YAML 파일로 정의합니다.
-   **Event**: 워크플로우를 실행시키는 특정 활동. 예: `push`, `pull_request`, `schedule` 등.
-   **Job**: 워크플로우를 구성하는 작업 단위. 여러 스텝(Step)으로 구성되며, 가상 머신(Runner)에서 실행됩니다.
-   **Step**: 잡을 구성하는 개별 명령어 또는 액션. 셸 명령어를 실행하거나, 미리 만들어진 **Action**을 사용할 수 있습니다.
-   **Action**: 워크플로우의 가장 작은 빌딩 블록. 자주 사용되는 자동화 작업을 재사용 가능하도록 만들어 놓은 것. 예: `actions/checkout`, `actions/setup-java`.



---

### 2. **Spring Boot CI/CD 워크플로우 작성하기**

이제 `main` 브랜치에 코드가 푸시될 때마다 자동으로 빌드, 테스트를 수행하고, Docker 이미지를 빌드하여 Docker Hub에 푸시하는 워크플로우를 작성해 보겠습니다.

#### **`.github/workflows/spring-boot-ci.yml`**

```yaml
# 워크플로우의 이름
name: Spring Boot CI/CD with GitHub Actions

# 워크플로우를 실행시킬 이벤트 정의
on:
  push:
    branches: [ "main" ] # main 브랜치에 push가 발생했을 때 실행

# 실행될 잡(Job)들을 정의
jobs:
  build-and-push-docker-image:
    # 잡이 실행될 가상 환경 지정
    runs-on: ubuntu-latest

    # 잡 내에서 실행될 스텝(Step)들을 정의
    steps:
      # 1. 소스 코드 체크아웃
      - name: Checkout source code
        uses: actions/checkout@v3

      # 2. JDK 17 설치
      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'temurin'

      # 3. Gradle Wrapper에 실행 권한 부여
      - name: Grant execute permission for gradlew
        run: chmod +x ./gradlew

      # 4. Spring Boot 애플리케이션 빌드 (테스트 포함)
      - name: Build with Gradle
        run: ./gradlew build --no-daemon

      # 5. Docker Hub 로그인
      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      # 6. Docker 이미지 빌드 및 푸시
      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: ${{ secrets.DOCKERHUB_USERNAME }}/my-spring-app:latest

      # (선택) 7. 배포 서버에 SSH 접속하여 컨테이너 재시작
      # - name: Deploy to Server
      #   uses: appleboy/ssh-action@master
      #   with:
      #     host: ${{ secrets.SERVER_HOST }}
      #     username: ${{ secrets.SERVER_USERNAME }}
      #     key: ${{ secrets.SSH_PRIVATE_KEY }}
      #     script: |
      #       docker stop my-spring-app-container || true
      #       docker rm my-spring-app-container || true
      #       docker pull ${{ secrets.DOCKERHUB_USERNAME }}/my-spring-app:latest
      #       docker run -d --name my-spring-app-container -p 8080:8080 ${{ secrets.DOCKERHUB_USERNAME }}/my-spring-app:latest
```

---

### 3. **GitHub Secrets 설정: 민감 정보 안전하게 관리하기**

워크플로우 파일에 Docker Hub 계정 정보나 서버 접속 키 같은 민감한 정보를 직접 작성하는 것은 매우 위험합니다. GitHub는 이러한 정보를 안전하게 암호화하여 저장할 수 있는 **Secrets** 기능을 제공합니다.

1.  **GitHub 저장소** > **Settings** 탭으로 이동합니다.
2.  왼쪽 메뉴에서 **Secrets and variables** > **Actions**를 선택합니다.
3.  **New repository secret** 버튼을 클릭하여 Secret을 추가합니다.
    -   `DOCKERHUB_USERNAME`: Docker Hub 사용자 이름
    -   `DOCKERHUB_TOKEN`: Docker Hub Access Token
    -   `SERVER_HOST`, `SERVER_USERNAME`, `SSH_PRIVATE_KEY` 등 배포에 필요한 정보

이렇게 등록된 Secret은 워크플로우 파일 내에서 `${{ secrets.SECRET_NAME }}` 구문을 통해 안전하게 참조할 수 있습니다.



---

### 4. **워크플로우 실행 결과 확인**

워크플로우 파일이 저장소의 `.github/workflows/` 경로에 추가되면, `main` 브랜치에 푸시가 발생할 때마다 자동으로 실행됩니다.

-   **GitHub 저장소**의 **Actions** 탭에서 실행 중이거나 완료된 워크플로우의 목록과 상태(성공/실패)를 확인할 수 있습니다.
-   특정 워크플로우를 클릭하면 각 잡(Job)과 스텝(Step)의 상세한 실행 로그를 볼 수 있어, 문제가 발생했을 때 원인을 쉽게 파악할 수 있습니다.

---

## 💡 배운 점

1.  **CI/CD의 접근성**: 과거에는 Jenkins 등 별도의 서버를 구축해야 했던 CI/CD 환경을, GitHub Actions를 통해 YAML 파일 하나만으로 매우 간단하게 구축할 수 있다는 점이 인상적이었습니다.
2.  **선언적 파이프라인**: 워크플로우를 코드로 관리함으로써 파이프라인의 모든 과정을 명시적으로 정의하고 버전 관리를 할 수 있다는 장점이 있습니다. 이는 팀 전체의 개발 프로세스를 표준화하는 데 큰 도움이 됩니다.
3.  **보안의 중요성**: `secrets`를 활용하여 민감한 정보를 코드와 분리하여 안전하게 관리하는 방식은 자동화 환경에서 반드시 지켜야 할 필수 보안 수칙임을 다시 한번 깨달았습니다.

---

## 🔗 참고 자료

-   [GitHub Actions 공식 문서](https://docs.github.com/en/actions)
-   [GitHub Marketplace - Actions](https://github.com/marketplace?type=actions)
-   [Spring Boot with Docker 가이드](https://spring.io/guides/gs/spring-boot-docker/)
