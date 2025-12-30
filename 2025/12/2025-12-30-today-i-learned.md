---
title: "REST를 넘어선 고성능 통신: Spring Boot에서 gRPC와 Protobuf 도입하기"
date: 2025-12-30
categories: [Network, MSA, Spring]
tags: [gRPC, Protobuf, HTTP/2, Spring Boot, Microservices, Performance, RPC, TIL]
excerpt: "MSA 내부 통신에서 JSON/REST의 오버헤드를 줄이기 위해 구글이 개발한 gRPC를 도입합니다. Protocol Buffers(Protobuf)를 이용한 인터페이스 정의(IDL)부터 Spring Boot 서버 및 클라이언트 구현까지의 과정을 학습하고, HTTP/2 기반의 멀티플렉싱 성능 이점을 이해합니다."
author_profile: true
---

# Today I Learned: REST를 넘어선 고성능 통신: Spring Boot에서 gRPC와 Protobuf 도입하기

## 📚 오늘 학습한 내용

마이크로서비스 간의 통신이 잦아지면서, JSON 직렬화/역직렬화 비용과 HTTP/1.1의 텍스트 기반 통신이 전체 시스템의 레이턴시(Latency)를 증가시키는 병목이 되고 있습니다. 외부 클라이언트와의 통신은 REST API가 표준이지만, **내부 서비스 간 통신(Internal Service-to-Service)**은 더 가볍고 빠른 대안이 필요합니다.

오늘은 바이너리 프로토콜과 HTTP/2를 사용하여 압도적인 성능을 자랑하는 **gRPC(gRPC Remote Procedure Call)**를 Spring Boot 환경에 구축하는 방법을 학습했습니다.

---

### 1. **gRPC와 REST의 차이점 🚀**

| 특징 | **REST (JSON)** | **gRPC (Protobuf)** |
| :--- | :--- | :--- |
| **데이터 포맷** | Text (JSON, XML) - 사람이 읽기 쉬움 | Binary (Protobuf) - 작고 빠름 |
| **전송 프로토콜** | HTTP/1.1 (주로) | **HTTP/2** (멀티플렉싱, 헤더 압축) |
| **계약(Contract)** | Swagger/OpenAPI (선택적) | **.proto 파일** (필수, 엄격한 타입) |
| **방향성** | 요청/응답 (단방향) | 양방향 스트리밍 지원 |
| **용도** | 대외 API, 브라우저 통신 | **내부 MSA 통신**, 모바일 백엔드 |



---

### 2. **구현 과정: `.proto` 정의부터 코드 생성까지**

gRPC는 **IDL(Interface Definition Language)** 기반이므로, 먼저 서비스와 메시지 구조를 정의해야 합니다.

#### **Step 1: `service.proto` 작성**
`src/main/proto` 디렉토리에 파일을 생성합니다.

```protobuf
syntax = "proto3";

package com.example.grpc;

option java_multiple_files = true;
option java_package = "com.example.grpc.lib";
option java_outer_classname = "OrderProto";

// 서비스 정의 (인터페이스)
service OrderService {
  rpc GetOrder (OrderRequest) returns (OrderResponse) {};
}

// 메시지 정의 (DTO)
message OrderRequest {
  int64 orderId = 1;
}

message OrderResponse {
  int64 orderId = 1;
  string productName = 2;
  double price = 3;
  OrderStatus status = 4;
}

enum OrderStatus {
  PENDING = 0;
  SHIPPED = 1;
  DELIVERED = 2;
}
```

#### **Step 2: 의존성 추가 및 코드 생성**
`grpc-spring-boot-starter`를 사용하면 설정이 매우 간편해집니다.

```groovy
// build.gradle
plugins {
    id 'com.google.protobuf' version '0.9.4' // Protobuf 플러그인
}

dependencies {
    implementation 'net.devh:grpc-server-spring-boot-starter:2.15.0.RELEASE' // 서버용
    // implementation 'net.devh:grpc-client-spring-boot-starter:2.15.0.RELEASE' // 클라이언트용
    implementation 'io.grpc:grpc-stub:1.58.0'
    implementation 'io.grpc:grpc-protobuf:1.58.0'
}

// Protobuf 플러그인 설정 (빌드 시 자바 코드 자동 생성)
protobuf {
    protoc { artifact = "com.google.protobuf:protoc:3.24.0" }
    plugins {
        grpc { artifact = "io.grpc:protoc-gen-grpc-java:1.58.0" }
    }
    generateProtoTasks {
        all()*.plugins { grpc {} }
    }
}
```
빌드를 수행하면 `build/generated` 폴더에 `OrderServiceGrpc.java` 등의 Stub 코드가 생성됩니다.

