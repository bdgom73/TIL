---
title: "MySQL에서 파티셔닝하는 방법"
date: 2025-09-15
categories: [MySQL, Database, Partitioning]
tags: [MySQL, Partitioning, RANGE, LIST, HASH, KEY]
excerpt: "MySQL에서 테이블 파티셔닝하는 다양한 방법과 장단점에 대해 알아봅니다."
author_profile: true
---

### TIL: MySQL에서 파티셔닝하는 방법

MySQL에서 대용량 테이블을 효율적으로 관리하기 위해 파티셔닝을 사용할 수 있습니다. 파티셔닝은 큰 테이블을 작은 파티션으로 나누어 관리하는 기술로, 쿼리 성능 향상, 데이터 관리 용이성, 백업 및 복구 효율성 증대 등의 이점을 제공합니다. 이번 TIL에서는 MySQL에서 테이블을 파티셔닝하는 다양한 방법과 각 방법의 장단점에 대해 알아보겠습니다.

#### 1. RANGE 파티셔닝

RANGE 파티셔닝은 특정 컬럼 값의 범위를 기준으로 파티션을 나눕니다.  날짜, 숫자 등 순차적인 값을 가진 컬럼에 적합합니다.

```sql
CREATE TABLE sales (
    id INT NOT NULL,
    sale_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL
)
PARTITION BY RANGE (YEAR(sale_date)) (
    PARTITION p0 VALUES LESS THAN (2024),
    PARTITION p1 VALUES LESS THAN (2025),
    PARTITION p2 VALUES LESS THAN MAXVALUE
);
```

#### 2. LIST 파티셔닝

LIST 파티셔닝은 특정 컬럼 값의 목록을 기준으로 파티션을 나눕니다.  ENUM 타입처럼 특정 값들만 가질 수 있는 컬럼에 적합합니다.

```sql
CREATE TABLE customers (
    id INT NOT NULL,
    country VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL
)
PARTITION BY LIST (country) (
    PARTITION p_usa VALUES IN ('USA'),
    PARTITION p_canada VALUES IN ('Canada'),
    PARTITION p_uk VALUES IN ('UK'),
    PARTITION p_other VALUES IN ('Other')
);

```

#### 3. HASH 파티셔닝

HASH 파티셔닝은 특정 컬럼 값의 해시 값을 기준으로 파티션을 나눕니다.  데이터 분포가 고른 경우에 적합합니다.

```sql
CREATE TABLE employees (
    id INT NOT NULL,
    department_id INT NOT NULL,
    name VARCHAR(100) NOT NULL
)
PARTITION BY HASH(department_id)
PARTITIONS 4; -- 4개의 파티션으로 나눔
```

#### 4. KEY 파티셔닝

KEY 파티셔닝은 HASH 파티셔닝과 유사하지만, MySQL 서버에서 제공하는 해시 함수 대신 사용자가 지정한 컬럼이나 컬럼 조합에 대해 해시 함수를 적용합니다. 여러 컬럼을 기준으로 파티셔닝할 때 유용합니다.

```sql
CREATE TABLE products (
    id INT NOT NULL,
    category_id INT NOT NULL,
    product_name VARCHAR(100) NOT NULL
)
PARTITION BY KEY(category_id, product_name)
PARTITIONS 8; -- 8개의 파티션으로 나눔
```

#### 파티셔닝 장점

* 쿼리 성능 향상: 특정 파티션만 검색하여 쿼리 성능을 높일 수 있습니다.
* 데이터 관리 용이성: 파티션 단위로 데이터를 관리하고 유지보수할 수 있습니다.
* 백업 및 복구 효율성 증대: 파티션 단위로 백업 및 복구 작업을 수행하여 시간과 자원을 절약할 수 있습니다.

#### 파티셔닝 단점

* 파티셔닝 키 선택 중요: 잘못된 파티셔닝 키 선택은 오히려 성능 저하를 초래할 수 있습니다.
* 파티션 수 제한: MySQL 버전에 따라 파티션 수 제한이 있을 수 있습니다.
* 복잡한 쿼리 설계 어려움: 파티션을 고려하여 쿼리를 설계해야 하므로 복잡한 쿼리 작성이 어려울 수 있습니다.


#### 결론

MySQL 파티셔닝은 대용량 테이블 관리에 효과적인 방법입니다.  데이터 특성과 요구사항에 맞는 적절한 파티셔닝 방법을 선택하여 데이터베이스 성능을 향상시키고 관리 효율성을 높일 수 있습니다.  파티셔닝 전략 수립 시에는 데이터 분포, 쿼리 패턴, 데이터 관리 방식 등을 고려해야 합니다.