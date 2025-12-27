---
title: "Spring Rest Docs: 프로덕션 코드 오염 없이 신뢰할 수 있는 API 문서 만들기"
date: 2025-12-27
categories: [Testing, Documentation]
tags: [Spring Rest Docs, API Documentation, Asciidoctor, JUnit5, MockMvc, Swagger, TIL]
excerpt: "Swagger(OpenAPI)의 단점인 '프로덕션 코드 오염'과 '문서와 코드의 불일치' 문제를 해결하기 위해 Spring Rest Docs를 도입합니다. 테스트 코드가 통과해야만 문서가 생성되는 TDD 기반의 문서화 파이프라인 구축 과정을 학습합니다."
author_profile: true
---

# Today I Learned: Spring Rest Docs: 프로덕션 코드 오염 없이 신뢰할 수 있는 API 문서 만들기

## 📚 오늘 학습한 내용

API 문서를 관리하기 위해 Swagger(Springdoc)를 주로 사용해왔습니다. 하지만 DTO와 컨트롤러에 덕지덕지 붙은 `@Schema`, `@Operation` 애노테이션 때문에 코드를 읽기 힘들고, 무엇보다 **"코드를 수정하고 문서를 안 고쳐서, 실제 동작과 문서가 다른"** 최악의 상황이 종종 발생했습니다.

오늘은 이러한 문제를 해결하고, **"테스트를 통과하지 못하면 문서가 생성되지 않는"** 강력한 신뢰성을 보장하는 **Spring Rest Docs**를 학습하고 적용했습니다.

---

### 1. **Swagger vs. Spring Rest Docs ⚔️**

| 특징 | **Swagger (Springdoc)** | **Spring Rest Docs** |
| :--- | :--- | :--- |
| **기반** | 애노테이션 기반 (Controller/DTO) | **테스트 코드 기반 (JUnit)** |
| **장점** | 적용이 쉽고, API를 직접 호출해볼 수 있는 UI(Try it out) 제공 | 프로덕션 코드에 영향 0%, **문서의 신뢰성 100%** |
| **단점** | 비즈니스 로직보다 문서용 코드가 더 길어짐 (코드 오염) | 테스트 작성이 필수이며, 적용 난이도가 약간 높음 |
| **결론** | 내부 개발팀끼리 빠르게 공유할 때 적합 | **외부에 공개하는 API**나, 품질 관리가 중요한 프로젝트에 적합 |

---

### 2. **Spring Boot에 적용하기**

#### **Step 1: `build.gradle` 설정 (가장 까다로운 부분)**

Rest Docs는 `Asciidoctor`라는 도구를 통해 스니펫(Snippet)을 HTML로 변환합니다. 설정 순서가 중요합니다.

```groovy
plugins {
    id 'org.asciidoctor.jvm.convert' version '3.3.2' // Asciidoctor 플러그인
}

configurations {
    asciidoctorExt // Asciidoctor 확장을 위한 설정
}

dependencies {
    // MockMvc 테스트용 의존성
    testImplementation 'org.springframework.restdocs:spring-restdocs-mockmvc'
    asciidoctorExt 'org.springframework.restdocs:spring-restdocs-asciidoctor'
}

ext {
    snippetsDir = file('build/generated-snippets') // 스니펫 생성 위치
}

test {
    outputs.dir snippetsDir
    useJUnitPlatform()
}

asciidoctor {
    inputs.dir snippetsDir
    configurations 'asciidoctorExt'
    dependsOn test // 테스트가 성공해야 문서 생성
}

// 생성된 문서를 static/docs로 복사 (서버 띄우면 /docs/index.html로 접근 가능)
bootJar {
    dependsOn asciidoctor
    from ("${asciidoctor.outputDir}") {
        into 'static/docs'
    }
}
```

#### **Step 2: 테스트 코드 작성 (`MockMvc` + `document`)**

