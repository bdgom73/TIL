---
title: "Spring Cache + Redis: 조회 성능 개선과 @Cacheable의 'Self-Invocation' 함정 피하기"
date: 2025-12-15
categories: [Spring, Performance]
tags: [Spring Cache, Redis, @Cacheable, AOP, Proxy, Performance, TIL]
excerpt: "반복적인 DB 조회를 줄여 응답 속도를 개선하는 Spring Cache(Redis)의 적용 방법을 학습합니다. 특히 3~4년차 개발자도 자주 실수하는 AOP 프록시의 한계인 '내부 호출(Self-Invocation)' 문제와 해결책을 알아봅니다."
author_profile: true
---

# Today I Learned: Spring Cache + Redis: 조회 성능 개선과 @Cacheable의 'Self-Invocation' 함정 피하기

## 📚 오늘 학습한 내용

서비스를 운영하다 보면 "변하지 않는 데이터(카테고리 목록, 공지사항 등)"를 매번 DB에서 조회하는 비효율을 발견하게 됩니다. 이를 해결하기 위해 로컬 캐시(Caffeine)나 글로벌 캐시(Redis)를 도입하는데, Spring은 **PSA(Portable Service Abstraction)**를 통해 애노테이션 하나로 캐시를 구현할 수 있게 해줍니다.

오늘은 Redis를 캐시 저장소로 설정하는 방법과, 적용 과정에서 반드시 마주치게 되는 **프록시 내부 호출(Self-Invocation)** 문제의 원인 및 해결책을 정리했습니다.

---

### 1. **Spring Cache + Redis 설정 🚀**

#### **Step 1: 의존성 추가**
`spring-boot-starter-cache`와 `spring-boot-starter-data-redis`가 필요합니다.

```groovy
implementation 'org.springframework.boot:spring-boot-starter-cache'
implementation 'org.springframework.boot:spring-boot-starter-data-redis'
```

#### **Step 2: RedisCacheManager 설정**
캐시마다 만료 시간(TTL)을 다르게 설정하는 것이 실무적인 포인트입니다.

```java
@Configuration
@EnableCaching // 캐시 기능 활성화
public class CacheConfig {

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory connectionFactory) {
        // 기본 설정: TTL 1시간, Null 값 캐싱 안 함
        RedisCacheConfiguration defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
                .entryTtl(Duration.ofHours(1))
                .disableCachingNullValues()
                .serializeKeysWith(RedisSerializationContext.SerializationPair.fromSerializer(new StringRedisSerializer()))
                .serializeValuesWith(RedisSerializationContext.SerializationPair.fromSerializer(new GenericJackson2JsonRedisSerializer()));

        // 별도 설정: "shortLived"라는 이름의 캐시는 1분만 유지
        Map<String, RedisCacheConfiguration> configurations = new HashMap<>();
        configurations.put("shortLived", defaultConfig.entryTtl(Duration.ofMinutes(1)));

        return RedisCacheManager.builder(connectionFactory)
                .cacheDefaults(defaultConfig)
                .withInitialCacheConfigurations(configurations)
                .build();
    }
}
```

#### **Step 3: 적용 (`@Cacheable`)**

```java
@Service
@RequiredArgsConstructor
public class CategoryService {

    private final CategoryRepository categoryRepository;

    // cacheNames: 캐시 저장소 이름 (Key Prefix)
    // key: 캐시 키 생성 규칙 (SpEL) -> "categories::top"
    @Cacheable(cacheNames = "categories", key = "'top'")
    public List<CategoryDto> getTopCategories() {
        // DB 조회 로직 (최초 1회만 실행됨)
        return categoryRepository.findTopCategories().stream()
                .map(CategoryDto::from)
                .toList();
    }
    
    @CacheEvict(cacheNames = "categories", key = "'top'") // 데이터 변경 시 캐시 삭제
    public void updateCategory(Long id, CategoryRequest request) {
        // ... 업데이트 로직
    }
}
```

---

### 2. **치명적인 함정: Self-Invocation (내부 호출) ⚠️**

`@Cacheable`은 **Spring AOP(Proxy)** 기반으로 동작합니다. 즉, 외부에서 프록시 객체를 통해 메서드를 호출할 때만 인터셉터가 동작하여 캐시 로직을 수행합니다.

**문제 상황**: **같은 클래스 내부**의 메서드가 `@Cacheable`이 붙은 메서드를 호출하면 캐시가 적용되지 않습니다.

```java
@Service
public class ProductService {

    public ProductDto getProduct(Long id) {
        // [문제 발생] 
        // this.findProductById(id)는 프록시를 거치지 않고 원본 객체의 메서드를 직접 호출함.
        // 따라서 @Cacheable이 무시되고 매번 DB 쿼리가 나감.
        return this.findProductById(id);
    }

    @Cacheable(cacheNames = "products", key = "#id")
    public ProductDto findProductById(Long id) {
        return productRepository.findById(id).map(ProductDto::from).orElseThrow();
    }
}
```

---

### 3. **해결 방법**

#### **방법 1: 구조 분리 (권장)**
가장 깔끔한 방법은 캐시 메서드를 **별도의 서비스 클래스(Component)**로 분리하는 것입니다.

```java
@Service
@RequiredArgsConstructor
public class ProductFacade { // 혹은 Service
    private final ProductReader productReader; // 별도 클래스

    public ProductDto getProduct(Long id) {
        // 외부 객체의 메서드를 호출하므로 프록시가 정상 동작함
        return productReader.findProductById(id);
    }
}

@Component
public class ProductReader {
    @Cacheable(...)
    public ProductDto findProductById(Long id) { ... }
}
```

#### **방법 2: 자기 자신 주입 (Self-Injection)**
구조 분리가 어렵다면, 자기 자신을 프록시로 주입받아 호출할 수 있습니다. (순환 참조 문제로 `@Lazy`나 `Setter` 주입 필요)

```java
@Service
public class ProductService {

    @Autowired
    @Lazy // 순환 참조 방지
    private ProductService self;

    public ProductDto getProduct(Long id) {
        // this 대신 주입받은 프록시(self)를 통해 호출
        return self.findProductById(id);
    }

    @Cacheable(...)
    public ProductDto findProductById(Long id) { ... }
}
```

---

## 💡 배운 점

1.  **캐시 전략은 TTL이 생명**: 단순히 캐시를 거는 것보다 **'언제 만료시킬 것인가'**가 더 중요합니다. 데이터의 성격(실시간성 vs 정합성)에 따라 TTL을 세분화하여 `RedisCacheManager`를 구성해야 함을 배웠습니다.
2.  **AOP의 동작 원리 재확인**: `@Transactional`, `@Async`, `@Cacheable` 등 Spring의 핵심 기능들이 모두 프록시 기반이라는 점을 잊지 말아야 합니다. "분명히 애노테이션을 붙였는데 왜 안 되지?"라는 의문이 들 때 1순위로 **내부 호출**을 의심해야 합니다.
3.  **Redis의 직렬화**: 기본 JdkSerializationRedisSerializer는 사람이 읽을 수 없는 바이너리로 저장됩니다. 운영 편의성을 위해 `GenericJackson2JsonRedisSerializer`를 사용하여 JSON 포맷으로 저장하는 것이 디버깅에 훨씬 유리합니다.

---

## 🔗 참고 자료

-   [Spring Boot Cache Guide](https://spring.io/guides/gs/caching/)
-   [Understanding Spring AOP Proxying](https://docs.spring.io/spring-framework/reference/core/aop/proxying.html)
-   [Redis Serialization in Spring](https://www.baeldung.com/spring-data-redis-tutorial#serialization)