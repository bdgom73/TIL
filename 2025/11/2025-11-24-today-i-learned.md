---
title: "Spring REST Docs: 테스트가 보증하는 '거짓말하지 않는' API 문서 만들기"
date: 2025-11-24
categories: [Spring, Testing]
tags: [Spring REST Docs, API Documentation, Asciidoctor, JUnit, MockMvc, Swagger, TIL]
excerpt: "프로덕션 코드에 침투하는 Swagger(Springdoc) 애노테이션의 문제점을 해결하고, 테스트 통과를 전제로 '항상 코드와 일치하는' 문서를 만들어주는 Spring REST Docs의 원리와 적용 방법을 학습합니다."
author_profile: true
---

# Today I Learned: Spring REST Docs: 테스트가 보증하는 '거짓말하지 않는' API 문서 만들기

## 📚 오늘 학습한 내용

API를 개발하면 반드시 문서를 작성해야 합니다. 보통 **Swagger (Springdoc)**를 많이 사용하지만, DTO와 Controller에 덕지덕지 붙는 `@Schema`, `@Operation` 같은 애노테이션이 프로덕션 코드를 지저분하게 만드는 것이 항상 불만이었습니다. 게다가 코드는 수정했지만 애노테이션 수정을 깜빡해서 **"문서와 코드가 다른"** 치명적인 문제가 발생하기도 합니다.

오늘은 이러한 문제를 해결하기 위해, **테스트 코드(JUnit)**를 기반으로 문서를 자동 생성하여 **"문서의 신뢰성"**을 보장하는 **Spring REST Docs**를 프로젝트에 적용하는 방법을 학습했습니다.

---

### 1. **Swagger vs. Spring REST Docs: 무엇이 다른가?**

| 특징 | **Swagger (Springdoc)** | **Spring REST Docs** |
| :--- | :--- | :--- |
| **문서 생성 방식** | 애플리케이션 실행 시 로직을 분석하여 생성 | **테스트 코드(JUnit) 실행 결과**를 기반으로 생성 |
| **장점** | 적용이 매우 쉽고, API 테스트 기능(UI) 제공 | **테스트가 통과해야만** 문서가 생성됨 (신뢰성 100%), 프로덕션 코드 오염 없음 |
| **단점** | 프로덕션 코드에 문서화용 애노테이션 침투 | 테스트 코드 작성이 필수, 초기 설정이 다소 복잡함 |
| **결론** | 빠른 개발과 내부 공유용 | **외부 공개용 API**, 코드 품질과 문서의 정확성이 중요한 경우 |

---

### 2. **Spring REST Docs 동작 원리**

1.  개발자가 `MockMvc` (또는 `WebTestClient`, `RestAssured`)를 사용해 컨트롤러 테스트를 작성합니다.
2.  테스트 수행 중 요청/응답 필드에 대한 설명을 작성(`document()`)합니다.
3.  테스트가 성공하면 `build/generated-snippets` 경로에 문서 조각(Snippets, `.adoc` 파일)들이 생성됩니다.
4.  **Asciidoctor**가 이 조각들을 모아서 하나의 HTML 파일(`index.html`)로 변환합니다.
5.  이 HTML 파일을 정적 리소스로 배포합니다.

---

### 3. **Spring Boot에 적용하기 (Step-by-Step)**

#### **Step 1: `build.gradle` 설정**
가장 까다로운 부분입니다. `asciidoctor` 플러그인과 의존성을 설정합니다.

```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.0'
    id 'io.spring.dependency-management' version '1.1.4'
    // 1. Asciidoctor 플러그인 추가
    id "org.asciidoctor.jvm.convert" version "3.3.2" 
}

configurations {
    asciidoctorExt // Asciidoctor 확장을 위한 설정
}

dependencies {
    // ... (기본 의존성) ...
    
    // 2. REST Docs 의존성 추가
    testImplementation 'org.springframework.restdocs:spring-restdocs-mockmvc'
    asciidoctorExt 'org.springframework.restdocs:spring-restdocs-asciidoctor'
}

ext {
    snippetsDir = file('build/generated-snippets') // 스니펫 생성 위치
}

test {
    outputs.dir snippetsDir // 테스트 결과로 스니펫 디렉토리 지정
    useJUnitPlatform()
}

asciidoctor {
    inputs.dir snippetsDir // 스니펫을 입력으로 사용
    configurations 'asciidoctorExt'
    dependsOn test // 문서 생성 전 테스트 실행 필수
}

// 3. 생성된 문서를 정적 리소스(static/docs)로 복사 (Jar 빌드 시 포함되도록)
bootJar {
    dependsOn asciidoctor
    from ("${asciidoctor.outputDir}") {
        into 'static/docs'
    }
}
```

