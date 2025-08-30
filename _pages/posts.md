---
layout: single
title: "📖 전체 글 목록"
permalink: /posts/
author_profile: true
---

# 📖 전체 글 목록

총 **{% raw %}{{ site.posts.size }}{% endraw %}**개의 TIL 글을 확인할 수 있습니다.

## 📅 최신 글부터 보기

{% raw %}
{% for post in site.posts %}
<div class="post-item">
  <article class="post-preview">
    <header class="post-header">
      <h2 class="post-title">
        <a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a>
      </h2>
      <div class="post-meta">
        <span class="post-date">
          <i class="far fa-calendar-alt"></i>
          {{ post.date | date: "%Y년 %m월 %d일" }}
        </span>
        {% if post.categories %}
        <span class="post-categories">
          <i class="fas fa-folder-open"></i>
          {% for category in post.categories %}
          <a href="{{ site.baseurl }}/categories/#{{ category | slugify }}">{{ category }}</a>{% unless forloop.last %}, {% endunless %}
          {% endfor %}
        </span>
        {% endif %}
        {% if post.tags %}
        <span class="post-tags">
          <i class="fas fa-tags"></i>
          {% for tag in post.tags %}
          <a href="{{ site.baseurl }}/tags/#{{ tag | slugify }}">{{ tag }}</a>{% unless forloop.last %}, {% endunless %}
          {% endfor %}
        </span>
        {% endif %}
      </div>
    </header>
    
    {% if post.excerpt %}
    <div class="post-excerpt">
      {{ post.excerpt | strip_html | truncatewords: 50 }}
    </div>
    {% endif %}
    
    <div class="post-footer">
      <a href="{{ site.baseurl }}{{ post.url }}" class="read-more">
        계속 읽기 <i class="fas fa-arrow-right"></i>
      </a>
    </div>
  </article>
</div>

{% unless forloop.last %}
<hr class="post-divider">
{% endunless %}
{% endfor %}
{% endraw %}

<style>
.post-item {
  margin-bottom: 2rem;
}

.post-preview {
  padding: 1.5rem;
  border: 1px solid #e9ecef;
  border-radius: 8px;
  background-color: #fff;
  transition: all 0.3s ease;
}

.post-preview:hover {
  border-color: #007acc;
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  transform: translateY(-2px);
}

.post-header {
  margin-bottom: 1rem;
}

.post-title {
  margin: 0 0 0.5rem 0;
  font-size: 1.5rem;
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
  font-size: 0.9rem;
  color: #666;
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
  line-height: 1.6;
  margin-bottom: 1rem;
}

.post-footer {
  text-align: right;
}

.read-more {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  background-color: #007acc;
  color: white;
  text-decoration: none;
  border-radius: 5px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.read-more:hover {
  background-color: #005a9e;
  color: white;
  transform: translateX(3px);
}

.post-divider {
  border: none;
  border-top: 1px solid #e9ecef;
  margin: 2rem 0;
}

@media (max-width: 768px) {
  .post-meta {
    flex-direction: column;
    gap: 0.5rem;
  }
  
  .post-preview {
    padding: 1rem;
  }
}
</style> 