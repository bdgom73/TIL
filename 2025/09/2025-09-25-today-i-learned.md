---
title: "API 설계 트렌드: REST 성숙도 모델과 GraphQL 비교"
date: 2025-09-25
categories: [Architecture, API]
tags: [REST, GraphQL, API Design, RMM, HATEOAS, TIL]
excerpt: "잘 설계된 REST API의 기준인 Richardson 성숙도 모델(RMM)의 각 단계를 이해하고, REST의 한계를 극복하기 위해 등장한 GraphQL의 핵심 개념과 장단점을 비교 분석하며 현대 API 설계 트렌드를 학습합니다."
author_profile: true
---

# Today I Learned: API 설계 트렌드: REST 성숙도 모델과 GraphQL 비교

## 📚 오늘 학습한 내용

현대 애플리케이션 개발에서 API는 클라이언트와 서버를 잇는 핵심적인 통로입니다. 단순히 데이터를 주고받는 것을 넘어, 잘 설계된 API는 개발 생산성과 시스템의 유지보수성을 크게 좌우합니다. 오늘은 성숙한 REST API의 기준인 **Richardson 성숙도 모델(RMM)**을 학습하고, 새로운 API 설계 패러다임인 **GraphQL**과 비교하며 각각의 장단점을 분석했습니다.

---

### 1. **REST API는 얼마나 성숙했는가? - Richardson 성숙도 모델(RMM)**

"RESTful API"라고 해서 모두 같은 수준이 아닙니다. Leonard Richardson이 제안한 이 모델은 REST API가 얼마나 REST의 제약 조건을 잘 따르는지를 4단계로 나누어 평가하는 척도입니다.

-   **Level 0: The Swamp of POX (단순 HTTP 호출)**
    -   HTTP를 단순히 원격 프로시저 호출(RPC)을 위한 터널로만 사용합니다.
    -   엔드포인트 하나(`e.g., /api`)에 모든 요청을 `POST` 메서드로 보내고, 요청 본문에 어떤 동작을 할지(`e.g., "action": "getUser"`) 명시하는 방식입니다.
    -   REST의 장점을 거의 활용하지 못하는 단계입니다.

-   **Level 1: Resources (리소스 개념 도입)**
    -   요청을 개념적인 리소스(`e.g., /users`, `/posts/1`)로 분리합니다.
    -   하지만 여전히 `POST` 메서드 하나만 사용하여 리소스에 대한 모든 처리를 합니다. (e.g., `POST /users`로 사용자 생성, `POST /users/1`로 사용자 정보 수정)

-   **Level 2: HTTP Verbs (HTTP 동사 활용)**
    -   리소스에 대한 행위를 **HTTP 메서드(`GET`, `POST`, `PUT`, `DELETE` 등)**로 표현합니다.
    -   `GET /users/1`: 사용자 조회
    -   `POST /users`: 사용자 생성
    -   `PUT /users/1`: 사용자 정보 전체 수정
    -   **대부분의 "RESTful API"가 이 수준에 해당하며, 실용적으로 가장 널리 사용됩니다.**

-   **Level 3: Hypermedia Controls (HATEOAS)**
    -   **HATEOAS(Hypermedia as the Engine of Application State)**를 만족하는 단계로, REST 성숙도의 정점입니다.
    -   API 응답에 현재 리소스와 관련된 다음 행동을 할 수 있는 **링크(Link)** 정보를 포함하여, 클라이언트가 이 링크들을 통해 API를 탐색(Navigate)할 수 있게 합니다.
    -   **장점**: 서버의 API가 변경되어도 클라이언트는 링크를 따라가기만 하면 되므로 결합도(Coupling)가 낮아집니다.

    ```json
    {
        "user_id": 123,
        "name": "John Doe",
        "_links": {
            "self": { "href": "/users/123" },
            "posts": { "href": "/users/123/posts" },
            "update": { "href": "/users/123", "method": "PUT" }
        }
    }
    ```


---

### 2. **REST의 대안, GraphQL의 등장**

GraphQL은 Facebook(현 Meta)에서 개발한 API를 위한 쿼리 언어이자 런타임입니다. REST API가 가진 고질적인 문제인 **Over-fetching**(필요 없는 데이터까지 받아오는 문제)과 **Under-fetching**(원하는 데이터를 얻기 위해 여러 번 요청해야 하는 문제)을 해결하기 위해 등장했습니다.

