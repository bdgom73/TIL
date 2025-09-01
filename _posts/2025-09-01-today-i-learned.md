---
title: "Today I Learned: JPA 영속성 컨텍스트(Persistence Context) 핵심 원리"
date: 2025-09-01
categories: [JPA]
tags: [JPA, PersistenceContext, TIL]
excerpt: "JPA의 핵심 메커니즘인 영속성 컨텍스트의 1차 캐시, 쓰기 지연, 변경 감지, 그리고 준영속 상태와 merge()의 동작 원리를 정리합니다."
author_profile: true
---

# Today I Learned: JPA 영속성 컨텍스트 핵심 원리 📝

JPA를 사용하면서 가장 중요하지만 헷갈렸던 **영속성 컨텍스트(Persistence Context)**에 대해 제대로 파고들었다. 단순히 엔티티를 데이터베이스에 저장하는 것을 넘어, 애플리케이션과 데이터베이스 사이에서 **똑똑한 중간 저장소** 역할을 하며 성능 최적화와 코드 간결성을 모두 잡아주는 핵심 메커니즘이라는 것을 깨달았다.

---

### 1. 영속성 컨텍스트의 3가지 핵심 기능

영속성 컨텍스트는 크게 세 가지 강력한 기능을 통해 개발을 편리하게 만들어준다.

#### **1) 1차 캐시: 불필요한 DB 조회를 막는 똑똑한 캐시 ⚡️**

영속성 컨텍스트는 내부에 '1차 캐시'라는 작은 저장소를 가지고 있다. `entityManager.find()`로 엔티티를 처음 조회하면, DB에서 가져온 엔티티를 이 1차 캐시에 저장한다. **같은 트랜잭션 안에서 동일한 엔티티를 다시 조회할 때는 DB를 또 가는 게 아니라, 1차 캐시에서 바로 꺼내준다.**

- **핵심:** 한 트랜잭션 내에서 **반복 가능한 읽기(Repeatable Read)**를 보장하고, 불필요한 SELECT 쿼리를 줄여 성능을 높인다.

```java
// 1. 첫 조회: DB에서 데이터를 가져와 1차 캐시에 저장 (SELECT 쿼리 발생)
Member member1 = entityManager.find(Member.class, 1L);

// 2. 두 번째 조회: DB가 아닌 1차 캐시에서 바로 가져옴 (SELECT 쿼리 없음!)
Member member2 = entityManager.find(Member.class, 1L);

// member1과 member2는 동일한 인스턴스임
System.out.println(member1 == member2); // true
```

#### **2) 쓰기 지연(Transactional Write-Behind): 쿼리를 모아서 한 번에! 🚀**

`entityManager.persist()`를 호출한다고 해서 바로 DB에 INSERT 쿼리가 날아가지 않는다. 영속성 컨텍스트는 실행해야 할 쿼리들을 '쓰기 지연 SQL 저장소'에 차곡차곡 모아둔다. 그리고 **트랜잭션이 커밋(`commit()`)되는 순간, 모아뒀던 쿼리들을 한꺼번에 DB로 보낸다.**

- **핵심:** 여러 쿼리를 묶어서 DB와 통신하는 횟수를 최소화하므로, 네트워크 비용을 줄이고 성능을 최적화할 수 있다. (JDBC의 배치 기능 활용)

```java
transaction.begin(); // 트랜잭션 시작

entityManager.persist(memberA); // INSERT 쿼리를 SQL 저장소에 저장
entityManager.persist(memberB); // INSERT 쿼리를 SQL 저장소에 저장
// 아직 DB에는 아무런 변화가 없음

transaction.commit(); // commit() 시점에 모아둔 쿼리 2개가 한번에 실행됨
```

#### **3) 변경 감지(Dirty Checking): `update()`가 필요 없는 마법 ✨**

JPA가 가장 마법처럼 느껴지는 부분이다. 영속성 컨텍스트는 1차 캐시에 엔티티를 저장할 때, 최초 상태의 **스냅샷**을 함께 저장한다. 이후 트랜잭션이 커밋될 때, **현재 엔티티의 상태와 저장해둔 스냅샷을 비교**한다. 만약 둘 사이에 변경된 점이 있다면, JPA가 알아서 UPDATE 쿼리를 생성해서 DB에 날려준다.

- **핵심:** 개발자는 `update()` 같은 메서드를 호출할 필요 없이, 단순히 객체의 상태만 변경하면 된다. 코드가 매우 간결해지고 비즈니스 로직에만 집중할 수 있게 된다.

```java
transaction.begin();

// 1. 엔티티 조회 (이때 스냅샷이 생성됨)
Member member = entityManager.find(Member.class, 1L);

// 2. 엔티티의 상태만 변경
member.setName("newName");

// 3. commit() 시점에 스냅샷과 비교하여 변경을 감지하고, UPDATE 쿼리를 자동 실행
transaction.commit();
```

---

### 2. 준영속 상태와 `merge()`의 올바른 이해

영속성 컨텍스트가 관리하던 엔티티가 컨텍스트 밖으로 벗어나면 **준영속(Detached)** 상태가 된다. 예를 들어 `entityManager.detach(entity)`를 호출하거나, 트랜잭션이 끝나서 영속성 컨텍스트가 닫히면 해당 엔티티는 준영속 상태가 된다.

준영속 상태의 엔티티는 더 이상 변경 감지 같은 JPA의 지원을 받지 못한다. 웹 환경에서 사용자가 수정한 데이터를 객체로 받아와 DB에 반영하려고 할 때 이 문제가 발생한다.

이때 사용하는 것이 바로 `merge()` 메서드다. 하지만 `merge()`의 동작 방식을 잘못 이해하면 큰 실수를 할 수 있다.

**`merge()`의 정확한 동작 방식:**

1.  `merge()`는 준영속 상태의 엔티티를 인자로 받는다.
2.  인자로 받은 엔티티의 ID를 사용해서 **영속성 컨텍스트의 1차 캐시를 조회**하거나, 없으면 **DB에서 영속 상태의 엔티티를 가져온다.**
3.  가져온 **영속 엔티티**에 준영속 엔티티의 값을 모두 덮어쓴다(병합한다).
4.  값을 병합한 **영속 상태의 엔티티를 반환**한다.

**🔥 가장 중요한 포인트:** `merge()`는 파라미터로 받은 준영속 엔티티를 영속 상태로 바꾸는 것이 아니다. **새로운 영속 엔티티를 반환**하는 것이다. 따라서 `merge()`를 호출한 이후에는 반드시 **반환된 새로운 객체를 사용**해야 변경 감지가 정상적으로 동작한다.

```java
// member는 컨트롤러 등에서 넘어온 준영속 상태의 객체
Member member = new Member();
member.setId(1L);
member.setName("updatedName");

transaction.begin();

// merge() 실행! 반환된 mergedMember가 진짜 영속 객체다.
Member mergedMember = entityManager.merge(member);

// member가 아닌, 반환받은 mergedMember의 상태를 변경해야 한다.
mergedMember.setAge(20); // 이 변경사항만 DB에 반영됨!

transaction.commit();
```

오늘 영속성 컨텍스트의 세 가지 핵심 기능과 `merge()`의 동작 원리를 확실히 정리했다. 특히 `merge()`가 새로운 영속 객체를 반환한다는 점을 명심하고 코드를 작성해야겠다. JPA를 더 깊이 있고 자신감 있게 다룰 수 있게 된 것 같다.
