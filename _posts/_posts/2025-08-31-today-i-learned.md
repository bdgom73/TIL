---
title: "QueryDSL을 이용한 동적 쿼리 및 검색 기능 구현"
date: 2025-08-31
categories: [QueryDsl, JPA]
tags: [QueryDsl, JPA]
excerpt: "QueryDSL을 이용한 동적 쿼리 및 검색 기능 구현"
author_profile: true
---

# Today I Learned:  QueryDSL을 이용한 동적 쿼리 및 검색 기능 구현

## 1. 들어가며

JPA를 사용하면서 복잡한 검색 기능을 구현해야 할 때가 있다. 특히 사용자의 입력값에 따라 검색 조건이 계속 바뀌는 **동적 쿼리**를 작성해야 하는 상황은 생각보다 자주 마주친다.

예를 들어, 쇼핑몰에서 상품을 검색할 때 사용자는 카테고리, 가격 범위, 상품명, 재고 유무 등 다양한 조건을 조합하여 검색할 수 있다.

이런 경우, JPA가 기본으로 제공하는 JPQL이나 Criteria API만으로는 코드가 매우 복잡해지고 가독성이 떨어지며, 유지보수가 어려워지는 문제에 봉착하게 된다.

이번 TIL에서는 이러한 동적 쿼리 문제를 왜 **QueryDSL**을 사용해서 해결해야 하는지, 그리고 `BooleanBuilder`와 `BooleanExpression`을 활용한 구체적인 구현 방법을 비교하며 정리해보고자 한다.

---

## 2. 왜 JPQL이나 Criteria가 아닌 QueryDSL인가?

### JPQL의 한계
JPQL은 문자열 기반으로 쿼리를 작성하기 때문에 다음과 같은 명확한 한계가 존재한다.

- **컴파일 시점 에러 체크 불가:** 쿼리 내 오타나 문법 오류는 애플리케이션 실행 후 해당 쿼리가 동작하는 시점에야 `RuntimeException`으로 발견할 수 있다.
- **동적 쿼리 작성의 번거로움:** 조건에 따라 `if`문으로 문자열을 더해가는 방식으로 작성해야 하므로 코드가 지저분해지고 실수할 가능성이 커진다.

```java
// JPQL 동적 쿼리의 좋지 않은 예
String jpql = "select i from Item i where";
if (itemName != null) {
    jpql += " i.name like :name";
}
if (price != null) {
    jpql += " and i.price <= :price";
}
```

### Criteria의 한계
JPA 표준 스펙인 Criteria는 JPQL의 단점을 보완하기 위해 나왔지만, 실제 사용해보면 오히려 더 복잡하고 가독성이 떨어진다는 치명적인 단점이 있다.

- **지나치게 복잡하고 비직관적인 코드:** 간단한 쿼리조차도 여러 줄의 코드를 작성해야 하며, 완성된 코드를 봐도 어떤 SQL이 실행될지 한눈에 파악하기 어렵다.

---

### QueryDSL의 등장 ✨
QueryDSL은 이런 문제들을 해결하기 위한 최고의 대안이다.

- **컴파일 시점 에러 체크:** 자바 코드로 쿼리를 작성하므로, 잘못된 컬럼명을 쓰거나 문법이 틀리면 컴파일 단계에서 바로 에러를 잡을 수 있다.  
- **직관적이고 간결한 문법 (IDE 지원):** 마치 자바 코드를 짜는 것처럼 자연스럽게 쿼리를 작성할 수 있으며, 자동 완성 기능의 도움을 받을 수 있다.  
- **동적 쿼리를 위한 강력한 기능 제공:** `BooleanBuilder`나 `BooleanExpression`을 통해 동적 쿼리를 매우 깔끔하고 효율적으로 작성할 수 있다.  

QueryDSL은 Q타입이라는 쿼리 타입을 생성하여 사용하는데, 이는 우리가 정의한 엔티티 클래스를 기반으로 만들어지므로 타입-세이프(Type-Safe)하게 쿼리를 개발할 수 있도록 돕는다.

---

## 3. QueryDSL로 동적 쿼리 구현하기

QueryDSL로 동적 쿼리를 작성하는 대표적인 방법은 `BooleanBuilder`와 `BooleanExpression`을 사용하는 것이다.

---

### 방법 1: BooleanBuilder 사용하기

`BooleanBuilder`는 쿼리의 where 절에 들어갈 조건들을 동적으로 조립해주는 클래스다.