-   **핵심 개념**:
    1.  **하나의 엔드포인트**: REST처럼 리소스별로 여러 엔드포인트를 두지 않고, 주로 `/graphql`이라는 단일 엔드포인트를 사용합니다.
    2.  **클라이언트가 데이터 요구사항을 정의**: 클라이언트는 필요한 데이터의 구조를 쿼리 형태로 작성하여 서버에 요청합니다. 서버는 정확히 그 구조에 맞춰 응답합니다.
    3.  **강력한 타입 시스템**: 서버는 스키마(Schema)를 통해 API의 모든 데이터와 타입을 정의합니다. 이 스키마는 클라이언트와 서버 간의 명확한 계약(Contract) 역할을 합니다.

#### **GraphQL 쿼리 예시**
클라이언트가 123번 사용자의 이름과 최근 게시물 3개의 제목만 필요할 경우:

**Query:**
```graphql
query {
  user(id: "123") {
    name
    posts(last: 3) {
      title
    }
  }
}
```

**Response:**
```json
{
  "data": {
    "user": {
      "name": "John Doe",
      "posts": [
        { "title": "My First Post" },
        { "title": "GraphQL is awesome" },
        { "title": "REST vs GraphQL" }
      ]
    }
  }
}
```
> **핵심**: 클라이언트가 API 요청의 주도권을 가지므로, 모바일 환경처럼 네트워크 비용이 민감하거나 다양한 형태의 데이터 조합이 필요한 서비스에 매우 효과적입니다.

---

### 3. **REST vs. GraphQL 비교 분석**

| 구분 | **REST** | **GraphQL** |
| :--- | :--- | :--- |
| **엔드포인트** | 다중 엔드포인트 (리소스 기반) | 단일 엔드포인트 (`/graphql`) |
| **데이터 페칭** | Over/Under-fetching 발생 가능 | 필요한 데이터만 정확히 페칭 |
| **캐싱** | HTTP 표준 캐싱(브라우저 캐시 등) 활용 용이 | 복잡함 (POST 요청 위주라 HTTP 캐싱 어려움) |
| **학습 곡선** | 상대적으로 낮음 (HTTP 표준 기반) | 상대적으로 높음 (스키마, 쿼리 언어 학습 필요) |
| **스키마/타입** | 내장된 표준 없음 (OpenAPI 등 별도 도구 사용) | 강력한 타입 시스템 내장 (스키마 필수) |
| **요청 주도권** | 서버 | 클라이언트 |

---

## 💡 배운 점

1.  **'좋은 REST API'는 명확한 기준이 있다**: Richardson 성숙도 모델을 통해 우리가 만드는 API가 어느 수준에 있는지 객관적으로 평가하고 개선 방향을 설정할 수 있습니다. 특히 Level 2는 실용적인 목표이며, HATEOAS(Level 3)는 API의 유연성과 확장성을 극대화하는 이상적인 목표임을 이해했습니다.
2.  **GraphQL은 만병통치약이 아니다**: GraphQL은 데이터 페칭 문제를 해결하는 강력한 도구이지만, 캐싱의 복잡성이나 초기 학습 비용 등 고려해야 할 트레이드오프가 명확합니다. 단순한 CRUD API나 파일 업로드 등은 여전히 REST가 더 효율적일 수 있습니다.
3.  **문제에 맞는 도구를 선택하는 것이 중요하다**: 모바일 앱, 복잡한 대시보드 등 다양한 클라이언트 요구사항에 대응해야 한다면 GraphQL이 강력한 선택지가 될 수 있습니다. 반면, 명확한 자원을 다루는 공개 API나 내부 마이크로서비스 간 통신에서는 잘 설계된 REST API가 더 합리적인 선택일 수 있다는 점을 깨달았습니다.

---

## 🔗 참고 자료

-   [Martin Fowler - Richardson Maturity Model](https://martinfowler.com/articles/richardsonMaturityModel.html)
-   [GraphQL 공식 문서](https://graphql.org/)
-   [REST vs. GraphQL (GraphQL.org)](https://graphql.org/learn/thinking-in-graphs/)