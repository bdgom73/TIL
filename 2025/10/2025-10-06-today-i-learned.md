---
title: "Elasticsearch로 전문(Full-text) 검색 시스템 구축하기"
date: 2025-10-06
categories: [Database, Search]
tags: [Elasticsearch, Full-text Search, Inverted Index, Spring Data, TIL]
excerpt: "RDBMS의 LIKE 검색이 가진 한계를 알아보고, 전문(Full-text) 검색 엔진인 Elasticsearch의 핵심 원리인 역색인(Inverted Index)과 형태소 분석을 학습합니다. Spring Data Elasticsearch를 이용해 데이터를 인덱싱하고 검색하는 기본적인 방법을 탐구합니다."
author_profile: true
---

# Today I Learned: Elasticsearch로 전문(Full-text) 검색 시스템 구축하기

## 📚 오늘 학습한 내용

온라인 쇼핑몰에서 상품을 찾거나, 블로그에서 특정 키워드가 포함된 글을 검색하는 기능은 이제 모든 서비스의 기본입니다. 이러한 검색 기능을 관계형 데이터베이스(RDBMS)의 `LIKE '%keyword%'` 쿼리로 구현할 수도 있지만, 데이터가 많아질수록 성능이 급격히 저하되고 정확한 검색 결과를 제공하기 어렵습니다. 오늘은 이러한 한계를 극복하기 위한 전문(Full-text) 검색 엔진, **Elasticsearch**의 핵심 원리와 기본적인 사용법에 대해 학습했습니다.

---

### 1. **왜 RDBMS의 `LIKE` 검색은 한계가 있을까?**

-   **성능 문제**: `LIKE '%keyword%'` 와 같은 쿼리는 테이블의 모든 데이터를 처음부터 끝까지 스캔하는 **Full Table Scan**을 유발합니다. 인덱스를 활용할 수 없어 데이터가 수십만 건만 넘어가도 검색 속도가 매우 느려집니다.
-   **정확도 문제**: `LIKE` 검색은 단순히 문자열의 포함 여부만 확인합니다. "자바 프로그래밍"을 검색했을 때 "자바"나 "프로그래밍"만 포함된 문서는 찾아주지 못합니다. 또한, 검색 결과의 관련도(Relevance)를 계산하여 정렬하는 기능이 없습니다.
-   **형태소 분석의 부재**: 한국어의 경우 '맛집'과 '맛집이'를 다른 단어로 인식합니다. 사용자의 다양한 검색어에 유연하게 대응하기 어렵습니다.

---

### 2. **Elasticsearch의 핵심 원리: 역색인(Inverted Index)**

Elasticsearch가 어떻게 이렇게 빠르고 정확한 검색을 할 수 있는지에 대한 비밀은 **역색인(Inverted Index)**이라는 자료 구조에 있습니다.

-   **역색인이란?**
    -   일반적인 책의 '목차'가 "문서 -> 단어" 순서라면, '찾아보기(인덱스)'는 **"단어 -> 문서"** 순서로 정리되어 있습니다. 역색인은 이 '찾아보기'와 같은 구조입니다.
    -   문서의 텍스트를 **텀(Term)**이라는 작은 단위(주로 단어)로 분리하고, 각 텀이 어떤 문서에 등장하는지를 기록한 데이터 구조입니다.

-   **동작 과정**:
    1.  **인덱싱(Indexing)**: 문서가 저장될 때, Elasticsearch는 **분석기(Analyzer)**를 사용하여 텍스트를 처리합니다.
        -   **형태소 분석**: "맛집에서 먹는 파스타" -> `"맛집"`, `"먹다"`, `"파스타"` 와 같이 의미 있는 단어(Term)로 분리합니다. (이 과정에서 불필요한 조사, 어미 등은 제거됩니다.)
        -   **역색인 생성**: 분리된 텀들을 기반으로 어떤 텀이 어떤 문서 ID에 있는지 기록합니다.
    2.  **검색(Search)**: 사용자가 "파스타 맛집"으로 검색하면,
        -   검색어도 동일한 분석기로 처리하여 `"파스타"`, `"맛집"`이라는 텀을 얻습니다.
        -   역색인에서 `"파스타"`가 포함된 문서 목록과 `"맛집"`이 포함된 문서 목록을 찾습니다.
        -   두 목록에 모두 포함된 문서를 찾아 관련도 순으로 정렬하여 반환합니다.



