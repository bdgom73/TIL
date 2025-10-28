---
title: "Java NIO와 Selector를 이용한 논블로킹(Non-Blocking) 소켓 통신의 첫걸음"
date: 2025-09-10
categories: [Java, Socket, NIO]
tags: [Java NIO, Selector, Non-blocking IO, SocketChannel, ServerSocketChannel]
excerpt: "기존의 Blocking I/O 모델의 한계를 이해하고, Java NIO의 Selector를 활용하여 단일 스레드로 여러 클라이언트의 요청을 효율적으로 처리하는 논블로킹 서버의 기본 원리를 학습했다. Selector의 이벤트 기반 동작 방식과 주요 컴포넌트의 역할을 코드로 확인했다."
author_profile: true
---

## Today I Learned: Java NIO `Selector`를 이용한 논블로킹 I/O 입문

3년차 개발자로서 주로 Spring WebFlux나 Netty와 같은 프레임워크 뒤에 숨겨진 네트워킹 기술의 내부 동작이 항상 궁금했다. 오늘은 그 핵심 기술 중 하나인 **Java NIO(New I/O)**, 특히 `Selector`를 이용한 이벤트 기반의 논블로킹(Non-Blocking) 소켓 통신에 대해 깊이 학습했다.

### 기존 Blocking I/O의 문제점

전통적인 `java.net.Socket` 기반의 서버는 클라이언트 연결마다 하나의 스레드를 할당하는 "Thread-per-Client" 모델을 사용한다. 이 방식은 구현이 간단하지만, 다음과 같은 명확한 한계가 있다.

1.  **리소스 낭비**: 수만 개의 동시 연결이 발생하면 그만큼의 스레드가 생성되어 심각한 메모리 소모와 컨텍스트 스위칭 비용을 유발한다.
2.  **응답성 저하**: 대부분의 스레드는 데이터를 기다리며 블로킹(Blocking) 상태로 대기하기 때문에 CPU 자원을 비효율적으로 사용한다.

### Java NIO와 `Selector`가 해결책인 이유

Java NIO는 이러한 문제를 해결하기 위해 **이벤트 기반의 논블로킹 I/O** 모델을 도입했다. 그 중심에는 `Selector`가 있다.

-   **`Selector`**: 여러 `Channel`을 등록하고, I/O 이벤트(연결 요청, 데이터 수신 등)가 발생한 채널을 감지하는 역할을 한다.
-   **`Channel`**: 데이터가 오고 가는 통로. `SocketChannel`, `ServerSocketChannel` 등이 있다.
-   **`ByteBuffer`**: 데이터를 읽고 쓰는 버퍼. 채널은 버퍼를 통해 데이터를 처리한다.

`Selector`를 사용하면 **단 하나의 스레드**만으로 여러 클라이언트 채널에서 발생하는 이벤트를 감지하고 처리할 수 있다. 즉, 스레드는 이벤트가 발생했을 때만 동작하므로 리소스를 매우 효율적으로 사용할 수 있다.

### `Selector`를 이용한 간단한 에코 서버 구현

아래는 `Selector`의 동작 방식을 이해하기 위해 작성해 본 간단한 논블로킹 에코 서버 코드다.

```java
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.util.Iterator;
import java.util.Set;

public class NioEchoServer {
    public static void main(String[] args) throws IOException {
        // 1. Selector 생성
        Selector selector = Selector.open();

        // 2. ServerSocketChannel 생성 및 설정
        ServerSocketChannel serverSocketChannel = ServerSocketChannel.open();
        serverSocketChannel.bind(new InetSocketAddress("localhost", 8080));
        serverSocketChannel.configureBlocking(false); // 논블로킹 모드로 설정

        // 3. Selector에 채널 등록 (연결 요청 이벤트를 감지)
        serverSocketChannel.register(selector, SelectionKey.OP_ACCEPT);
        System.out.println("NIO Echo Server is running on port 8080...");

        while (true) {
            // 4. 이벤트가 발생할 때까지 대기
            selector.select();

            // 5. 발생한 이벤트 키들의 집합 가져오기
            Set<SelectionKey> selectedKeys = selector.selectedKeys();
            Iterator<SelectionKey> keyIterator = selectedKeys.iterator();

            while (keyIterator.hasNext()) {
                SelectionKey key = keyIterator.next();

                if (key.isAcceptable()) {
                    // 연결 요청 이벤트 처리
                    ServerSocketChannel serverChannel = (ServerSocketChannel) key.channel();
                    SocketChannel clientChannel = serverChannel.accept();
                    clientChannel.configureBlocking(false);
                    clientChannel.register(selector, SelectionKey.OP_READ);
                    System.out.println("New client connected: " + clientChannel.getRemoteAddress());
                } else if (key.isReadable()) {
                    // 데이터 수신(Read) 이벤트 처리
                    SocketChannel clientChannel = (SocketChannel) key.channel();
                    ByteBuffer buffer = ByteBuffer.allocate(256);
                    int bytesRead = clientChannel.read(buffer);

                    if (bytesRead == -1) {
                        // 클라이언트 연결 종료
                        clientChannel.close();
                        System.out.println("Client disconnected.");
                    } else {
                        buffer.flip();
                        // 받은 데이터를 그대로 다시 전송 (에코)
                        clientChannel.write(buffer);
                        buffer.clear();
                    }
                }
                // 처리 완료된 키는 반드시 제거해야 함
                keyIterator.remove();
            }
        }
    }
}
```

### 느낀 점

코드를 직접 작성해보니 `Selector`가 어떻게 `select()` 메서드를 통해 이벤트를 기다리고, `selectedKeys()`를 통해 발생한 이벤트들을 순회하며 처리하는지 명확하게 이해할 수 있었다. 왜 Netty와 같은 고성능 프레임워크들이 이벤트 루프(Event Loop) 모델을 사용하는지 그 근본 원리를 엿본 기분이다. 다음에는 `ByteBuffer`의 내부 구조와 Direct/Non-Direct 버퍼의 차이에 대해 더 깊이 학습해 볼 계획이다.