#### ItemSearchCond (검색 조건 DTO)

```java
@Data
public class ItemSearchCond {
    private String itemName;
    private Integer maxPrice;
}
```

#### BooleanBuilder를 사용한 레포지토리 로직

```java
public List<Item> findByCond(ItemSearchCond cond) {
    BooleanBuilder builder = new BooleanBuilder();

    if (hasText(cond.getItemName())) {
        builder.and(item.name.like("%" + cond.getItemName() + "%"));
    }

    if (cond.getMaxPrice() != null) {
        builder.and(item.price.loe(cond.getMaxPrice()));
    }

    return queryFactory
            .selectFrom(item)
            .where(builder)
            .fetch();
}
```

**장점**
- 코드가 직관적이어서 이해하기 쉽다.

**단점**
- 여러 조건을 조합할 때 builder 객체의 상태가 계속 변하므로, 재사용하기 어렵다.  
- 메서드로 분리하지 않으면 코드가 길어질 수 있다.  

---

### 방법 2: BooleanExpression 사용하기 (⭐ 추천)

`BooleanExpression`은 where 절에 들어가는 조건 하나하나를 메서드로 분리하여 작성하는 방식이다. 이 방식은 코드의 재사용성과 **조합(Composition)**이라는 엄청난 장점을 제공한다.

`where` 절은 `Predicate`를 파라미터로 받는데, `BooleanExpression`은 `Predicate`의 구현체이다. `where`에 `null`이 들어가면 해당 조건은 무시되므로 코드를 더욱 간결하게 만들 수 있다.

#### BooleanExpression를 사용한 레포지토리 로직

```java
public List<Item> findByCond(ItemSearchCond cond) {
    return queryFactory
            .selectFrom(item)
            .where(
                nameLike(cond.getItemName()),
                priceLoe(cond.getMaxPrice())
            )
            .fetch();
}

private BooleanExpression nameLike(String itemName) {
    return hasText(itemName) ? item.name.like("%" + itemName + "%") : null;
}

private BooleanExpression priceLoe(Integer maxPrice) {
    return maxPrice != null ? item.price.loe(maxPrice) : null;
}
```

`where` 절은 파라미터로 들어온 `BooleanExpression`들을 자동으로 **and 조건**으로 연결해준다.

**장점**
- 높은 재사용성: `nameLike`, `priceLoe` 같은 조건 메서드는 다른 쿼리에서도 얼마든지 재사용할 수 있다.  
- 자유로운 조합: 이 메서드들을 조합하여 새로운 검색 조건을 쉽게 만들어낼 수 있다.  
- 가독성 향상: where 절을 보면 어떤 조건들이 들어가는지 한눈에 명확하게 파악할 수 있다.  

#### BooleanExpression의 조합 예시

```java
private BooleanExpression isItemServiceable(ItemSearchCond cond) {
    return nameLike(cond.getItemName()).and(priceLoe(cond.getMaxPrice()));
}
```

---

## 4. 결론 및 느낀점

프로젝트에서 동적 검색 기능을 구현할 때, 처음에는 JPQL의 문자열 조합 방식으로 접근했다가 코드의 복잡성이 걷잡을 수 없이 커지는 경험을 했다.

QueryDSL, 특히 `BooleanExpression`을 활용하는 방식으로 리팩토링한 후에는 다음과 같은 장점을 체감할 수 있었다.

- **개발 생산성 향상:** 컴파일 시점에 오류를 잡을 수 있어 런타임 에러로 인한 디버깅 시간이 크게 줄었다.  
- **유지보수 용이성:** 검색 조건이 추가되거나 변경될 때, 다른 코드에 영향을 주지 않고 새로운 `BooleanExpression` 메서드를 추가하거나 기존 메서드를 수정하면 되므로 매우 유연하게 대처할 수 있었다.  
- **코드의 가독성 및 품질 향상:** where절만 봐도 어떤 쿼리인지 명확하게 이해할 수 있게 되어 동료 개발자와의 협업이 훨씬 수월해졌다.  

결론적으로, JPA를 사용하면서 동적 쿼리를 다뤄야 한다면 QueryDSL은 선택이 아닌 필수라고 생각한다.  
그 중에서도 `BooleanExpression`을 통해 조건을 메서드 단위로 분리하고 조합하는 방식은 코드의 재사용성과 가독성을 극대화하는 최고의 방법이다.  

앞으로는 복잡한 쿼리는 주저 없이 QueryDSL을 도입하여 해결해야겠다.