이러한 방식 덕분에 Elasticsearch는 테이블 전체를 스캔할 필요 없이, 역색인에서 단어를 찾는 것만으로 즉시 검색 결과를 찾아낼 수 있습니다.

---

### 3. **Spring Boot와 Elasticsearch 연동하기**

Spring Data Elasticsearch를 사용하면 JPA를 사용하듯 익숙한 방식으로 Elasticsearch와 연동할 수 있습니다.

**1. 의존성 추가 (`build.gradle`)**
```groovy
implementation 'org.springframework.boot:spring-boot-starter-data-elasticsearch'
```

**2. Document 엔티티 정의**
-   RDBMS의 `@Entity`와 유사하게, Elasticsearch에 저장될 문서의 구조를 `@Document` 애노테이션으로 정의합니다.
```java
@Document(indexName = "products") // Elasticsearch의 인덱스(데이터베이스 스키마와 유사) 이름
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ProductDocument {

    @Id
    private Long id;

    @Field(type = FieldType.Text, analyzer = "nori_analyzer") // 한국어 분석기 nori 사용
    private String name;

    @Field(type = FieldType.Text, analyzer = "nori_analyzer")
    private String description;

    @Field(type = FieldType.Long)
    private Long price;

    public ProductDocument(Long id, String name, String description, Long price) {
        this.id = id;
        this.name = name;
        this.description = description;
        this.price = price;
    }
}
```

**3. Elasticsearch Repository 생성**
-   `JpaRepository`와 마찬가지로 `ElasticsearchRepository`를 상속받는 인터페이스를 만듭니다.
```java
public interface ProductSearchRepository extends ElasticsearchRepository<ProductDocument, Long> {

    // 메서드 이름 기반으로 검색 쿼리 자동 생성
    List<ProductDocument> findByName(String name);
    
    // description 필드에서 keyword를 포함하는 문서 검색
    List<ProductDocument> findByDescriptionContaining(String keyword);
}
```

**4. 데이터 인덱싱 및 검색**
```java
@Service
@RequiredArgsConstructor
public class ProductSearchService {

    private final ProductSearchRepository productSearchRepository;

    public void indexProduct(Product product) {
        ProductDocument document = new ProductDocument(
            product.getId(),
            product.getName(),
            product.getDescription(),
            product.getPrice()
        );
        productSearchRepository.save(document); // Elasticsearch에 문서 저장(인덱싱)
    }

    public List<ProductDocument> searchByDescription(String keyword) {
        return productSearchRepository.findByDescriptionContaining(keyword);
    }
}
```

---

## 💡 배운 점

1.  **'검색'은 '조회'와 다른 전문 분야다**: 데이터베이스에서 단순히 데이터를 찾아오는 것과, 사용자의 의도를 파악하여 가장 관련도 높은 결과를 빠르고 유연하게 제공하는 '검색'은 완전히 다른 영역임을 깨달았습니다. 전문 검색 엔진이 왜 필요한지에 대한 기술적인 이유를 명확히 이해했습니다.
2.  **역색인은 검색을 위한 최고의 발명품이다**: 모든 문서를 뒤지는 대신, 단어가 어디에 있는지를 미리 정리해둔 '역색인'이라는 발상의 전환이 어떻게 대용량 텍스트 검색을 가능하게 하는지 알게 되었습니다.
3.  **Spring Data의 위대한 추상화**: Spring Data Elasticsearch 덕분에 Elasticsearch의 복잡한 REST API를 직접 다루지 않고도, JPA를 사용하듯 익숙한 Repository 패턴으로 검색 기능을 구현할 수 있다는 점이 매우 인상적이었습니다. 이는 개발자가 비즈니스 로직에 더 집중할 수 있도록 도와주는 훌륭한 추상화입니다.

---

## 🔗 참고 자료

-   [Elasticsearch - What is it? (Official Guide)](https://www.elastic.co/guide/en/elasticsearch/reference/current/elasticsearch-intro.html)
-   [Spring Data Elasticsearch - Reference Documentation](https://docs.spring.io/spring-data/elasticsearch/docs/current/reference/html/)
-   [역색인 (Inverted Index) 이란?](https://www.elastic.co/kr/blog/found-elasticsearch-from-the-bottom-up)