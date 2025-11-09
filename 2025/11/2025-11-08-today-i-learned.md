---
title: "JPA 상속 관계 매핑 전략: Joined, Single Table, Table per Class"
date: 2025-11-08
categories: [Java, Spring]
tags: [JPA, Inheritance, ORM, Database Design, Single Table, Joined, TIL]
excerpt: "객체지향의 '상속'을 관계형 데이터베이스에서 구현하는 JPA의 세 가지 전략(Joined, Single Table, Table per Class)의 동작 방식과, 각각의 성능 및 정규화 트레이드오프를 비교 분석합니다."
author_profile: true
---

# Today I Learned: JPA 상속 관계 매핑 전략: Joined, Single Table, Table per Class

## 📚 오늘 학습한 내용

저는 3~4년차 개발자로서, 공통 필드(e.g., `createdAt`, `modifiedAt`)를 관리하기 위해 `@MappedSuperclass`를 사용하는 데는 익숙했습니다. 하지만 객체지향의 핵심 특징인 **'상속'** 관계 자체를 JPA로 매핑하는 것은 또 다른 차원의 문제였습니다.

예를 들어, 상품(`Item`)이라는 부모 엔티티가 있고, 이를 상속받는 책(`Book`), 앨범(`Album`), 영화(`Movie`) 자식 엔티티가 있다고 가정해봅시다. 관계형 DB에는 '상속'이라는 개념이 없기 때문에, JPA는 이 관계를 DB 테이블로 변환하기 위한 3가지 전략을 제공합니다. 오늘은 이 세 가지 전략의 동작 방식과 명확한 장단점을 학습했습니다.

---

### 1. **Joined Strategy (조인 전략) 🤝**

-   **애노테이션**: `@Inheritance(strategy = InheritanceType.JOINED)`
-   **동작 방식**: 부모와 자식 테이블을 모두 생성합니다. 부모 테이블(`Item`)에는 공통 필드를, 자식 테이블(`Book`, `Album`)에는 각각의 고유 필드만 저장합니다. 자식 테이블은 부모 테이블의 ID를 외래 키(FK)이자 기본 키(PK)로 사용합니다.
-   **DB 스키마**:
    -   `Item` (id, name, price, **DTYPE**)
    -   `Book` (item_id(FK/PK), author, isbn)
    -   `Album` (item_id(FK/PK), artist)
    -   `DTYPE` 컬럼: 어떤 자식 테이블과 조인해야 하는지 알려주는 구분자 컬럼이 부모 테이블에 생성됩니다.

```java
@Entity
@Inheritance(strategy = InheritanceType.JOINED)
@DiscriminatorColumn(name = "DTYPE") // 구분자 컬럼 (필수)
public abstract class Item {
    @Id @GeneratedValue
    private Long id;
    private String name;
    private int price;
}

@Entity
public class Book extends Item {
    private String author;
    private String isbn;
}

@Entity
public class Album extends Item {
    private String artist;
}
```

-   **장점**:
    -   **정규화**: 데이터가 정규화되어 저장됩니다. DB 스키마가 깔끔하고 직관적입니다.
    -   **공간 효율성**: 자식 테이블에는 `null` 값이 거의 없습니다.
-   **단점**:
    -   **조회 성능**: `Book`을 조회할 때 **항상** `Item` 테이블과 **JOIN**이 발생하여 성능이 저하될 수 있습니다.
    -   **쓰기 성능**: `Book`을 저장할 때 부모(`Item`)와 자식(`Book`) 테이블 **두 곳에 INSERT**가 발생합니다.

---

### 2. **Single Table Strategy (단일 테이블 전략) 📦**

-   **애노테이션**: `@Inheritance(strategy = InheritanceType.SINGLE_TABLE)`
-   **(JPA 기본 전략)**: 아무것도 지정하지 않으면 이 전략으로 동작합니다.
-   **동작 방식**: 이름 그대로, 부모와 모든 자식의 필드를 포함하는 **단 하나의 '슈퍼 테이블'**을 생성합니다.
-   **DB 스키마**:
    -   `Item` (id, name, price, **DTYPE**, author, isbn, artist)
    -   `DTYPE` 컬럼: 해당 로우가 `Book`인지 `Album`인지 구분하는 **필수** 컬럼입니다.

