---
title: "Redis의 특수 자료구조: HyperLogLog와 Bitmap으로 대용량 데이터 효율적으로 처리하기"
date: 2025-11-26
categories: [Database, Redis]
tags: [Redis, HyperLogLog, Bitmap, Performance, Big Data, Counting, TIL]
excerpt: "수백만 명의 일일 방문자 수(DAU)나 출석 체크 데이터를 처리할 때, RDBMS나 일반적인 Redis Set이 가진 메모리 한계를 극복하는 방법입니다. 오차율 0.81%로 메모리를 획기적으로 절약하는 HyperLogLog와 비트 단위 연산으로 상태를 관리하는 Bitmap의 원리와 활용법을 학습합니다."
author_profile: true
---

# Today I Learned: Redis의 특수 자료구조: HyperLogLog와 Bitmap으로 대용량 데이터 효율적으로 처리하기

## 📚 오늘 학습한 내용

서비스의 규모가 커지면서 단순한 CRUD를 넘어 **"오늘 방문한 순수 사용자 수(UV)는 몇 명인가?"** 혹은 **"이 유저가 이번 달에 며칠 출석했는가?"**와 같은 통계성 데이터를 실시간으로 처리해야 하는 요구사항이 늘어납니다.

이때 RDBMS의 `COUNT(DISTINCT user_id)`는 데이터가 많아질수록 느려지고, Redis의 `Set` 자료구조에 모든 ID를 담는 것은 메모리 비용이 너무 큽니다. 오늘은 이러한 대용량 카운팅 문제를 아주 적은 메모리로 해결해주는 Redis의 특수 자료구조 **HyperLogLog**와 **Bitmap**에 대해 학습했습니다.

---

### 1. **HyperLogLog: 12KB로 수억 건의 중복 제거 카운팅하기 📊**

**HyperLogLog**는 집합의 원소 개수(Cardinality)를 추정하기 위한 확률적 자료구조입니다.

-   **핵심 특징**:
    -   **고정된 메모리**: 입력되는 데이터의 양이 백만 건이든 10억 건이든, 단 **12KB**의 고정된 메모리만 사용합니다.
    -   **오차 허용**: 약 **0.81%**의 표준 오차를 가집니다. (e.g., 100만 명 방문 시 약 8,100명의 오차). 정확한 수치보다는 추세나 대략적인 규모 파악이 중요한 지표(DAU, 검색 키워드 수 등)에 적합합니다.
    -   **데이터 조회 불가**: 값을 넣을 수는 있지만, "어떤 값이 들어있는지"를 꺼내볼 수는 없습니다. (카운팅 전용)

#### **Spring Boot (RedisTemplate) 활용 예시: DAU 측정**

```java
@Service
@RequiredArgsConstructor
public class AnalyticsService {

    private final RedisTemplate<String, String> redisTemplate;

    // 사용자가 방문할 때마다 호출
    public void logVisit(String userId) {
        String key = "dau:" + LocalDate.now().toString(); // e.g., dau:2025-11-26
        // 1. HyperLogLog에 요소 추가 (PFADD)
        redisTemplate.opsForHyperLogLog().add(key, userId);
    }

    // 실시간 방문자 수 조회
    public Long getDailyActiveUsers() {
        String key = "dau:" + LocalDate.now().toString();
        // 2. 카디널리티(개수) 조회 (PFCOUNT)
        return redisTemplate.opsForHyperLogLog().size(key);
    }
}
```
> **비교**: 만약 1,000만 명의 유저 ID(Long, 8byte)를 `Set`에 저장한다면 약 **80MB**가 필요하지만, HyperLogLog는 **12KB**면 충분합니다.

---

### 2. **Bitmap: 0과 1로 관리하는 수백만 유저의 상태 ✅**

**Bitmap**은 Redis의 String 자료구조(최대 512MB)를 비트(Bit) 단위로 제어하는 기술입니다.

-   **핵심 특징**:
    -   **극강의 공간 효율성**: 유저 ID를 오프셋(Offset)으로 사용하여, 해당 유저의 상태(참/거짓)를 **1비트**로 표현합니다. 100만 명의 상태를 저장하는 데 단 **125KB** (1,000,000 bits / 8)만 필요합니다.
    -   **비트 연산**: 여러 Bitmap 간의 `AND`, `OR`, `XOR`, `NOT` 연산이 매우 빠릅니다.

