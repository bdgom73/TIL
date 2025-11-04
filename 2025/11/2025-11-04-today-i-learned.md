---
title: "Java 애플리케이션 프로파일링: JFR과 JDK Mission Control(JMC) 활용법"
date: 2025-11-04
categories: [Java, JVM, Performance]
tags: [Java Flight Recorder, JFR, JDK Mission Control, JMC, Performance Tuning, Profiling, TIL]
excerpt: "운영 환경에서 발생한 성능 저하의 원인을 '감'이 아닌 데이터로 분석하는 방법을 학습합니다. JVM에 내장된 저-오버헤드 프로파일러인 JFR로 이벤트를 기록하고, JMC로 시각화하여 병목 지점을 찾는 실전 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: Java 애플리케이션 프로파일링: JFR과 JDK Mission Control(JMC) 활용법

## 📚 오늘 학습한 내용

3~4년차 개발자가 되면서 "로컬에서는 빠른데 운영(prod)에서는 느려요" 또는 "가끔 API 응답이 5초씩 걸리는데 로그에는 아무것도 안 남아요"와 같은 막연한 성능 문제에 부딪히기 시작했습니다. `top`이나 `htop`으로 CPU 사용률을 보는 것만으로는 근본 원인을 찾기 어렵습니다.

오늘은 이러한 **운영 환경의 성능 문제를 진단**하기 위해, **JVM에 내장된** 강력하고 오버헤드가 매우 적은 프로파일링 도구인 **JFR(Java Flight Recorder)**과 **JMC(JDK Mission Control)**에 대해 학습했습니다.

---

### 1. **JFR과 JMC는 무엇인가? ✈️**

-   **JFR (Java Flight Recorder)**: JVM의 "블랙박스"입니다. JVM 내부에서 발생하는 상세한 이벤트(CPU 사용, GC, 락(Lock) 경합, I/O 등)를 **매우 낮은 오버헤드(일반적으로 1% 미만)**로 지속적으로 기록하는 데이터 수집 프레임워크입니다.
-   **JMC (JDK Mission Control)**: JFR이 수집한 기록 파일(`*.jfr`)을 열어 시각화하고 분석하는 GUI 도구입니다.

**비유**: JFR이 비행기의 모든 운항 데이터를 기록하는 '블랙박스'라면, JMC는 그 블랙박스 데이터를 재생하고 분석하는 '관제 센터'입니다.

---

### 2. **왜 JFR/JMC를 사용해야 하는가?**

-   **Production-Safe**: 오버헤드가 극히 낮아, 24/7 운영 환경에서도 부담 없이 활성화하여 데이터를 수집할 수 있습니다.
-   **JVM 내장**: JDK 11부터는 표준(Standard) 기능으로 포함되어 별도 설치가 필요 없습니다.
-   **Holistic View**: CPU, 메모리(GC), 스레드(락), I/O 등 시스템 전반의 데이터를 한 번에 수집하여 문제의 원인을 종합적으로 분석할 수 있게 해줍니다.

---

### 3. **JFR 데이터 수집 방법**

운영 중인 Spring Boot 애플리케이션에서 JFR 데이터를 수집하는 방법은 다양합니다.

#### **방법 1: `jcmd` 명령어로 직접 수집 (가장 일반적)**
SSH로 서버에 접속하여 실행 중인 Java 프로세스에서 직접 데이터를 수집합니다.

1.  **프로세스 ID(PID) 확인**
    ```bash
    ps -ef | grep java
    # 12345 ... my-app.jar
    ```

2.  **JFR 레코딩 시작** (e.g., 5분간 `profile` 설정을 사용해 기록)
    ```bash
    # jcmd <PID> JFR.start name=my-recording settings=profile duration=5m filename=/tmp/my-recording.jfr
    jcmd 12345 JFR.start name=my-recording settings=profile duration=5m filename=/tmp/my-recording.jfr
    ```
    -   `settings=profile`: 일반적인 성능 분석에 필요한 상세 데이터를 수집합니다. (`default`는 더 가벼움)
    -   `duration=5m`: 5분 동안 데이터를 수집합니다. (지정하지 않으면 `JFR.stop`으로 중지할 때까지 계속 수집)

