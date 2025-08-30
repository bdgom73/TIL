---
layout: single
title: "📁 카테고리별 글"
permalink: /categories/
author_profile: true
---

# 📁 카테고리별 글

총 **{{ site.categories.size }}**개의 카테고리로 분류된 글들을 확인할 수 있습니다.

## 📊 카테고리 통계

{% for category in site.categories %}
{% assign category_name = category[0] %}
{% assign posts_count = category[1].size %}
<div class="category-section" id="{{ category_name | slugify }}">
  <h2 class="category-title">
    {{ category_name }}
    <span class="category-count">{{ posts_count }}개</span>
  </h2>
  
  <div class="category-posts">
    {% for post in category[1] %}
    <div class="category-post">
      <h3 class="post-title">
        <a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a>
      </h3>
      <div class="post-meta">
        <span class="post-date">
          <i class="far fa-calendar-alt"></i>
          {{ post.date | date: "%Y년 %m월 %d일" }}
        </span>
        {% if post.tags %}
        <span class="post-tags">
          <i class="fas fa-tags"></i>
          {% for tag in post.tags %}
          <a href="{{ site.baseurl }}/tags/#{{ tag | slugify }}">{{ tag }}</a>{% unless forloop.last %}, {% endunless %}
          {% endfor %}
        </span>
        {% endif %}
      </div>
      {% if post.excerpt %}
      <div class="post-excerpt">
        {{ post.excerpt | strip_html | truncatewords: 30 }}
      </div>
      {% endif %}
    </div>
    {% endfor %}
  </div>
</div>

{% unless forloop.last %}
<hr class="category-divider">
{% endunless %}
{% endfor %}

<style>
.category-section {
  margin-bottom: 3rem;
}

.category-title {
  display: flex;
  align-items: center;
  gap: 1rem;
  color: #333;
  border-bottom: 3px solid #007acc;
  padding-bottom: 0.5rem;
  margin-bottom: 1.5rem;
}

.category-count {
  background-color: #007acc;
  color: white;
  padding: 0.3rem 0.8rem;
  border-radius: 15px;
  font-size: 0.9rem;
  font-weight: 600;
}

.category-posts {
  display: grid;
  gap: 1.5rem;
}

.category-post {
  padding: 1.5rem;
  border: 1px solid #e9ecef;
  border-radius: 8px;
  background-color: #fff;
  transition: all 0.3s ease;
}

.category-post:hover {
  border-color: #007acc;
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  transform: translateY(-2px);
}

.post-title {
  margin: 0 0 0.75rem 0;
  font-size: 1.3rem;
}

.post-title a {
  color: #333;
  text-decoration: none;
  transition: color 0.2s ease;
}

.post-title a:hover {
  color: #007acc;
}

.post-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  font-size: 0.85rem;
  color: #666;
  margin-bottom: 0.75rem;
}

.post-meta span {
  display: flex;
  align-items: center;
  gap: 0.25rem;
}

.post-meta a {
  color: #007acc;
  text-decoration: none;
}

.post-meta a:hover {
  text-decoration: underline;
}

.post-excerpt {
  color: #555;
  line-height: 1.5;
  font-size: 0.9rem;
}

.category-divider {
  border: none;
  border-top: 2px solid #e9ecef;
  margin: 3rem 0;
}

@media (max-width: 768px) {
  .category-title {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }
  
  .post-meta {
    flex-direction: column;
    gap: 0.5rem;
  }
  
  .category-post {
    padding: 1rem;
  }
}
</style> 