#### **활용 예시: 출석 체크 및 활성 유저 분석**

1.  **출석 체크 (`SETBIT`)**
    -   Key: `attendance:2025-11-26`
    -   User ID가 12345인 유저가 출석하면, 해당 오프셋의 비트를 1로 설정합니다.

2.  **특정 유저 출석 여부 확인 (`GETBIT`)**
    -   User ID 12345의 비트 값이 1인지 0인지 확인합니다.

3.  **고급 분석 (`BITOP`)**
    -   "최근 3일 연속 출석한 유저 수"를 구하고 싶다면?
    -   3일치 Bitmap을 `AND` 연산하여 새로운 Bitmap을 만들고, 1의 개수(`BITCOUNT`)를 세면 됩니다.

#### **Spring Boot 활용 코드**

```java
@Service
@RequiredArgsConstructor
public class AttendanceService {

    private final RedisTemplate<String, String> redisTemplate;

    // 출석 처리
    public void checkIn(Long userId) {
        String key = "attendance:" + LocalDate.now().toString();
        // SETBIT key offset value
        redisTemplate.opsForValue().setBit(key, userId, true);
    }

    // 특정 유저 출석 여부 확인
    public Boolean isCheckedIn(Long userId) {
        String key = "attendance:" + LocalDate.now().toString();
        return redisTemplate.opsForValue().getBit(key, userId);
    }

    // 오늘 총 출석자 수 (BITCOUNT)
    public Long countTodayAttendees() {
        String key = "attendance:" + LocalDate.now().toString();
        return redisTemplate.execute((RedisCallback<Long>) connection -> 
                connection.stringCommands().bitCount(key.getBytes())
        );
    }
    
    // (심화) 이번 주 개근 유저 수 계산 (AND 연산)
    public Long countWeeklyPerfectAttendees() {
        String destKey = "attendance:weekly_perfect";
        byte[][] keys = {
            "attendance:2025-11-24".getBytes(),
            "attendance:2025-11-25".getBytes(),
            "attendance:2025-11-26".getBytes()
            // ...
        };
        
        // BITOP AND destKey key1 key2 ...
        redisTemplate.execute((RedisCallback<Long>) connection -> 
             connection.stringCommands().bitOp(BitOperation.AND, destKey.getBytes(), keys)
        );
        
        // 결과 카운팅
        return redisTemplate.execute((RedisCallback<Long>) connection -> 
                connection.stringCommands().bitCount(destKey.getBytes())
        );
    }
}
```

---

## 💡 배운 점

1.  **자료구조가 성능을 결정한다**: "데이터를 어떻게 저장할까?"라는 질문에 항상 `Table`이나 `JSON`만 떠올렸습니다. 데이터의 특성(단순 카운팅, Boolean 상태)에 맞춰 HyperLogLog나 Bitmap 같은 특수 자료구조를 선택하면 비용과 성능 문제를 획기적으로 해결할 수 있음을 깨달았습니다.
2.  **정확도와 효율성의 트레이드오프**: HyperLogLog는 100% 정확하지 않습니다. 하지만 마케팅용 DAU 지표에서 0.81%의 오차는 비용 절감 효과에 비하면 충분히 감수할 만한 트레이드오프입니다. 기술 선택 시 비즈니스 요구사항(정확도가 필수인가?)을 먼저 파악해야 합니다.
3.  **ID 설계의 중요성**: Bitmap을 효율적으로 쓰려면 유저 ID가 `Auto Increment` 형태의 정수여야 유리합니다. UUID처럼 긴 문자열이나 랜덤 한 값은 오프셋으로 쓰기 어려워 별도의 매핑 테이블이 필요할 수 있다는 점을 고려해야 합니다.

---

## 🔗 참고 자료

-   [Redis HyperLogLog Docs](https://redis.io/docs/data-types/hyperloglogs/)
-   [Redis Bitmap Docs](https://redis.io/docs/data-types/bitmaps/)
-   [Fast, Cheap, and accurate: Cardinality estimation with HyperLogLog](https://engineering.fb.com/2018/12/13/data-infrastructure/hyperloglog/)