---
title: "Swagger의 배신: Spring REST Docs로 운영 코드 오염 없는 '진짜' 문서 만들기"
date: 2026-01-28
categories: [Spring, Testing, Documentation]
tags: [Spring REST Docs, Swagger, OpenAPI, AsciiDoc, Test Driven, API Documentation, TIL]
excerpt: "운영 코드에 덕지덕지 붙은 Swagger 애노테이션을 제거하고, 테스트가 통과해야만 문서가 생성되는 Spring REST Docs를 도입합니다. MockMvc 테스트 코드에 문서화 로직을 녹여내는 방법과 AsciiDoc을 활용해 신뢰할 수 있는 API 명세서를 자동화하는 파이프라인을 구축합니다."
author_profile: true
---

# Today I Learned: Swagger의 배신: Spring REST Docs로 운영 코드 오염 없는 '진짜' 문서 만들기

## 📚 오늘 학습한 내용

프로젝트가 커지면서 Controller 코드보다 Swagger용 애노테이션(`@Operation`, `@ApiResponse`, `@Schema`)이 더 길어지는 **주객전도** 현상이 발생했습니다. 더 심각한 건, 코드는 수정했는데 애노테이션 수정을 깜빡해서 **"문서랑 실제 응답이 달라요"**라는 프론트엔드 팀의 항의를 받는 일이 잦아졌습니다.

오늘은 프로덕션 코드에 침투하지 않으면서, **테스트가 성공해야만 문서가 만들어지는(신뢰성 100%)** **Spring REST Docs**로 마이그레이션을 진행했습니다.

---

### 1. **Swagger(OpenAPI) vs Spring REST Docs 🥊**

| 특징 | **Swagger (SpringDoc)** | **Spring REST Docs** |
| :--- | :--- | :--- |
| **장점** | 적용이 매우 쉽고, API를 직접 호출해볼 수 있는 UI 제공 (Try it out) | **테스트 코드 기반**이라 문서와 코드의 불일치가 발생할 수 없음 (신뢰성 높음) |
| **단점** | 운영 코드(Controller, DTO)에 문서화용 애노테이션이 심하게 침투함 | 초기 설정(Gradle, AsciiDoc)이 복잡하고 러닝 커브가 있음 |
| **결론** | 빠른 프로토타이핑이나 내부 어드민용으로는 좋지만, **외부 공개용 API나 유지보수가 중요한 프로젝트**는 REST Docs가 유리함. |



---

### 2. **Spring Boot 3.x 설정 (Gradle)**

REST Docs의 가장 큰 진입 장벽은 복잡한 빌드 설정입니다. Asciidoctor 플러그인을 설정해야 합니다.

**build.gradle**
```groovy
plugins {
    id 'org.asciidoctor.jvm.convert' version '3.3.2' // AsciiDoc 변환 플러그인
}

configurations {
    asciidoctorExt // 의존성 설정을 위한 확장 설정
}

dependencies {
    // mockmvc를 위한 restdocs 의존성
    testImplementation 'org.springframework.restdocs:spring-restdocs-mockmvc'
    asciidoctorExt 'org.springframework.restdocs:spring-restdocs-asciidoctor'
}

ext {
    snippetsDir = file('build/generated-snippets') // 스니펫 생성 경로
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

// 생성된 문서를 static/docs로 복사 (서버 띄우면 /docs/index.html로 접근 가능하게)
bootJar {
    dependsOn asciidoctor
    from ("${asciidoctor.outputDir}") {
        into 'static/docs'
    }
}
```

---

### 3. **테스트 코드 작성 (MockMvc)**

이제 Controller에는 아무런 애노테이션을 붙이지 않아도 됩니다. 대신 **ControllerTest**에 문서화 로직을 작성합니다.

```java
@WebMvcTest(ProductController.class)
@AutoConfigureRestDocs // REST Docs 자동 설정
class ProductControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("상품 단건 조회 API 문서화")
    void getProduct() throws Exception {
        // given
        Long productId = 1L;
        // (Mocking 로직 생략)

        // when & then
        mockMvc.perform(get("/api/v1/products/{id}", productId)
                .accept(MediaType.APPLICATION_JSON))
            .andExpect(status().isOk())
            // 여기서부터 문서화 로직
            .andDo(document("product-get", // 스니펫 디렉토리 명
                preprocessRequest(prettyPrint()), // 요청 JSON 예쁘게 출력
                preprocessResponse(prettyPrint()), // 응답 JSON 예쁘게 출력
                
                // 1. Path Variable 문서화
                pathParameters(
                    parameterWithName("id").description("조회할 상품의 ID")
                ),
                
                // 2. Response Fields 문서화
                responseFields(
                    fieldWithPath("id").type(JsonFieldType.NUMBER).description("상품 ID"),
                    fieldWithPath("name").type(JsonFieldType.STRING).description("상품명"),
                    fieldWithPath("price").type(JsonFieldType.NUMBER).description("가격"),
                    fieldWithPath("status").type(JsonFieldType.STRING).description("판매 상태 (SALE, SOLD_OUT)")
                )
            ));
    }
}
```

만약 `responseFields`에 실제 응답 필드 중 하나라도 빠뜨리면? **테스트가 실패(Failure)**합니다. 이것이 REST Docs가 문서의 정확성을 보장하는 원리입니다.

---

### 4. **AsciiDoc 조합하기 (.adoc)**

테스트를 돌리면 `build/generated-snippets/product-get` 폴더에 `.adoc` 조각 파일들이 생깁니다. 이를 하나의 문서로 합쳐야 합니다.

**src/docs/asciidoc/index.adoc**
```asciidoc
= Catch Beauty API 명세서
:doctype: book
:icons: font
:source-highlighter: highlightjs
:toc: left
:toclevels: 2

== 1. 상품(Product) API

=== 상품 단건 조회

==== 요청
include::{snippets}/product-get/http-request.adoc[]
include::{snippets}/product-get/path-parameters.adoc[]

==== 응답
include::{snippets}/product-get/http-response.adoc[]
include::{snippets}/product-get/response-fields.adoc[]
```

이제 `./gradlew bootJar`를 실행하면 이 adoc 파일이 HTML로 변환되어 정적 리소스로 배포됩니다.

---

## 💡 배운 점

1.  **강제된 현행화**: 필드명을 바꾸거나 삭제했을 때, 테스트를 돌리지 않으면 빌드가 깨지므로 **문서 업데이트를 까먹을 수가 없는 구조**가 되었습니다. 개발자에게 "문서 업데이트 하세요"라고 잔소리할 필요가 없어졌습니다.
2.  **클린 코드**: Controller 클래스가 다시 본연의 모습(요청 매핑 및 위임)으로 돌아왔습니다. `@Schema(description = "...")` 같은 지저분한 코드가 사라져 가독성이 매우 좋아졌습니다.
3.  **UI의 부재 해결**: Swagger UI의 편리함(API 호출 기능)이 아쉬울 수 있는데, 이는 IntelliJ의 `.http` 파일이나 Postman 컬렉션을 별도로 공유하거나, **`restdocs-api-spec`** 라이브러리를 사용해 REST Docs 결과물로 OpenAPI 스펙(JSON)을 뽑아내어 Swagger UI에 띄우는 하이브리드 방식도 존재함을 알았습니다.

---

## 🔗 참고 자료

-   [Spring REST Docs Official Reference](https://docs.spring.io/spring-restdocs/docs/current/reference/html5/)
-   [Woowahan Tech Blog: Spring REST Docs 적용기](https://techblog.woowahan.com/2597/)
-   [Asciidoctor User Manual](https://docs.asciidoctor.org/asciidoc/latest/)