컨트롤러 테스트(`@WebMvcTest`)에서 `document()` 메서드를 통해 요청/응답 필드를 정의합니다. 여기서 정의한 내용과 실제 응답이 다르면 **테스트가 실패**합니다.

```java
@WebMvcTest(MemberController.class)
@AutoConfigureRestDocs // RestDocs 설정 자동 로드
class MemberControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private MemberService memberService;

    @Test
    @DisplayName("회원 단건 조회 API 문서화")
    void getMember() throws Exception {
        // given
        given(memberService.findById(1L))
                .willReturn(new MemberResponse(1L, "user@example.com", "홍길동"));

        // when & then
        mockMvc.perform(get("/api/members/{id}", 1L)
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andDo(document("member-get", // 문서 식별자 (폴더명)
                        // 1. Path Parameter 문서화
                        pathParameters(
                                parameterWithName("id").description("조회할 회원 ID")
                        ),
                        // 2. Response Fields 문서화
                        responseFields(
                                fieldWithPath("id").type(JsonFieldType.NUMBER).description("회원 고유 ID"),
                                fieldWithPath("email").type(JsonFieldType.STRING).description("이메일 주소"),
                                fieldWithPath("name").type(JsonFieldType.STRING).description("회원 이름")
                        )
                ));
    }
}
```

#### **Step 3: `index.adoc` 작성**

생성된 스니펫들(`http-request.adoc`, `http-response.adoc` 등)을 조합하여 최종 문서를 만듭니다. (`src/docs/asciidoc/index.adoc`)

```asciidoc
= My Service API Documentation
:doctype: book
:icons: font
:source-highlighter: highlightjs
:toc: left
:toclevels: 2

== 회원(Member) API

=== 회원 단건 조회

==== 요청
include::{snippets}/member-get/http-request.adoc[]
include::{snippets}/member-get/path-parameters.adoc[]

==== 응답
include::{snippets}/member-get/http-response.adoc[]
include::{snippets}/member-get/response-fields.adoc[]
```

---

### 3. **Swagger UI와 함께 쓰기 (RestDocs-API-Spec)**

Rest Docs는 HTML 정적 문서만 제공하여 "API를 바로 테스트해보기(Try it out)"가 어렵다는 단점이 있습니다. 이를 보완하기 위해 **`com.epages.restdocs-api-spec`** 라이브러리를 활용하면, Rest Docs로 작성한 테스트 코드를 기반으로 **OpenAPI(Swagger) Spec 파일(JSON/YAML)**을 뽑아낼 수 있습니다.

즉, **"코드의 신뢰성(Rest Docs)" + "UI의 편리함(Swagger UI)"** 두 마리 토끼를 잡을 수 있습니다.

---

## 💡 배운 점

1.  **문서는 곧 코드다**: API 스펙이 변경되었는데 테스트 코드를 수정하지 않으면 빌드가 깨집니다. 이 강제성이 귀찮을 수도 있지만, 장기적으로는 "거짓말하지 않는 문서"를 유지하는 유일한 방법임을 깨달았습니다.
2.  **프로덕션 코드의 청정 구역화**: 컨트롤러에서 `@Operation(summary = "...")` 같은 지저분한 애노테이션이 싹 사라지고, 오직 비즈니스 로직과 라우팅 정보만 남게 되어 가독성이 비약적으로 상승했습니다.
3.  **TC 품질 향상**: 문서를 만들기 위해 강제로 모든 필드에 대한 검증 로직을 넣어야 하다 보니, 자연스럽게 테스트 케이스가 꼼꼼해지고 API의 완성도가 올라가는 부수 효과를 얻었습니다.

---

## 🔗 참고 자료

-   [Spring Rest Docs Official Reference](https://docs.spring.io/spring-restdocs/docs/current/reference/html5/)
-   [Asciidoctor Gradle Plugin Guide](https://asciidoctor.github.io/asciidoctor-gradle-plugin/development-3.x/user-guide/)
-   [Spring Rest Docs with OpenAPI (Swagger)](https://github.com/ePages-de/restdocs-api-spec)