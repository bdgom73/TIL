---
title: "JVM 메모리 누수 분석: Heap Dump와 Eclipse MAT로 OOM 원인 찾기"
date: 2026-01-07
categories: [Java, JVM, Troubleshooting]
tags: [OutOfMemoryError, Heap Dump, Eclipse MAT, JVM Tuning, Memory Leak, GC, TIL]
excerpt: "운영 중인 애플리케이션에서 발생한 'java.lang.OutOfMemoryError: Java heap space'의 원인을 분석하기 위해 힙 덤프(Heap Dump)를 확보하고, Eclipse MAT 도구를 사용하여 메모리 누수 지점(Dominator Tree, GC Roots)을 찾아내는 실전 분석 과정을 학습합니다."
author_profile: true
---

# Today I Learned: JVM 메모리 누수 분석: Heap Dump와 Eclipse MAT로 OOM 원인 찾기

## 📚 오늘 학습한 내용

서비스 운영 중 간헐적으로 서버가 재시작되는 현상이 발생했습니다. 로그에는 공포의 **`java.lang.OutOfMemoryError: Java heap space`**가 찍혀 있었지만, 단순히 힙 메모리(`-Xmx`)를 늘리는 것은 근본적인 해결책이 아님을 알기에, 정확한 **메모리 누수(Memory Leak)** 지점을 찾기 위해 힙 덤프 분석을 진행했습니다.

3~4년 차 개발자라면 코드를 잘 짜는 것도 중요하지만, **터진 서버의 원인을 규명하는 능력**이 필수적임을 깨닫고 JVM 메모리 분석 기법을 학습했습니다.

---

### 1. **힙 덤프(Heap Dump) 확보하기 📸**

OOM은 언제 터질지 모르기 때문에, 사고가 났을 때 JVM이 유언처럼 덤프 파일을 남기도록 설정해야 합니다.

**JVM 실행 옵션 추가**
```bash
# OOM 발생 시 자동으로 덤프 생성 (파일 경로 지정 가능)
-XX:+HeapDumpOnOutOfMemoryError 
-XX:HeapDumpPath=/var/log/app/heapdump.hprof
```

만약 실행 중인 서버에서 즉시 덤프를 떠야 한다면 `jmap`을 사용합니다.
```bash
# PID 확인 후 덤프 생성 (Live 객체만 덤프)
jmap -dump:live,format=b,file=heapdump.hprof <PID>
```

---

### 2. **분석 도구: Eclipse MAT (Memory Analyzer Tool) 🧐**

IntelliJ Profiler나 VisualVM도 좋지만, 대용량 덤프 분석에는 **Eclipse MAT**가 업계 표준에 가깝습니다.

#### **핵심 개념: Shallow Heap vs Retained Heap**

분석 리포트를 볼 때 가장 헷갈리는 두 가지 개념입니다.

1.  **Shallow Heap**: 객체 그 자체가 차지하는 메모리 크기입니다. (예: `ArrayList` 객체 자체의 껍데기 크기)
2.  **Retained Heap (중요)**: 해당 객체가 GC(Garbage Collection)될 때, **함께 회수될 수 있는 메모리의 총합**입니다.
    -   즉, 이 객체가 꽉 잡고 있어서(참조하고 있어서) GC가 못 가져가는 객체들의 합입니다.
    -   **메모리 누수의 주범을 찾으려면 Retained Heap이 비정상적으로 큰 객체를 찾아야 합니다.**

---

### 3. **누수 패턴 분석 (Dominator Tree)**

MAT의 **Dominator Tree** 뷰를 열면 메모리를 가장 많이 점유한 객체 순으로 보여줍니다.

**사례 분석:**
-   상위에 `ConcurrentHashMap` 엔트리가 수백만 개 잡혀있는 것을 발견.
-   **Path to GC Roots** 기능을 통해 누가 이 맵을 참조하고 있는지 역추적.
-   **원인**: `static`으로 선언된 캐시용 `Map`에 데이터를 `put`만 하고, 오래된 데이터를 지우는(`remove`) 로직이 없어서 무한히 쌓이고 있었음.

**문제 코드 (예시)**
```java
@Component
public class BadCacheService {
    // static 컬렉션은 GC 대상이 되지 않으므로 위험함!
    private static final Map<String, UserDto> localCache = new ConcurrentHashMap<>();

    public void cacheUser(UserDto user) {
        localCache.put(user.getId(), user); 
        // 만료 정책(TTL)이나 사이즈 제한(Eviction)이 없음 -> OOM 발생
    }
}
```

**해결**: `Caffeine Cache`나 `Ehcache` 같이 만료 정책(ExpireAfterWrite)과 최대 크기(MaximumSize)를 설정할 수 있는 라이브러리로 교체.

---

### 4. **또 다른 범인: ThreadLocal 🧵**

스레드 풀 환경에서 `ThreadLocal`을 사용할 때 `remove()`를 하지 않으면, 스레드가 재사용될 때 이전 데이터가 그대로 남아 메모리를 점유합니다. 덤프 분석 시 톰캣의 `TaskThread` 아래에 거대한 객체가 매달려 있다면 이를 의심해야 합니다.

```java
try {
    ContextHolder.set(data);
    chain.doFilter(request, response);
} finally {
    // 필수: 사용 후 반드시 비워야 메모리 누수를 방지할 수 있음
    ContextHolder.clear(); 
}
```

---

## 💡 배운 점

1.  **증거 없는 추측은 금물**: "이미지가 커서 그럴 거야", "동시 접속자가 많아서 그럴 거야"라는 추측으로 힙 메모리만 늘리는 것은 시한폭탄의 시간을 늦추는 것일 뿐입니다. 힙 덤프라는 확실한 증거(Evidence)를 통해 범인을 잡는 과정이 중요하다는 것을 배웠습니다.
2.  **GC Roots의 이해**: 어떤 객체가 메모리에서 해제되지 않는다면, 반드시 어딘가에서(Static 변수, 실행 중인 스레드 스택 등) 그 객체를 참조하고 있다는 뜻입니다. 이 연결 고리를 끊는 것이 메모리 최적화의 핵심입니다.
3.  **방어적 코딩**: `static` 컬렉션이나 `ThreadLocal`을 사용할 때는 반드시 "이 데이터가 언제 지워지는가?"를 설계 단계에서 고민해야 함을 뼈저리게 느꼈습니다.

---

## 🔗 참고 자료

-   [Eclipse Memory Analyzer (MAT)](https://eclipse.dev/mat/)
-   [Oracle: Troubleshoot Memory Leaks](https://docs.oracle.com/javase/8/docs/technotes/guides/troubleshoot/memleaks004.html)
-   [Baeldung: Understanding Memory Leaks in Java](https://www.baeldung.com/java-memory-leaks)