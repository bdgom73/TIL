---
title: "Spring Boot와 GraphQL 시작하기: REST API의 대안 탐구"
date: 2025-11-14
categories: [Spring, API]
tags: [GraphQL, Spring Boot, API Design, @SchemaMapping, Over-fetching, TIL]
excerpt: "MSA 환경에서 REST API가 가진 Over-fetching, Under-fetching 문제를 해결하기 위한 대안으로 GraphQL의 핵심 개념을 학습합니다. Spring Boot에서 스키마를 정의하고 @SchemaMapping을 통해 API를 구현하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Boot와 GraphQL 시작하기: REST API의 대안 탐구

## 📚 오늘 학습한 내용

저는 3~4년차 백엔드 개발자로서 수많은 RESTful API를 설계하고 구현해왔습니다. 하지만 REST API는 명확한 한계를 가질 때가 있습니다.

-   **Over-fetching (오버 페칭)**: `GET /api/users/1` API가 사용자의 모든 정보(e.g., 이름, 이메일, 주소, 전화번호...)를 반환할 때, 클라이언트(모바일 앱)는 단지 '이름'만 필요할 수 있습니다. 불필요한 데이터를 과도하게 받아옵니다.
-   **Under-fetching (언더 페칭)**: `GET /api/users/1`로 사용자 정보를 받고, `GET /api/users/1/posts`로 해당 사용자의 게시글을 또 받아오는 등, 클라이언트가 원하는 화면을 구성하기 위해 **여러 번의 API 호출**이 필요합니다.

오늘은 이 두 가지 문제를 해결하는 **GraphQL**의 기본 개념과, **Spring for GraphQL**을 통해 이를 구현하는 방법에 대해 학습했습니다.

---

### 1. **GraphQL: '클라이언트가 주도하는' API 🗣️**

GraphQL은 API를 위한 **쿼리 언어(Query Language)**입니다. 가장 큰 특징은 REST처럼 여러 개의 엔드포인트(`users`, `posts`...)를 두는 것이 아니라, **단 하나의 엔드포인트(e.g., `/graphql`)**를 사용한다는 것입니다.

-   **핵심 아이디어**: 서버가 응답의 형태를 결정하는 것이 아니라, **클라이언트가 필요한 데이터의 구조를 쿼리로 작성**하여 요청하면, 서버는 정확히 그 모양대로 응답을 만들어줍니다.

---

### 2. **GraphQL의 3가지 핵심 요소**

1.  **Schema (스키마)**: API의 "설계도"이자 "계약서". `.graphqls` 파일에 API에서 사용할 수 있는 모든 데이터 타입(Type)과 행위(Query, Mutation)를 정의합니다.
2.  **Query (조회)**: 데이터를 읽는(Read) 요청.
3.  **Mutation (변경)**: 데이터를 생성/수정/삭제(CUD)하는 요청.

---

### 3. **Spring Boot로 GraphQL 서버 구축하기 🚀**

**1. `build.gradle` 의존성 추가**
```groovy
// Spring Boot 3.x 이상 기준
implementation 'org.springframework.boot:spring-boot-starter-graphql'
```
> 이 의존성 하나만 추가하면, Spring Boot가 GraphQL 엔진과 GraphiQL(테스트 UI) 등을 자동으로 구성해줍니다.

**2. 스키마 정의 (`src/main/resources/graphql/schema.graphqls`)**
API의 명세를 `.graphqls` 파일에 작성합니다. 이 스키마가 곧 API 문서가 됩니다.

```graphql
# src/main/resources/graphql/schema.graphqls

# 1. 데이터 타입을 정의합니다 (JPA 엔티티나 DTO와 유사)
type User {
    id: ID!
    username: String
    email: String
    posts: [Post] # 사용자의 게시글 목록 (연관관계)
}

type Post {
    id: ID!
    title: String
    content: String
}

# 2. 조회(Read) API를 정의합니다. (Controller의 GET 메서드와 유사)
type Query {
    # ID로 사용자를 조회
    findUserById(id: ID!): User
    # 모든 게시글을 조회
    findAllPosts: [Post]
}

# 3. 변경(CUD) API를 정의합니다. (Controller의 POST/PUT/DELETE와 유사)
type Mutation {
    # 새로운 게시글 작성
    createPost(title: String!, content: String!, userId: ID!): Post
}
```

