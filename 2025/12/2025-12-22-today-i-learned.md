---
title: "ArchUnit: 'Controller에서 Repository 직접 호출 금지'를 코드로 강제하기"
date: 2025-12-22
categories: [Testing, Architecture]
tags: [ArchUnit, JUnit5, Clean Architecture, Refactoring, Code Quality, TIL]
excerpt: "팀의 아키텍처 규칙(Layered Architecture 준수, 순환 참조 방지 등)을 문서나 코드 리뷰가 아닌 '테스트 코드'로 자동 검증하는 방법을 학습합니다. ArchUnit을 도입하여 아키텍처 침식을 방지하고 리팩토링 안전망을 구축해봅니다."
author_profile: true
---

# Today I Learned: ArchUnit: 'Controller에서 Repository 직접 호출 금지'를 코드로 강제하기

## 📚 오늘 학습한 내용

서비스가 커지고 팀원이 늘어나면 **"Controller는 Service만 호출해야 한다"**, **"Service는 Controller를 알면 안 된다"** 같은 계층형 아키텍처(Layered Architecture)의 원칙들이 서서히 무너집니다. 바쁜 일정 속에 코드 리뷰에서 놓치기 쉽고, 신규 입사자는 문서를 읽지 않으면 실수하기 마련입니다.

오늘은 이러한 아키텍처 제약 사항을 **단위 테스트(JUnit)**로 작성하여, 규칙을 위반하면 빌드가 실패하도록 만드는 라이브러리인 **ArchUnit**에 대해 학습했습니다.

---

### 1. **ArchUnit이란? 🏗️**

ArchUnit은 Java 바이트코드를 분석하여 클래스 간의 의존성, 패키지 구조, 상속 관계, 애노테이션 등을 검사하는 테스트 라이브러리입니다.

-   **활용 사례**:
    -   계층 간 의존성 방향 체크 (Controller -> Service -> Repository)
    -   순환 참조(Cycle) 감지
    -   특정 패키지의 클래스는 특정 애노테이션을 가져야 함
    -   `System.out.println` 사용 금지 등

---

### 2. **Spring Boot에 적용하기**

#### **Step 1: 의존성 추가**
`build.gradle`에 `archunit-junit5`를 추가합니다.

```groovy
testImplementation 'com.tngtech.archunit:archunit-junit5:1.0.1'
```

#### **Step 2: 아키텍처 테스트 작성**

가장 흔한 3-Tier Layered Architecture 규칙을 코드로 작성해 봅니다.

```java
@AnalyzeClasses(packages = "com.example.myapp") // 분석할 패키지 루트 지정
public class ArchitectureTest {

    @ArchTest
    // 1. Controller는 Service만 의존해야 하고, Repository를 직접 의존하면 안 된다.
    static final ArchRule controller_should_not_access_repository =
            noClasses().that().resideInAPackage("..controller..")
                    .should().dependOnClassesThat().resideInAPackage("..repository..");

    @ArchTest
    // 2. Service는 Controller나 Web 관련 패키지에 의존하면 안 된다. (역참조 방지)
    static final ArchRule service_should_not_depend_on_web_layer =
            noClasses().that().resideInAPackage("..service..")
                    .should().dependOnClassesThat().resideInAPackage("..controller..");

    @ArchTest
    // 3. 순환 참조(Cycle)가 없어야 한다.
    static final ArchRule no_cycles =
            slices().matching("com.example.myapp.(*)..").namingSlices("$1")
                    .should().beFreeOfCycles();
}
```

---

### 3. **심화: 명명 규칙과 애노테이션 강제하기**

단순한 의존성뿐만 아니라 코딩 컨벤션도 강제할 수 있습니다.

```java
@AnalyzeClasses(packages = "com.example.myapp")
public class ConventionTest {

    @ArchTest
    // 1. Service 패키지에 있는 클래스 이름은 항상 'Service'로 끝나야 한다.
    static final ArchRule services_should_be_named_service =
            classes().that().resideInAPackage("..service..")
                    .should().haveSimpleNameEndingWith("Service");

    @ArchTest
    // 2. Repository 인터페이스는 반드시 @Repository 애노테이션이 있어야 한다. (JPA 제외 시 유용)
    //    또는 Service 클래스는 @Transactional을 가지고 있어야 한다 등.
    static final ArchRule repositories_should_be_annotated =
            classes().that().resideInAPackage("..repository..")
                    .should().beAnnotatedWith(Repository.class);
    
    @ArchTest
    // 3. 도메인(Entity) 계층은 DTO나 Request 객체에 의존하면 안 된다.
    static final ArchRule domain_should_not_depend_on_dto =
            noClasses().that().resideInAPackage("..domain..")
                    .should().dependOnClassesThat().haveSimpleNameEndingWith("Dto");
}
```

---

### 4. **LayeredArchitecture API 사용하기**

ArchUnit은 계층형 아키텍처 검증을 위한 전용 API를 제공하여 더 직관적인 작성이 가능합니다.

```java
@ArchTest
static final ArchRule layered_architecture =
        layeredArchitecture()
                .consideringOnlyDependenciesInLayers() // 정의된 레이어 간의 의존성만 본다
                .layer("Controller").definedBy("..controller..")
                .layer("Service").definedBy("..service..")
                .layer("Repository").definedBy("..repository..")

                .whereLayer("Controller").mayNotBeAccessedByAnyLayer()
                .whereLayer("Service").mayOnlyBeAccessedByLayers("Controller")
                .whereLayer("Repository").mayOnlyBeAccessedByLayers("Service");
```

---

## 💡 배운 점

1.  **문서보다 강력한 코드**: "Controller에서 Repository 부르지 마세요"라고 위키에 적어두는 것보다, 누군가 그 코드를 작성했을 때 **테스트가 깨지게 만드는 것**이 훨씬 강력한 제약 수단임을 깨달았습니다.
2.  **리팩토링의 나침반**: 레거시 코드를 리팩토링할 때, ArchUnit을 먼저 설정해두면 의존성이 엉켜있는 지점(Cycle 등)을 빠르게 파악할 수 있고, 리팩토링 과정에서 아키텍처가 다시 망가지는 것을 방지할 수 있습니다.
3.  **지속 가능한 아키텍처**: 개발 초기에는 잘 지켜지던 규칙들이 시간이 지나며 무너지는 현상(Architectural Erosion)을 방지하기 위해, ArchUnit은 CI 파이프라인의 필수 요소로 가져가야 할 도구입니다.

---

## 🔗 참고 자료

-   [ArchUnit User Guide](https://www.archunit.org/userguide/html/000_Index.html)
-   [Test Your Architecture with ArchUnit (Baeldung)](https://www.baeldung.com/archunit)
-   [Keep your Java architecture clean with ArchUnit](https://developer.okta.com/blog/2021/04/26/java-architecture-archunit)