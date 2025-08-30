---
title: "제목을 입력하세요"
date: YYYY-MM-DD
categories: [카테고리1, 카테고리2]
tags: [태그1, 태그2, 태그3]
excerpt: "이 글에서 다룰 내용을 간단히 요약해주세요."
author_profile: true
---

# Today I Learned: 제목

## 📅 날짜별 네비게이션

<div class="post-navigation">
  <div class="nav-section">
    <h3>📚 최근 글</h3>
    <ul>
      {% for post in site.posts limit:5 %}
      <li><a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a></li>
      {% endfor %}
    </ul>
  </div>
  
  <div class="nav-section">
    <h3>🏷️ 인기 태그</h3>
    <div class="tag-cloud">
      {% assign tags = site.tags | sort_by: 'size' | reverse %}
      {% for tag in tags limit:10 %}
      {% assign tag_name = tag[0] %}
      {% assign posts_count = tag[1].size %}
      <span class="tag-item">{{ tag_name }} ({{ posts_count }})</span>
      {% endfor %}
    </div>
  </div>
</div>

---

## 📚 오늘 학습한 내용

### 1. 주제 1
- 세부 내용 1
- 세부 내용 2
- 세부 내용 3

### 2. 주제 2
- 세부 내용 1
- 세부 내용 2

## 💻 코드 예시

```java
public class Example {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
```

## 💡 배운 점

- 핵심 개념 1
- 핵심 개념 2
- 실무 적용 포인트

---

*매일 조금씩이라도 배우고 기록하는 것이 중요합니다! 🚀*

<style>
.post-navigation {
  background: #f8f9fa;
  border: 1px solid #e9ecef;
  border-radius: 8px;
  padding: 1.5rem;
  margin: 2rem 0;
}

.nav-section {
  margin-bottom: 1.5rem;
}

.nav-section:last-child {
  margin-bottom: 0;
}

.nav-section h3 {
  color: #007acc;
  margin-bottom: 0.75rem;
  font-size: 1.1rem;
}

.nav-section ul {
  list-style: none;
  padding: 0;
  margin: 0;
}

.nav-section li {
  margin-bottom: 0.5rem;
  padding: 0.5rem;
  background: white;
  border-radius: 4px;
  border: 1px solid #e9ecef;
}

.nav-section a {
  color: #333;
  text-decoration: none;
  font-size: 0.9rem;
}

.nav-section a:hover {
  color: #007acc;
}

.tag-cloud {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.tag-item {
  background: #007acc;
  color: white;
  padding: 0.3rem 0.6rem;
  border-radius: 15px;
  font-size: 0.8rem;
  font-weight: 500;
}
</style> 