**3. 컨트롤러(Resolver) 구현 (`@Controller` + `@SchemaMapping`)**
GraphQL 스키마의 각 필드와 메서드를 실제 Java 코드와 연결하는 **'리졸버(Resolver)'**를 작성합니다. `@RestController`가 아닌 일반 `@Controller`를 사용합니다.

```java
@Controller // (주의!) @RestController가 아님
@RequiredArgsConstructor
public class GraphQlApiController {

    private final UserRepository userRepository;
    private final PostRepository postRepository;

    /**
     * Query.findUserById(id) 스키마를 이 메서드와 매핑합니다.
     */
    @QueryMapping // type Query 밑의 필드
    public User findUserById(@Argument Long id) {
        return userRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("User not found"));
    }

    /**
     * Mutation.createPost(...) 스키마를 이 메서드와 매핑합니다.
     */
    @MutationMapping // type Mutation 밑의 필드
    public Post createPost(@Argument String title, @Argument String content, @Argument Long userId) {
        User user = userRepository.findById(userId).orElseThrow();
        Post newPost = new Post(title, content, user);
        return postRepository.save(newPost);
    }

    /**
     * N+1 문제 해결을 위한 Data Fetcher (Type User의 posts 필드)
     * User 타입이 요청될 때, 'posts' 필드가 함께 요청되면
     * 이 메서드가 호출되어 해당 필드를 채워줍니다.
     */
    @SchemaMapping(typeName = "User", field = "posts")
    public List<Post> getPostsForUser(User user) {
        log.info("Fetching posts for user: {}", user.getId());
        // (주의) N+1 문제가 발생하기 쉬운 지점!
        // 실제로는 Dataloader 등을 사용해 최적화해야 함.
        return postRepository.findByUser(user);
    }
}
```

---

### 4. **GraphQL 테스트 (GraphiQL)**

Spring Boot를 실행하고 `http://localhost:8080/graphiql` (기본값)에 접속하면, GraphQL 쿼리를 테스트할 수 있는 UI가 나타납니다.

**요청 (Query)**:
클라이언트가 "ID가 1인 유저의 username과, 그 유저가 쓴 글의 title"만 요청합니다.
```graphql
query {
  findUserById(id: 1) {
    username
    posts {
      title
    }
  }
}
```

**응답 (Response)**:
서버는 요청받은 모양 그대로, 딱 필요한 데이터만 JSON으로 응답합니다. (Over-fetching 해결)
```json
{
  "data": {
    "findUserById": {
      "username": "testuser",
      "posts": [
        {
          "title": "My First Post"
        },
        {
          "title": "GraphQL is Fun"
        }
      ]
    }
  }
}
```
> 만약 쿼리에서 `posts`를 빼고 `email`을 추가하면, 서버 코드 변경 없이도 클라이언트가 응답을 제어할 수 있습니다.

---

## 💡 배운 점

1.  **API의 주도권이 클라이언트로 넘어갔다**: REST가 서버 중심의 아키텍처라면, GraphQL은 클라이언트가 필요한 데이터를 선언적으로 요청하는 클라이언트 중심 아키텍처임을 이해했습니다. 이는 특히 모바일 앱처럼 네트워크 비용이 민감하고 화면 구성이 다양한 환경에 강력한 이점을 제공합니다.
2.  **스키마(Schema)가 곧 문서다**: `.graphqls`라는 강력한 타입 시스템 기반의 스키마 덕분에, API 명세가 항상 코드와 일치하게 됩니다. (Swagger/OpenAPI 문서를 별도로 관리할 필요가 줄어듦)
3.  **GraphQL도 N+1 문제가 있다**: `@SchemaMapping`을 통해 `User.posts` 같은 연관관계를 순진하게 구현하면, 유저 100명을 조회할 때 게시글 조회가 100번 나가는 **N+1 문제**가 그대로 발생합니다. 이를 해결하려면 `Dataloader`라는 기술을 사용하여 요청을 모았다가(Batch) 한 번에 처리하는 별도의 최적화가 필수적임을 깨달았습니다.

---

## 🔗 참고 자료

-   [Spring for GraphQL (Official Documentation)](https://docs.spring.io/spring-graphql/reference/)
-   [GraphQL 공식 사이트](https://graphql.org/)
-   [Introduction to Spring for GraphQL (Baeldung)](https://www.baeldung.com/spring-graphql)