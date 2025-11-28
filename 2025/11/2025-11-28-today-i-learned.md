---
title: "Redis 고급 최적화: Pipeline과 Lua Script로 네트워크 왕복(RTT) 줄이기"
date: 2025-11-28
categories: [Database, Redis]
tags: [Redis, Pipelining, Lua Script, Optimization, Performance, Network, TIL]
excerpt: "Redis 성능 병목의 주범인 네트워크 왕복 시간(RTT)을 최소화하는 고급 기법을 학습합니다. 대량의 명령어를 한 번에 전송하는 Pipeline과, 여러 명령어를 원자적(Atomic)으로 실행하는 Lua Script의 사용법과 차이점을 알아봅니다."
author_profile: true
---

# Today I Learned: Redis 고급 최적화: Pipeline과 Lua Script로 네트워크 왕복(RTT) 줄이기

## 📚 오늘 학습한 내용

Redis는 인메모리 DB로서 매우 빠르지만, 실제 운영 환경에서는 **네트워크 지연(Network Latency)**이 성능의 가장 큰 병목이 됩니다. Redis가 아무리 1ms 안에 응답을 만들어도, 서버와 Redis 사이의 네트워크 왕복 시간(RTT)이 10ms라면 전체 응답 시간은 10ms 이상이 걸립니다.

오늘은 3~4년차 개발자로서 단순한 `get/set`을 넘어, **네트워크 비용을 극적으로 줄이고 성능을 최적화**할 수 있는 두 가지 고급 기술인 **Pipeline**과 **Lua Script**에 대해 학습했습니다.

---

### 1. **문제 상황: 반복적인 네트워크 호출 (N번의 RTT) 🐢**

예를 들어, 사용자 1,000명의 정보를 Redis에 저장해야 한다고 가정해봅시다.

```java
// 최악의 경우: 1,000번의 네트워크 통신 발생
for (User user : users) {
    redisTemplate.opsForValue().set("user:" + user.getId(), user.getName());
}
```
이 코드는 Redis 서버와 1,000번의 **요청-응답(Request-Response)**을 주고받습니다. RTT가 1ms라면, 총 1초(1,000ms)가 소요됩니다. Redis의 처리 속도보다 네트워크를 왔다 갔다 하는 시간이 훨씬 깁니다.

---

### 2. **Redis Pipelining: 묶음 배송으로 RTT 줄이기 📦**

**Pipelining**은 여러 개의 명령어를 한 번에 보내고, 응답도 한 번에 모아서 받는 기술입니다.

-   **원리**: 클라이언트는 응답을 기다리지 않고 계속 요청을 보냅니다(Send-Send-Send). Redis는 요청을 처리하고 응답을 메모리에 쌓아두었다가 마지막에 한꺼번에 반환합니다(Receive-All).
-   **효과**: 1,000번의 RTT를 **1번의 RTT**로 줄일 수 있습니다.

#### **Spring Boot (RedisTemplate) 적용 예시**

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final StringRedisTemplate redisTemplate;

    public void bulkInsertUsers(List<User> users) {
        // executePipelined를 사용하여 파이프라인 시작
        redisTemplate.executePipelined(new SessionCallback<Object>() {
            @Override
            public Object execute(RedisOperations operations) throws DataAccessException {
                for (User user : users) {
                    // 이 안에서의 명령어는 즉시 실행되지 않고 큐에 쌓임
                    operations.opsForValue().set("user:" + user.getId(), user.getName());
                }
                // 파이프라인 내에서는 반환값이 의미가 없으므로 null 반환
                return null; 
            }
        });
    }
}
```
> **주의**: 파이프라인 내부에서는 `get` 명령어를 사용해도 즉시 값을 받아볼 수 없습니다(응답이 나중에 오기 때문). 따라서 **쓰기(Write) 위주의 배치 작업**에 가장 적합합니다.

---

### 3. **Lua Script: 원자성(Atomicity)과 성능을 동시에 ⚡️**

Pipelining은 빠르지만, 명령어 간의 **인과관계**가 있거나 **원자성**이 필요할 때는 사용할 수 없습니다. (e.g., "값을 읽어보고(GET), 그 값이 10보다 작으면 1을 더해라(INCR)")

**Lua Script**는 Redis 서버 내부에서 실행되는 스크립트입니다.

-   **원자성 보장**: Redis는 싱글 스레드로 동작하므로, 스크립트가 실행되는 동안 다른 명령어는 실행되지 않습니다. `WATCH`/`MULTI`/`EXEC` 트랜잭션보다 훨씬 빠르고 간편하게 원자성을 보장합니다.
-   **네트워크 최적화**: 복잡한 로직을 하나의 스크립트로 짜서 보내면, 수십 번의 `GET`/`SET` 왕복을 **단 1번의 스크립트 실행 요청**으로 줄일 수 있습니다.

#### **Spring Boot (RedisTemplate) 적용 예시**

**시나리오**: "선착순 쿠폰 발급" (재고 확인 후 차감)
`lua/decrease_stock.lua` 파일을 `src/main/resources`에 생성합니다.

```lua
-- KEYS[1]: 재고 Key
-- ARGV[1]: 차감할 수량