```java
@Entity
@Inheritance(strategy = InheritanceType.SINGLE_TABLE) // 기본값이지만 명시
@DiscriminatorColumn(name = "DTYPE") // 구분자 컬럼 (필수)
public abstract class Item { /*...*/ }

@Entity
public class Book extends Item { private String author; private String isbn; }

@Entity
public class Album extends Item { private String artist; }
```

-   **장점**:
    -   **조회 성능**: **성능이 가장 좋습니다.** JOIN이 전혀 필요 없으며, 단일 테이블 `SELECT`만으로 조회가 완료됩니다.
-   **단점**:
    -   **데이터 무결성**: 자식 테이블의 고유 필드들(e.g., `author`, `artist`)은 **모두 `nullable=true`**여야 합니다. (`Book` 타입의 로우는 `artist` 컬럼이 `null`이 됨)
    -   **공간 비효율성**: 데이터가 많아질수록 `null` 값이 공간을 많이 차지하고, 테이블이 지나치게 비대해질 수 있습니다.

---

### 3. **Table per Class Strategy (클래스별 테이블 전략) 📑**

-   **애노테이션**: `@Inheritance(strategy = InheritanceType.TABLE_PER_CLASS)`
-   **동작 방식**: **구현 클래스마다** 독립적인 테이블을 생성합니다. 부모의 공통 필드까지 모두 포함하여 각각의 테이블이 만들어집니다. (추상 클래스인 `Item` 테이블은 생성되지 않습니다.)
-   **DB 스키마**:
    -   `Book` (id, name, price, author, isbn)
    -   `Album` (id, name, price, artist)

```java
@Entity
@Inheritance(strategy = InheritanceType.TABLE_PER_CLASS)
// (주의) 이 전략은 @DiscriminatorColumn이 필요 없음
public abstract class Item { /*...*/ }

@Entity
public class Book extends Item { /*...*/ }

@Entity
public class Album extends Item { /*...*/ }
```

-   **장점**:
    -   자식 클래스 입장에서 직관적이며 `null` 컬럼이 없습니다.
-   **단점**:
    -   **치명적인 조회 성능 문제**: 만약 부모 타입으로 조회(e.g., `itemRepository.findAll()`)하면, JPA는 모든 자식 테이블을 **`UNION ALL`** 쿼리로 묶어서 조회해야 합니다. 이는 테이블이 많아질수록 재앙적인 성능 저하를 유발합니다.
    -   **DB 비효율성**: 공통 필드(name, price)가 모든 자식 테이블에 중복으로 존재합니다.
-   **결론**: 이 전략은 **어떤 상황에서도 권장되지 않습니다.**

---

## 💡 배운 점: 3~4년차의 선택은?

1.  **`TABLE_PER_CLASS`는 사용하지 말자**: 명확한 단점(특히 `UNION ALL` 문제) 때문에 이 전략은 고려 대상에서 제외하는 것이 맞습니다.
2.  **`SINGLE_TABLE` (기본값) vs. `JOINED` (정규화)**
    -   JPA의 기본 전략이 `SINGLE_TABLE`인 이유는 **조회 성능**을 최우선으로 고려했기 때문입니다.
    -   하지만 3~4년차 개발자로서, `null`을 허용하는 스키마가 과연 좋은 설계인지 고민해야 합니다.
    -   **결론**:
        -   자식 클래스가 많지 않고, 필드도 적으며, 조회 성능이 압도적으로 중요하다면 `SINGLE_TABLE`.
        -   데이터의 정규화와 명확한 스키마가 중요하고, 자식 클래스가 많거나 고유 필드가 많다면 `JOINED` 전략을 선택하고, 성능 문제는 캐시(Cache) 등으로 보완하는 것이 더 성숙한 설계임을 깨달았습니다.

---

## 🔗 참고 자료

-   [JPA Docs - Inheritance Mapping](https://en.wikibooks.org/wiki/Java_Persistence/Inheritance)
-   [JPA Inheritance Strategies (Baeldung)](https://www.baeldung.com/hibernate-inheritance)
-   [자바 ORM 표준 JPA 프로그래밍 (김영한님 저)](https://www.yes24.com/Product/Goods/17133731)