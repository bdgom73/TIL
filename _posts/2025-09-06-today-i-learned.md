---
title: "Spring Boot와 Redis를 활용한 캐싱"
date: 2025-09-06
categories: [Spring, Backend]
tags: [Spring Boot, Redis, Caching, Performance]
excerpt: "Spring Boot에서 Redis를 활용해 캐싱을 구현하고 조회 성능을 개선한 경험을 공유합니다."
author_profile: true
---

# Today I Learned: Spring Boot와 Redis를 활용한 캐싱

오늘은 Spring Boot 애플리케이션에서 Redis를 활용해 캐싱을 구현하고, 이를 통해 조회 성능을 개선한 경험을 정리했습니다.

---

## Redis를 활용한 캐싱의 필요성

대규모 트래픽을 처리하는 애플리케이션에서는 데이터베이스 조회가 병목현상을 일으키는 경우가 많습니다. 이를 해결하기 위해 Redis를 활용한 캐싱을 도입하면, 자주 조회되는 데이터를 메모리에 저장하여 데이터베이스 접근을 줄이고 성능을 크게 개선할 수 있습니다.

---

## 구현 과정

### 1. Redis 의존성 추가
Spring Boot 프로젝트에 Redis를 사용하기 위해 `spring-boot-starter-data-redis` 의존성을 추가했습니다.

```xml
<!-- filepath: pom.xml -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis</artifactId>
</dependency>
```
