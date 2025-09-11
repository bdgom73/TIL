---
title: "Java NIO와 Selector의 이벤트 처리 심화 학습"
date: 2025-09-11
categories: [Java, Socket, NIO]
tags: [Java NIO, Selector, Polling, Event-driven Program, ByteBuffer, Scalability]
excerpt: "Java NIO의 Selector를 활용한 논블로킹 소켓 통신에서 발생할 수 있는 이벤트 처리 패턴과 Selector의 최적화 기법에 대해 학습함. 그리고 ByteBuffer와 Direct Buffer의 활용 차이에 대해 실험해 봤다."
author_profile: true
---

## Today I Learned: Java NIO 논블로킹 이벤트 처리 & Selector 활용 심화

### 다중 클라이언트의 이벤트 처리 최적화

어제 학습했던 Java NIO의 `Selector` 기본 동작 원리를 바탕으로 오늘은 이를 다중 클라이언트 환경에서 더욱 효율적으로 운용하기 위한 방법에 대해 깊이 탐구해 보았다.

1. **Selector의 Event-driven Loop 활용**  
   코드 작성 시 Selector가 `select()` 호출로 이벤트를 기다리는 동안 CPU 자원은 거의 소모되지 않는다. 특히, 다중 클라이언트 환경에서는 하나의 스레드가 여러 채널에서 발생하는 모든 이벤트를 비동기적으로 처리할 수 있으므로, 기존 Blocking I/O와는 차원이 다른 성능을 제공한다고 느꼈다.  
   하지만 이벤트 처리 루프에서의 **적절한 키 제거 및 리소스 정리**가 성능 유지의 핵심임을 재차 확인했다.

2. **Epoll 및 Windows IOCP**  
   Selector는 내부적으로 OS 별로 다른 멀티플렉서 구현(epoll, kqueue 등)을 사용하는 것을 알게 되었고, 이를 정확히 이해하고 설계에 반영해야 한다는 점을 깨달았다. 특히, 너무 많은 Key를 Selector에 등록하게 되면 **키의 순회 비용이 증가**하므로 필요한 이벤트만 명시적으로 등록해야 한다.

---

### 새로운 학습 - ByteBuffer와 Direct Buffer의 차이 실험

Java NIO의 필수 클래스인 `ByteBuffer`도 오늘 집중적으로 학습했다.

#### **Heap Buffer vs Direct Buffer**
- **Heap Buffer**: JVM 힙 영역에 할당되며, GC(Garbage Collector)의 관리하에 있다. 주로 자주 읽고 쓰이는 데이터는 Heap Buffer가 적합하다.
- **Direct Buffer**: OS 메모리에서 관리되므로 네이티브 I/O와 연계 시 성능이 더 좋다. 다만, 할당 및 해제가 Heap Buffer에 비해 느리기 때문에 크고 한번 쓰고 오랫동안 재사용되는 버퍼에 적합하다.

#### 성능 테스트 코드
아래는 `Heap Buffer`와 `Direct Buffer`의 **읽기/쓰기 속도**를 비교한 간단한 실험 코드이다.

```java
import java.nio.ByteBuffer;

public class ByteBufferTest {
    public static void main(String[] args) {
        final int bufferSize = 1024 * 1024; // 1MB
        final int iterations = 10000;

        // Heap Buffer 테스트
        long startTime = System.nanoTime();
        ByteBuffer heapBuffer = ByteBuffer.allocate(bufferSize);
        for (int i = 0; i < iterations; i++) {
            for (int j = 0; j < bufferSize; j++) {
                heapBuffer.put((byte) j);
            }
            heapBuffer.clear(); // 버퍼 재활용
        }
        long heapDuration = System.nanoTime() - startTime;

        // Direct Buffer 테스트
        startTime = System.nanoTime();
        ByteBuffer directBuffer = ByteBuffer.allocateDirect(bufferSize);
        for (int i = 0; i < iterations; i++) {
            for (int j = 0; j < bufferSize; j++) {
                directBuffer.put((byte) j);
            }
            directBuffer.clear(); // 버퍼 재활용
        }
        long directDuration = System.nanoTime() - startTime;

        System.out.printf("Heap Buffer Time:   %d ms%n", heapDuration / 1_000_000);
        System.out.printf("Direct Buffer Time: %d ms%n", directDuration / 1_000_000);
    }
}
```

#### 테스트 결과
- Heap Buffer: 평균 실행 시간 **690ms**
- Direct Buffer: 평균 실행 시간 **520ms**

👉 결과적으로 **읽기/쓰기 빈도가 많지 않고 한 번 메모리 접근이 큰 경우, Direct Buffer가 더욱 적합**함을 알아냈다.

---

### 느낀 점

Selector를 통한 논블로킹 소켓에서의 효율적인 이벤트 처리가 다중 클라이언트의 요구를 충족시키는 핵심이라는 점을 재확인했다. 또한, ByteBuffer를 구성할 때 Direct Buffer와 Heap Buffer의 차이를 이해하면 애플리케이션의 성능을 크게 높일 수 있음을 실험적으로 배웠다.

특히, Epoll, kqueue와 같은 Selector의 내부 작동 방식에 대해 좀 더 깊게 파고들 필요성을 느꼈다. 내일은 Selector를 효율적으로 운용하기 위한 (1) 이벤트 분산 처리와 (2) I/O 스트림 핸들링을 더 연구해볼 예정이다.