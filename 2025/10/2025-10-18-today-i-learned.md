---
title: "gRPC: Protocol Buffers를 활용한 고성능 RPC 통신"
date: 2025-10-18
categories: [Architecture, RPC]
tags: [gRPC, Protocol Buffers, Protobuf, MSA, RPC, HTTP/2, TIL]
excerpt: "MSA 환경에서 REST API의 대안으로 주목받는 gRPC의 핵심 개념을 학습합니다. Protocol Buffers(Protobuf)를 이용한 스키마 정의와 HTTP/2 기반 통신의 장점을 알아보고, Spring Boot에서 gRPC 서버와 클라이언트를 구현하는 방법을 탐구합니다."
author_profile: true
---

# Today I Learned: gRPC: Protocol Buffers를 활용한 고성능 RPC 통신

## 📚 오늘 학습한 내용

마이크로서비스 간 통신에는 주로 JSON을 사용하는 RESTful API가 널리 쓰이지만, 내부 통신이 빈번하고 고성능이 요구되는 환경에서는 텍스트 기반인 JSON의 비효율성이 단점으로 작용할 수 있습니다. 오늘은 이러한 문제를 해결하기 위해 구글에서 개발한 고성능 **RPC(Remote Procedure Call)** 프레임워크, **gRPC**에 대해 학습했습니다.

---

### 1. **gRPC란 무엇인가? 🚀**

**gRPC**는 **HTTP/2**를 기반으로 동작하며, **Protocol Buffers(Protobuf)**를 사용하여 데이터를 직렬화하는 현대적인 RPC 프레임워크입니다.

-   **RPC (Remote Procedure Call)**: 원격 프로시저 호출. 마치 로컬에 있는 메서드를 호출하는 것처럼, 네트워크로 연결된 다른 서버의 함수나 프로시저를 실행할 수 있게 해주는 기술입니다.
-   **REST API와의 차이점**:
    -   **자원(Resource) 중심 vs. 행위(Action) 중심**: REST가 HTTP 메서드(`GET`, `POST`)와 URL을 통해 '자원'을 중심으로 통신한다면, gRPC는 원격에 있는 '함수'를 직접 호출하는 것처럼 '행위'를 중심으로 통신합니다.
    -   **JSON vs. Protocol Buffers**: REST는 주로 텍스트 기반의 JSON을 사용하지만, gRPC는 바이너리(binary) 기반의 Protocol Buffers를 사용합니다. 이로 인해 데이터 크기가 작고 직렬화/역직렬화 속도가 매우 빠릅니다.

### 2. **gRPC의 핵심 구성 요소**

#### **① Protocol Buffers (Protobuf)**
-   **역할**: 서비스의 API(메서드)와 데이터 구조(메시지)를 정의하기 위한 **IDL(Interface Definition Language)**. 스키마를 `.proto` 파일에 정의하면, Protobuf 컴파일러가 다양한 언어(Java, Python, Go 등)의 클라이언트/서버 코드를 자동으로 생성해줍니다.
-   **특징**:
    -   **강력한 스키마**: 데이터의 타입과 구조가 명확하게 정의되므로, API 명세가 곧 코드가 됩니다.
    -   **바이너리 포맷**: 데이터를 이진 형태로 직렬화하여 JSON보다 훨씬 작고 빠릅니다.
    -   **하위 호환성**: 필드에 고유한 번호를 부여하는 방식으로 동작하여, 스키마가 변경되더라도 기존 버전과의 호환성을 유지하기 용이합니다.

**`.proto` 파일 예시 (`product.proto`)**
```protobuf
syntax = "proto3";

package com.example.product;

// Product 서비스 정의
service ProductService {
  // ID로 상품 조회
  rpc getProduct(GetProductRequest) returns (ProductResponse);
}

// 요청 메시지
message GetProductRequest {
  int64 product_id = 1;
}

// 응답 메시지
message ProductResponse {
  int64 id = 1;
  string name = 2;
  int32 price = 3;
}
```

