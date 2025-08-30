---
layout: none
---

<div class="sidebar-recent">
  <h4>🆕 최근 글</h4>
  <ul class="recent-list">
    {% raw %}
    {% for post in site.posts limit:5 %}
    <li class="recent-item">
      <a href="{{ site.baseurl }}{{ post.url }}" class="recent-link">
        <div class="recent-content">
          <span class="recent-title">{{ post.title }}</span>
          <span class="recent-date">{{ post.date | date: "%m월 %d일" }}</span>
        </div>
        {% if post.categories %}
        <span class="recent-category">{{ post.categories.first }}</span>
        {% endif %}
      </a>
    </li>
    {% endfor %}
    {% endraw %}
  </ul>
</div>

<style>
.sidebar-recent {
  margin-bottom: 2rem;
}

.recent-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.recent-item {
  margin-bottom: 0.75rem;
  padding: 0.75rem;
  background-color: #f8f9fa;
  border-radius: 6px;
  transition: all 0.2s ease;
}

.recent-item:hover {
  background-color: #e9ecef;
  transform: translateX(3px);
}

.recent-link {
  text-decoration: none;
  color: inherit;
  display: block;
}

.recent-content {
  display: flex;
  flex-direction: column;
  margin-bottom: 0.5rem;
}

.recent-title {
  font-size: 0.9rem;
  font-weight: 500;
  line-height: 1.3;
  color: #333;
  margin-bottom: 0.25rem;
}

.recent-date {
  font-size: 0.75rem;
  color: #666;
}

.recent-category {
  display: inline-block;
  font-size: 0.7rem;
  background-color: #007acc;
  color: white;
  padding: 0.2rem 0.5rem;
  border-radius: 12px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
</style> 