---

### 3. **서버(Server) 구현**

생성된 베이스 클래스(`OrderServiceGrpc.OrderServiceImplBase`)를 상속받아 비즈니스 로직을 구현합니다. 컨트롤러(`@RestController`)와 유사한 역할입니다.

```java
@GrpcService // Spring Bean으로 등록하고 gRPC 서버 포트(기본 9090)를 엽니다.
@RequiredArgsConstructor
public class GrpcOrderService extends OrderServiceGrpc.OrderServiceImplBase {

    private final OrderRepository orderRepository;

    @Override
    public void getOrder(OrderRequest request, StreamObserver<OrderResponse> responseObserver) {
        // 1. 요청 데이터 꺼내기
        Long orderId = request.getOrderId();

        // 2. 비즈니스 로직 (DB 조회)
        Order order = orderRepository.findById(orderId).orElseThrow();

        // 3. 응답 객체 빌드 (Builder 패턴 자동 생성됨)
        OrderResponse response = OrderResponse.newBuilder()
                .setOrderId(order.getId())
                .setProductName(order.getName())
                .setPrice(order.getPrice())
                .setStatus(OrderStatus.valueOf(order.getStatus().name()))
                .build();

        // 4. 응답 전송 및 완료 처리
        responseObserver.onNext(response);
        responseObserver.onCompleted();
    }
}
```

---

### 4. **클라이언트(Client) 구현**

다른 서비스에서 gRPC 서버를 호출할 때는 `Stub`을 사용합니다.

```java
@Service
public class OrderClientService {

    // net.devh 스타터가 제공하는 주입 방식
    @GrpcClient("order-service") // application.yml에 설정된 주소로 연결
    private OrderServiceGrpc.OrderServiceBlockingStub orderServiceStub;

    public String getOrderName(Long id) {
        // 1. 요청 객체 생성
        OrderRequest request = OrderRequest.newBuilder().setOrderId(id).build();

        // 2. RPC 호출 (마치 로컬 메서드 호출하듯이)
        OrderResponse response = orderServiceStub.getOrder(request);

        return response.getProductName();
    }
}
```

**application.yml (Client Side)**
```yaml
grpc:
  client:
    order-service:
      address: static://localhost:9090 # 또는 Eureka/K8s DNS 사용
      negotiation-type: plaintext # 개발용 (SSL 미적용)
```

---

## 💡 배운 점

1.  **엄격한 타입 시스템의 안정성**: JSON으로 통신할 때는 필드명 오타나 타입 불일치(String vs Int)로 인한 런타임 에러가 종종 발생했습니다. gRPC는 `.proto` 파일이 **컴파일 시점**에 코드를 생성해주므로, 인터페이스 변경 시 컴파일 에러가 발생하여 유지보수가 훨씬 안전해졌습니다.
2.  **HTTP/2의 위력**: 하나의 커넥션으로 여러 요청을 동시에 처리하는 멀티플렉싱(Multiplexing) 덕분에, 기존 REST 통신에서 발생하던 **HOL(Head of Line) Blocking** 문제가 해결되고 처리량이 비약적으로 상승함을 알 수 있었습니다.
3.  **디버깅의 어려움**: JSON은 눈으로 바로 읽을 수 있지만, Protobuf는 바이너리라서 패킷 캡처나 로깅만으로는 내용을 알기 어렵습니다. `BloomRPC`나 `Postman(gRPC 지원)` 같은 전용 툴 사용법을 익혀야 개발 생산성을 유지할 수 있습니다.

---

## 🔗 참고 자료

-   [gRPC Official Docs](https://grpc.io/docs/languages/java/)
-   [Spring Boot Starter for gRPC (LogNet)](https://github.com/LogNet/grpc-spring-boot-starter)
-   [Protocol Buffers Guide](https://protobuf.dev/programming-guides/proto3/)