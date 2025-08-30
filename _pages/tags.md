---
layout: single
title: "🏷️ 태그별 글"
permalink: /tags/
author_profile: true
---

# 🏷️ 태그별 글

총 **{% raw %}{{ site.tags.size }}{% endraw %}**개의 태그로 분류된 글들을 확인할 수 있습니다.

## 🔍 태그 검색

<div class="tag-search">
  <input type="text" id="tagSearch" placeholder="태그명을 입력하세요..." class="search-input">
</div>

## 📊 태그 통계

{% raw %}
{% assign tags = site.tags | sort_by: 'size' | reverse %}
{% for tag in tags %}
{% assign tag_name = tag[0] %}
{% assign posts_count = tag[1].size %}
<div class="tag-section" id="{{ tag_name | slugify }}">
  <h2 class="tag-title">
    <span class="tag-icon">🏷️</span>
    {{ tag_name }}
    <span class="tag-count">{{ posts_count }}개</span>
  </h2>
  
  <div class="tag-posts">
    {% for post in tag[1] %}
    <div class="tag-post">
      <h3 class="post-title">
        <a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a>
      </h3>
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
      </div>
      {% if post.excerpt %}
      <div class="post-excerpt">
        {{ post.excerpt | strip_html | truncatewords: 25 }}
      </div>
      {% endif %}
    </div>
    {% endfor %}
  </div>
</div>

{% unless forloop.last %}
<hr class="tag-divider">
{% endunless %}
{% endfor %}
{% endraw %}

<style>
.tag-search {
  margin-bottom: 2rem;
  text-align: center;
}

.search-input {
  width: 100%;
  max-width: 400px;
  padding: 0.75rem 1rem;
  border: 2px solid #e9ecef;
  border-radius: 25px;
  font-size: 1rem;
  transition: all 0.3s ease;
}

.search-input:focus {
  outline: none;
  border-color: #007acc;
  box-shadow: 0 0 0 3px rgba(0, 122, 204, 0.1);
}

.tag-section {
  margin-bottom: 3rem;
}

.tag-title {
  display: flex;
  align-items: center;
  gap: 1rem;
  color: #333;
  border-bottom: 3px solid #007acc;
  padding-bottom: 0.5rem;
  margin-bottom: 1.5rem;
}

.tag-icon {
  font-size: 1.5rem;
}

.tag-count {
  background-color: #007acc;
  color: white;
  padding: 0.3rem 0.8rem;
  border-radius: 15px;
  font-size: 0.9rem;
  font-weight: 600;
}

.tag-posts {
  display: grid;
  gap: 1.5rem;
}

.tag-post {
  padding: 1.5rem;
  border: 1px solid #e9ecef;
  border-radius: 8px;
  background-color: #fff;
  transition: all 0.3s ease;
}

.tag-post:hover {
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

.tag-divider {
  border: none;
  border-top: 2px solid #e9ecef;
  margin: 3rem 0;
}

@media (max-width: 768px) {
  .tag-title {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }
  
  .post-meta {
    flex-direction: column;
    gap: 0.5rem;
  }
  
  .tag-post {
    padding: 1rem;
  }
}
</style>

<script>
document.addEventListener('DOMContentLoaded', function() {
  const searchInput = document.getElementById('tagSearch');
  const tagSections = document.querySelectorAll('.tag-section');
  
  searchInput.addEventListener('input', function() {
    const searchTerm = this.value.toLowerCase().trim();
    
    tagSections.forEach(section => {
      const tagName = section.querySelector('.tag-title').textContent.toLowerCase();
      const posts = section.querySelectorAll('.tag-post');
      
      if (tagName.includes(searchTerm)) {
        section.style.display = 'block';
        posts.forEach(post => post.style.display = 'block');
      } else {
        section.style.display = 'none';
      }
    });
  });
});
</script> 