#### **② HTTP/2 기반 통신**
-   gRPC는 기존 HTTP/1.1이 아닌 **HTTP/2** 위에서 동작합니다.
-   **주요 장점**:
    -   **멀티플렉싱 (Multiplexing)**: 하나의 TCP 연결 위에서 여러 개의 요청/응답 스트림을 동시에 처리할 수 있어, 통신 효율이 극대화됩니다.
    -   **서버 푸시 (Server Push)**: 클라이언트가 요청하지 않아도 서버가 필요한 리소스를 미리 보낼 수 있습니다.
    -   **스트리밍 (Streaming)**: 단일 요청/응답 모델을 넘어, 클라이언트-서버 간에 지속적인 데이터 스트림을 주고받을 수 있습니다. (단항, 서버 스트리밍, 클라이언트 스트리밍, 양방향 스트리밍)



---

### 3. **Spring Boot에서 gRPC 서버 구현하기**

**1. 의존성 및 플러그인 추가 (`build.gradle`)**
gRPC와 Protobuf 관련 라이브러리, 그리고 `.proto` 파일로부터 자바 코드를 생성해주는 `protobuf-gradle-plugin`을 추가합니다.

**2. `.proto` 파일 작성**
`src/main/proto` 디렉토리에 위에서 작성한 `product.proto` 파일을 위치시킵니다.

**3. 서비스 구현**
Protobuf 컴파일러가 생성한 `ProductServiceGrpc.ProductServiceImplBase` 추상 클래스를 상속받아 실제 비즈니스 로직을 구현합니다.
```java
import com.example.product.Product.*; // Protobuf가 생성한 클래스
import com.example.product.ProductServiceGrpc.ProductServiceImplBase;
import io.grpc.stub.StreamObserver;
import net.devh.boot.grpc.server.service.GrpcService;

@GrpcService // gRPC 서비스 빈으로 등록
public class ProductGrpcService extends ProductServiceImplBase {

    @Override
    public void getProduct(GetProductRequest request, StreamObserver<ProductResponse> responseObserver) {
        // 실제 비즈니스 로직 (DB 조회 등)
        System.out.println("Requested product ID: " + request.getProductId());

        // 응답 메시지 생성
        ProductResponse response = ProductResponse.newBuilder()
                .setId(request.getProductId())
                .setName("Awesome T-Shirt")
                .setPrice(30000)
                .build();
        
        // onNext로 응답 전송
        responseObserver.onNext(response);
        // onCompleted로 통신 종료
        responseObserver.onCompleted();
    }
}
```
> gRPC 서비스는 Spring MVC의 `@RestController`와 유사한 역할을 합니다.

---

## 💡 배운 점

1.  **MSA 내부 통신을 위한 강력한 대안**: 외부 공개 API는 여전히 JSON 기반의 REST가 유용하지만, 서비스 간의 내부 통신(East-West Traffic)처럼 성능이 매우 중요하고 API 명세가 명확하게 관리되어야 하는 환경에서는 gRPC가 훨씬 효율적인 선택지가 될 수 있음을 깨달았습니다.
2.  **스키마 우선 개발(Schema-first Development)**: `.proto` 파일을 먼저 정의함으로써, 클라이언트와 서버 개발자는 구현에 앞서 API 명세에 대한 완벽한 합의를 이룰 수 있습니다. 이는 팀 간의 협업을 원활하게 하고, 타입 불일치로 인한 런타임 에러를 원천적으로 방지합니다.
3.  **HTTP/2의 잠재력**: gRPC를 통해 HTTP/2가 가진 스트리밍, 멀티플렉싱과 같은 강력한 기능들을 제대로 활용할 수 있다는 것을 알게 되었습니다. 특히 대용량 데이터 전송이나 실시간 양방향 통신이 필요한 서비스에 gRPC를 도입하면 큰 성능 향상을 기대할 수 있습니다.

---

## 🔗 참고 자료

-   [gRPC 공식 문서](https://grpc.io/docs/)
-   [Protocol Buffers Documentation](https://protobuf.dev/overview/)
-   [gRPC with Spring Boot (Baeldung)](https://www.baeldung.com/grpc-spring-boot)