---
title: "JPA 시대에 MyBatis가 여전히 강력한 이유: 동적 SQL과 XML 매핑"
date: 2025-11-03
categories: [Java, Spring]
tags: [MyBatis, Spring Data, JPA, SQL Mapper, Dynamic SQL, TIL]
excerpt: "JPA와 QueryDSL의 편리함 속에서, SQL에 대한 완전한 제어권을 제공하는 MyBatis가 왜 여전히 3~4년차 개발자에게 강력한 무기인지 학습합니다. 복잡한 통계 쿼리와 배치(Batch) 작업을 위한 동적 SQL의 활용법을 알아봅니다."
author_profile: true
---

# Today I Learned: JPA 시대에 MyBatis가 여전히 강력한 이유: 동적 SQL과 XML 매핑

## 📚 오늘 학습한 내용

저는 3년 넘게 JPA와 Spring Data JPA, QueryDSL을 주력으로 사용하며 객체지향적인 개발의 편리함을 누려왔습니다. 엔티티를 조회하고 수정하면 변경 감지(Dirty Checking)가 알아서 UPDATE 쿼리를 만들어주고, QueryDSL이 타입-세이프(Type-Safe)하게 동적 쿼리를 생성해주는 것은 분명한 장점입니다.

하지만 실무에서 **복잡한 통계 리포트**를 조회하거나, **대용량 데이터를 일괄 수정(Batch Update)**해야 하는 상황에 부딪히면서, JPA가 생성하는 SQL이 비효율적이거나 아예 JPA만으로는 표현하기 어려운 쿼리가 존재한다는 것을 깨달았습니다.

오늘은 이러한 JPA의 한계점을 보완해주는 강력한 **SQL Mapper** 프레임워크인 **MyBatis**의 핵심 가치와 **동적 SQL**의 활용법에 대해 학습했습니다.

---

### 1. **ORM이 아닌 SQL Mapper, MyBatis**

JPA가 '객체(Object)'와 '관계형 DB(Relational)'를 매핑하는 **ORM(Object-Relational Mapping)**이라면, MyBatis는 '객체(Java Object)'와 **'SQL 문(SQL Statement)'**을 매핑하는 **SQL Mapper**입니다.

-   **JPA (ORM)**: 개발자가 객체지향적으로 코드를 짜면(e.g., `user.getOrders()`), JPA가 SQL을 **'생성'**해줍니다. 개발자는 SQL을 직접 다루지 않습니다.
-   **MyBatis (SQL Mapper)**: 개발자가 **직접 SQL을 작성**하고(XML 또는 애노테이션), MyBatis는 이 SQL의 실행 결과와 Java 객체 간의 **'매핑'**만 담당합니다.

JPA가 제공하는 영속성 컨텍스트, 1차 캐시, 변경 감지 등의 복잡한 기능이 없는 대신, **SQL에 대한 100% 제어권**을 개발자에게 돌려줍니다.

---

### 2. **MyBatis의 핵심: 동적 SQL (Dynamic SQL)**

MyBatis가 빛을 발하는 순간은 바로 **복잡한 조건의 동적 쿼리**를 작성할 때입니다. QueryDSL로도 가능하지만, 조건이 수십 개가 되면 Java 코드가 매우 지저분해질 수 있습니다. MyBatis는 XML 태그를 통해 이를 간결하게 표현합니다.

-   **상황**: 사용자 검색 시, 이름(username), 이메일(email), 그리고 여러 개의 상태(statuses) 중 하나라도 일치하는 경우를 검색해야 함.

**Mapper 인터페이스 (Java)**
```java
@Mapper
public interface UserMapper {
    List<User> findUsersByDynamicCondition(UserSearchCondition condition);
}

// UserSearchCondition.java (DTO)
public class UserSearchCondition {
    private String username;
    private String email;
    private List<String> statuses; // e.g., ["ACTIVE", "PENDING"]
}
```

