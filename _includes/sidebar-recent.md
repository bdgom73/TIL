---
layout: none
---

<div class="sidebar-recent">
  <h4>🆕 최근 글</h4>
  
  {% if site.posts.size > 0 %}
    <div class="recent-list">
      {% for post in site.posts limit:3 %}
      <div class="recent-item">
        <div class="recent-content">
          <span class="recent-title">{{ post.title }}</span>
          <span class="recent-date">{{ post.date | date: "%m월 %d일" }}</span>
        </div>
      </div>
      {% endfor %}
    </div>
  {% else %}
    <p>아직 글이 없습니다.</p>
  {% endif %}
</div>

<style>
.sidebar-recent {
  margin-bottom: 2rem;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  padding: 1rem;
}

.recent-list {
  display: grid;
  gap: 0.75rem;
}

.recent-item {
  padding: 0.75rem;
  background-color: #f8f9fa;
  border-radius: 6px;
  border: 1px solid #e9ecef;
}

.recent-content {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.recent-title {
  font-size: 0.9rem;
  font-weight: 500;
  line-height: 1.3;
  color: #333;
}

.recent-date {
  font-size: 0.75rem;
  color: #666;
}
</style> 