#### **Step 2: 테스트 코드 작성 (`MockMvc` + `document`)**
단순히 `status().isOk()`만 검증하는 것이 아니라, `document()` 메서드를 통해 필드 명세를 작성합니다.

```java
@WebMvcTest(UserController.class)
@AutoConfigureRestDocs // REST Docs 자동 설정
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("회원 단건 조회 API 문서화")
    void getUser() throws Exception {
        // given
        Long userId = 1L;
        
        // when & then
        mockMvc.perform(get("/api/users/{id}", userId)
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                // 문서화 시작
                .andDo(document("user-get", // 식별자 (폴더명)
                        // 1. 경로 파라미터 문서화
                        pathParameters(
                                parameterWithName("id").description("조회할 사용자의 ID")
                        ),
                        // 2. 응답 필드 문서화
                        responseFields(
                                fieldWithPath("id").description("사용자 ID"),
                                fieldWithPath("email").description("사용자 이메일"),
                                fieldWithPath("name").description("사용자 이름"),
                                fieldWithPath("createdAt").description("가입일시")
                        )
                ));
    }
}
```
> 만약 DTO에 `phone` 필드가 추가되었는데 테스트 코드(`responseFields`)에 반영하지 않았다면? **테스트가 실패합니다.** 이것이 문서의 정확성을 강제하는 핵심입니다.

#### **Step 3: AsciiDoc 파일 작성 (`src/docs/asciidoc/index.adoc`)**
생성된 스니펫들을 모아서 보여줄 메인 문서 템플릿을 작성합니다.

```asciidoc
= My Service API 문서
:doctype: book
:icons: font
:source-highlighter: highlightjs
:toc: left
:toclevels: 2

== 회원 API

=== 회원 단건 조회

==== 요청
include::{snippets}/user-get/http-request.adoc[]
include::{snippets}/user-get/path-parameters.adoc[]

==== 응답
include::{snippets}/user-get/http-response.adoc[]
include::{snippets}/user-get/response-fields.adoc[]
```

이제 `./gradlew build`를 실행하면, 테스트가 수행되고 -> 스니펫이 생성되고 -> `index.html`이 만들어져 -> `jar` 파일 안에 포함됩니다.

---

## 💡 배운 점

1.  **테스트 주도 문서화(Test-Driven Documentation)**: "테스트가 통과하지 않으면 문서도 발행되지 않는다." 이 강력한 제약 조건 덕분에, 코드를 수정하고 문서를 업데이트하지 않는 실수를 원천적으로 차단할 수 있음을 깨달았습니다.
2.  **프로덕션 코드의 순수성**: Swagger를 쓸 때는 DTO마다 `@Schema(description = "...")`를 붙이느라 코드가 지저분했는데, REST Docs는 테스트 코드에만 명세가 존재하므로 비즈니스 로직과 문서화 로직이 완벽하게 분리되었습니다.
3.  **커스텀의 자유**: Swagger UI는 정해진 틀을 벗어나기 어렵지만, Asciidoctor는 마크다운과 유사한 문법으로 문서를 내 입맛대로 자유롭게 구성하고 디자인할 수 있다는 장점이 있습니다.

---

## 🔗 참고 자료

-   [Spring REST Docs Official Documentation](https://docs.spring.io/spring-restdocs/docs/current/reference/html5/)
-   [Asciidoctor User Manual](https://asciidoctor.org/docs/user-manual/)
-   [Spring REST Docs with Gradle (Baeldung)](https://www.baeldung.com/spring-rest-docs)