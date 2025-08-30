---
layout: single
title: "📅 연도별 아카이브"
permalink: /archive/
author_profile: true
---

# 📅 연도별 아카이브

총 **{{ site.posts.size }}**개의 TIL 글을 연도별로 정리했습니다.

## 📊 연도별 통계

{% assign years = site.posts | group_by_exp: "post", "post.date | date: '%Y'" | sort: "name" | reverse %}
{% for year in years %}
{% assign year_name = year.name %}
{% assign posts_count = year.items.size %}
<div class="year-section" id="year-{{ year_name }}">
  <h2 class="year-title">
    <span class="year-icon">📅</span>
    {{ year_name }}년
    <span class="year-count">{{ posts_count }}개</span>
  </h2>
  
  <div class="year-posts">
    {% for post in year.items %}
    <div class="archive-post">
      <div class="post-date">
        <span class="day">{{ post.date | date: "%m/%d" }}</span>
      </div>
      <div class="post-content">
        <h4 class="post-title">
          <a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a>
        </h4>
        <div class="post-meta">
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
      </div>
    </div>
    {% endfor %}
  </div>
</div>

{% unless forloop.last %}
<hr class="year-divider">
{% endunless %}
{% endfor %}

<style>
.year-section {
  margin-bottom: 4rem;
}

.year-title {
  display: flex;
  align-items: center;
  gap: 1rem;
  color: #333;
  border-bottom: 3px solid #007acc;
  padding-bottom: 0.5rem;
  margin-bottom: 2rem;
  font-size: 2rem;
}

.year-icon {
  font-size: 2rem;
}

.year-count {
  background-color: #007acc;
  color: white;
  padding: 0.5rem 1rem;
  border-radius: 20px;
  font-size: 1rem;
  font-weight: 600;
}

.year-posts {
  display: grid;
  gap: 1.5rem;
}

.archive-post {
  display: flex;
  gap: 1rem;
  padding: 1rem;
  border: 1px solid #f0f0f0;
  border-radius: 8px;
  background-color: #fff;
  transition: all 0.3s ease;
}

.archive-post:hover {
  border-color: #007acc;
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  transform: translateX(5px);
}

.post-date {
  flex-shrink: 0;
  width: 50px;
  height: 50px;
  background-color: #007acc;
  color: white;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: bold;
  font-size: 1.1rem;
}

.post-content {
  flex: 1;
}

.post-title {
  margin: 0 0 0.5rem 0;
  font-size: 1.1rem;
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
  gap: 0.75rem;
  font-size: 0.8rem;
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

.year-divider {
  border: none;
  border-top: 3px solid #e9ecef;
  margin: 4rem 0;
}

@media (max-width: 768px) {
  .year-title {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
    font-size: 1.5rem;
  }
  
  .archive-post {
    flex-direction: column;
    gap: 0.5rem;
    text-align: center;
  }
  
  .post-date {
    align-self: center;
  }
}
</style> 