**Mapper XML (`UserMapper.xml`)**
```xml
<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-mapper.dtd">
<mapper namespace="com.example.mapper.UserMapper">

    <select id="findUsersByDynamicCondition" resultType="com.example.model.User">
        SELECT id, username, email, status
        FROM users
        <where>
            <if test="username != null and username != ''">
                AND username LIKE CONCAT(#{username}, '%')
            </if>
            
            <if test="email != null and email != ''">
                AND email = #{email}
            </if>
            
            <if test="statuses != null and !statuses.isEmpty()">
                AND status IN
                <foreach item="statusItem" collection="statuses"
                         open="(" separator="," close=")">
                    #{statusItem}
                </foreach>
            </if>
        </where>
    </select>

</mapper>
```
> `<where>` 태그는 내부 조건 중 하나라도 유효할 때만 `WHERE` 키워드를 붙여주고, 불필요한 `AND`나 `OR`을 자동으로 제거해줍니다. `<if>`와 `<foreach>`를 사용해 복잡한 쿼리 조합을 SQL에 가깝게 완성할 수 있습니다.

---

### 3. **JPA와 MyBatis를 함께 사용하기 (Best Practice)**

3~4년차 개발자에게 MyBatis가 강력한 무기인 이유는, JPA를 버리는 것이 아니라 **JPA와 함께 사용할 때** 시너지가 나기 때문입니다.

-   **일반적인 CRUD**: **Spring Data JPA**를 사용하여 빠르고 객체지향적으로 개발합니다. (e.g., `UserRepository`)
-   **복잡한 조회/통계/배치**: **MyBatis**를 사용하여 SQL을 직접 튜닝하고 최적화합니다. (e.g., `UserReportMapper`)

Spring Boot는 두 기술을 하나의 트랜잭션으로 묶는 것을 완벽하게 지원합니다.

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository; // JPA
    private final UserMapper userMapper;     // MyBatis

    // CRUD는 JPA로 간편하게
    @Transactional
    public User createUser(String username, String email) {
        User user = new User(username, email);
        return userRepository.save(user); // JPA 사용
    }

    // 복잡한 리포트 쿼리는 MyBatis로 최적화
    @Transactional(readOnly = true)
    public List<User> search(UserSearchCondition condition) {
        return userMapper.findUsersByDynamicCondition(condition); // MyBatis 사용
    }
}
```

---

## 💡 배운 점

1.  **JPA는 만능이 아니다**: JPA는 CRUD와 객체 그래프 탐색에는 압도적으로 편리하지만, 통계/리포팅 쿼리나 대규모 데이터의 일괄 업데이트/삭제(Batch) 시에는 비효율적일 수 있습니다. (e.g., N건 수정을 위해 N번의 `SELECT` + N번의 `UPDATE` 발생 가능)
2.  **SQL 제어권의 가치**: 3~4년차로서 성능 튜닝에 대한 압박이 커질 때, SQL을 직접 제어할 수 있다는 것은 엄청난 장점입니다. MyBatis는 `EXPLAIN`으로 확인한 실행 계획을 바탕으로 인덱스 힌트를 주거나, 서브쿼리를 추가하는 등 **SQL 튜닝을 코드 변경 없이** XML 파일 수정만으로 가능하게 해줍니다.
3.  **최고의 전략은 '하이브리드'**: JPA의 편리함과 MyBatis의 SQL 제어력, 두 가지 장점을 모두 취하는 것이 현명한 전략임을 깨달았습니다. 도메인의 특성에 맞춰, 복잡도와 성능 요구사항에 따라 적절한 기술을 조합하여 사용하는 것이 3~4년차 개발자의 역량입니다.

---

## 🔗 참고 자료

-   [MyBatis-Spring-Boot-Starter (MyBatis 공식 문서)](https://mybatis.org/spring-boot-starter/mybatis-spring-boot-autoconfigure/)
-   [MyBatis 3 | Dynamic SQL](https://mybatis.org/mybatis-3/dynamic-sql.html)
-   [JPA vs. MyBatis: Which to Choose? (Baeldung)](https://www.baeldung.com/jpa-vs-mybatis)