3.  **레코딩 파일 다운로드**: 5분 뒤 생성된 `/tmp/my-recording.jfr` 파일을 로컬 PC로 다운로드합니다.

#### **방법 2: Spring Boot Actuator로 수집 (권장)**
`actuator` 의존성이 있다면, HTTP 엔드포인트를 통해 JFR을 제어할 수 있습니다.

**`application.yml`**
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,jfr # jfr 엔드포인트 노출
```

**JFR 덤프 생성**
`curl` 명령어로 `/actuator/jfr` 엔드포인트를 호출하면, 현재까지 수집된 데이터를 즉시 파일로 덤프하여 다운로드할 수 있습니다.
```bash
# JFR 덤프를 시작하고, my-recording.jfr 파일로 다운로드
curl -o my-recording.jfr http://localhost:8080/actuator/jfr
```

---

### 4. **JMC로 병목 지점 찾기 (무엇을 보아야 하는가?)**

다운로드한 `my-recording.jfr` 파일을 JMC(JDK Mission Control)로 열면, 방대한 양의 데이터가 나옵니다. 3~4년차 개발자로서 다음 3가지를 중점적으로 확인해야 합니다.

**1. 메서드 프로파일링 (Hot Methods)**
-   **위치**: `Java 애플리케이션` -> `메서드 프로파일링` 탭
-   **확인**: **"어떤 메서드가 CPU를 가장 많이 사용했는가?"**
-   **분석**: `top`에서 CPU 사용률은 높은데 원인을 모르겠을 때, 여기서 1위를 차지한 메서드가 병목 지점일 확률이 높습니다. (e.g., 비효율적인 `for` 루프, 불필요한 객체 변환 등)

**2. 스레드 락(Lock) 경합 (Contention)**
-   **위치**: `스레드` -> `경합` 탭
-   **확인**: **"스레드들이 특정 락을 얻기 위해 얼마나 오래 기다렸는가?"**
-   **분석**: `synchronized` 블록이나 `ReentrantLock`을 잘못 사용하여 여러 스레드가 동시에 대기(Blocked) 상태에 빠져 시스템 전체의 처리량(Throughput)이 저하되는 지점을 찾을 수 있습니다.

**3. TLAB 할당 (메모리 분석)**
-   **위치**: `메모리` -> `TLAB별 할당` 탭
-   **확인**: **"어떤 메서드가 객체를 가장 많이, 그리고 자주 생성했는가?"**
-   **분석**: GC(Garbage Collection)가 너무 자주 발생한다면, 이 탭에서 불필요하게 많은 임시 객체를 생성하는 메서드를 찾아내어 메모리 할당을 최적화할 수 있습니다.

---

## 💡 배운 점

1.  **'감'이 아닌 '데이터' 기반의 튜닝**: JFR/JMC는 "이 부분이 느릴 것 같아"라는 추측이 아닌, 실제 운영 환경의 데이터를 기반으로 성능을 분석할 수 있게 해주는 강력한 도구입니다. 3~4년차 개발자로서 객관적인 데이터를 제시하며 성능 개선을 주도할 수 있어야 합니다.
2.  **오버헤드 걱정 없는 운영 환경 프로파일링**: JFR의 가장 큰 장점은 '낮은 오버헤드'입니다. 덕분에 운영 환경에서 문제가 발생했을 때, 재현이 어려운 문제를 서버 재시작 없이 즉시 데이터를 수집하여 분석할 수 있습니다.
3.  **성능 문제는 결국 '종합 예술'이다**: JMC를 통해 CPU, 메모리, 스레드, I/O를 한눈에 보니, 성능 문제는 어느 한 부분의 문제가 아니라 여러 요소가 복합적으로 작용하는 경우가 많다는 것을 깨달았습니다. (e.g., 불필요한 객체 생성(`TLAB`)이 잦으면 `GC`가 자주 발생하고, 이로 인해 `CPU` 사용량이 높아진다.)

---

## 🔗 참고 자료

-   [JEP 328: Flight Recorder (Official Java Docs)](https://openjdk.org/jeps/328)
-   [Spring Boot Docs - Java Flight Recorder](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.jfr)
-   [Introduction to JFR (Baeldung)](https://www.baeldung.com/java-flight-recorder-monitoring)