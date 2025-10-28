---
title: "JPA 2차 캐시(Second-Level Cache) 적용 및 학습"
date: 2025-09-01
categories: [JPA]
tags: [JPA, PersistenceContext]
excerpt: "오늘은 JPA의 성능을 한 단계 더 끌어올릴 수 있는 **캐싱** 전략에 대해 공부했다. 특히, 트랜잭션 범위를 넘어서는 2차 캐시(L2 Cache)에 집중했다. 1차 캐시만으로는 해결할 수 없는 성능 문제를 어떻게 개선할 수 있는지 명확하게 알게 된 시간이었다."
author_profile: true
---

# Today I Learned: [JPA] 2차 캐시(Second-Level Cache) 적용 및 학습 TIL

오늘은 JPA의 성능을 한 단계 더 끌어올릴 수 있는 **캐싱** 전략에 대해 공부했다. 특히, 트랜잭션 범위를 넘어서는 **2차 캐시(L2 Cache)**에 집중했다. 1차 캐시만으로는 해결할 수 없는 성능 문제를 어떻게 개선할 수 있는지 명확하게 알게 된 시간이었다.

---

## 1. 1차 캐시의 명확한 한계

복습 차원에서 짚고 넘어가자면, **1차 캐시**는 영속성 컨텍스트 내부에 존재하며 **같은 트랜잭션 안에서**만 유효하다.

-   **한계점:** 트랜잭션이 다르면 1차 캐시는 아무런 도움이 되지 않는다. `userA`가 조회한 엔티티를 잠시 후 `userB`가 다시 조회할 때, `userB`의 트랜잭션에서는 1차 캐시가 비어있으므로 결국 또다시 DB에 SELECT 쿼리를 보내야 한다. 애플리케이션 전체 관점에서는 여전히 DB 부하가 발생한다.

이러한 한계를 극복하기 위해 필요한 것이 바로 **2차 캐시**다.

---

## 2. 2차 캐시: 애플리케이션 레벨의 공유 캐시 🚀

-   **What I Learned:** 2차 캐시는 영속성 컨텍스트(즉, 트랜잭션)의 범위를 넘어 **애플리케이션 전체에서 공유되는 캐시**다. 여러 트랜잭션에서 동일한 데이터를 반복적으로 조회할 때, DB 접근 횟수를 획기적으로 줄여주는 강력한 기능이다. JPA 구현체(하이버네이트)가 직접 관리하며, Ehcache나 Infinispan 같은 외부 캐시 라이브러리와 연동하여 사용한다.
-   **동작 과정:**
    1.  엔티티를 조회할 때, 먼저 **1차 캐시**를 확인한다.
    2.  1차 캐시에 없으면, **2차 캐시**를 확인한다.
    3.  2차 캐시에도 없으면, **DB에서 조회**한다.
    4.  DB에서 조회한 데이터를 **2차 캐시와 1차 캐시에 각각 저장**한 후, 엔티티를 반환한다.

---

## 3. Ehcache로 2차 캐시 적용하기 (How-To)

오늘은 가장 대중적인 Ehcache를 기준으로 적용법을 정리했다.

### 1) 의존성 추가 (`build.gradle`)

하이버네이트와 Ehcache를 연동하기 위한 라이브러리를 추가한다.

```groovy
// 하이버네이트 2차 캐시 모듈
implementation 'org.hibernate.orm:hibernate-jcache:6.2.7.Final'
// Ehcache 구현체
implementation 'org.ehcache:ehcache:3.10.8'
```

### 2) `application.yml` 설정

스프링 부트 환경에서는 yml 파일에 간단한 설정으로 2차 캐시를 활성화할 수 있다.

```yaml
spring:
  jpa:
    properties:
      hibernate:
        # 2차 캐시 활성화
        cache.use_second_level_cache: true
        # 쿼리 캐시 활성화 (선택 사항)
        cache.use_query_cache: true
        # 캐시 구현체 지정
        cache.region.factory_class: org.hibernate.cache.jcache.JCacheRegionFactory
```

### 3) 캐시 대상 엔티티 지정 (`@Cacheable`)

모든 엔티티가 캐시되는 것은 아니다. 캐시를 적용하고 싶은 엔티티 클래스에 `@Cacheable` 어노테이션을 붙여줘야 한다.

```java
import jakarta.persistence.Cacheable;
import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;

@Entity
@Cacheable // 2차 캐시 대상임을 명시
@Cache(usage = CacheConcurrencyStrategy.READ_WRITE) // 캐시 동시성 전략 설정
public class Member {
    // ... 필드
}
```

### 4. 캐시 동시성 전략 (Concurrency Strategy)

`@Cache` 어노테이션의 `usage` 속성으로 설정하는 동시성 전략이 정말 중요했다. 데이터의 변경 빈도와 일관성 수준을 고려해서 신중하게 선택해야 한다.

-   **`READ_ONLY`**: 절대 변경되지 않는 데이터에 사용한다. (예: 국가 코드, 공휴일 정보). 가장 성능이 좋지만, 수정 시 에러가 발생한다.
-   **`NONSTRICT_READ_WRITE`**: 데이터가 자주 변경되지 않고, 약간의 데이터 불일치를 감수할 수 있을 때 사용한다. (예: 사용자 프로필, 게시물). 캐시와 DB 데이터가 아주 잠깐 달라질 수 있지만, 락을 사용하지 않아 성능이 좋다.
-   **`READ_WRITE`**: 데이터 일관성이 매우 중요할 때 사용한다. (예: 계좌 잔고, 상품 재고). 데이터를 읽고 쓰는 동안 락(Lock)을 걸어 데이터 정합성을 보장하지만, 성능상 약간의 손실이 있다. 대부분의 경우 `READ_WRITE`가 합리적인 선택이 될 것 같다.
-   **`TRANSACTIONAL`**: JTA(Java Transaction API) 환경에서만 사용할 수 있으며, 가장 강력한 정합성을 보장한다. 일반적인 웹 애플리케이션 환경에서는 거의 쓸 일이 없을 것 같다.

---

## 오늘의 결론

JPA 2차 캐시는 자주 조회되지만 거의 변경되지 않는 데이터에 적용할 때 최고의 성능 효과를 낼 수 있다. 하지만 캐시는 결국 데이터 불일치라는 잠재적 위험을 안고 가는 트레이드오프 관계임을 명심해야 한다. 따라서 캐시를 적용하기 전에는 데이터의 특성을 명확히 분석하고, 적절한 동시성 전략을 선택하는 것이 무엇보다 중요하다. 무분별한 캐시 사용은 오히려 찾기 힘든 버그의 원인이 될 수 있다는 것을 깨달았다.