local stock = tonumber(redis.call('GET', KEYS[1]))

if stock == nil then
    return -1 -- 재고 키가 없음
end

if stock >= tonumber(ARGV[1]) then
    return redis.call('DECRBY', KEYS[1], ARGV[1]) -- 차감 후 남은 재고 반환
else
    return -2 -- 재고 부족
end
```

**Java 코드에서 호출**
```java
@Service
@RequiredArgsConstructor
public class CouponService {

    private final StringRedisTemplate redisTemplate;
    private final DefaultRedisScript<Long> decreaseStockScript;

    // 생성자에서 스크립트 로드
    public CouponService(StringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
        this.decreaseStockScript = new DefaultRedisScript<>();
        this.decreaseStockScript.setLocation(new ClassPathResource("lua/decrease_stock.lua"));
        this.decreaseStockScript.setResultType(Long.class);
    }

    public void issueCoupon(String couponId) {
        // runScript(스크립트, 키 리스트, 인자 리스트)
        Long result = redisTemplate.execute(
                decreaseStockScript, 
                Collections.singletonList("coupon:" + couponId), 
                "1"
        );

        if (result == -2) {
            throw new RuntimeException("Sold out!");
        }
    }
}
```
> 서버에서 `GET`하고 애플리케이션에서 `if`문 검사 후 `DECR`하는 과정(Race Condition 위험)을, Lua Script 하나로 **원자적이고 빠르게** 처리했습니다.

---

### 4. **Pipeline vs. Lua Script 선택 가이드**

| 특징 | **Pipeline** | **Lua Script** |
| :--- | :--- | :--- |
| **목적** | 대량의 명령어 고속 처리 (Throughput) | 복잡한 로직의 원자적 실행 (Atomicity + Latency) |
| **동작 방식** | 요청을 모아서 한 번에 전송 (비동기 응답) | 서버 내부에서 로직 실행 (동기 실행) |
| **중간 결과 사용** | **불가능** (앞 명령어의 결과를 뒤에서 사용 불가) | **가능** (변수에 담아 로직 분기 가능) |
| **주요 사례** | 대량 데이터 Insert, 로그 적재, 초기화 | 선착순 이벤트, 분산 락 구현, 복합 연산 |

---

## 💡 배운 점

1.  **네트워크는 비싸다**: Redis 자체의 성능보다 네트워크 왕복 비용(RTT)이 전체 성능을 좌우하는 경우가 많습니다. 쿼리 튜닝만큼이나 **네트워크 호출 횟수 튜닝**이 중요하다는 것을 깨달았습니다.
2.  **Lua Script는 Redis의 'Stored Procedure'다**: DB의 프로시저처럼 Redis 내부에서 로직을 태움으로써, 네트워크 비용을 줄이고 동시성 문제(Race Condition)를 락 없이 깔끔하게 해결할 수 있는 강력한 도구임을 알게 되었습니다.
3.  **적재적소 활용**: 단순한 대량 데이터 입력에는 Pipeline이 압도적으로 유리하고, 데이터의 상태를 확인하고 변경하는 로직에는 Lua Script가 유리합니다. 두 기술을 적절히 섞어 쓰는 것이 Redis 성능 최적화의 지름길입니다.

---

## 🔗 참고 자료

-   [Redis Pipelining (Official Docs)](https://redis.io/docs/manual/pipelining/)
-   [Redis Scripting with Lua (Official Docs)](https://redis.io/docs/manual/programmability/eval-intro/)
-   [Spring Data Redis - Scripting](https://docs.spring.io/spring-data/redis/docs/current/reference/html/#scripting)
