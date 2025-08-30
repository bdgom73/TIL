---
layout: none
---

<div class="sidebar-date-navigation">
  <h4>📅 날짜별 이동</h4>
  
  <!-- 간단한 테스트 버전 -->
  <div class="test-content">
    <p>총 글 수: {{ site.posts.size }}개</p>
    
    {% if site.posts.size > 0 %}
      <p>첫 번째 글: {{ site.posts.first.title }}</p>
      <p>마지막 글: {{ site.posts.last.title }}</p>
    {% else %}
      <p>아직 글이 없습니다.</p>
    {% endif %}
  </div>
  
  <!-- 연도별 간단한 목록 -->
  {% assign years = site.posts | group_by_exp: "post", "post.date | date: '%Y'" %}
  {% if years.size > 0 %}
    <div class="years-list">
      <h5>연도별 글 수:</h5>
      {% for year in years %}
        <div class="year-item">
          {{ year.name }}년: {{ year.items.size }}개
        </div>
      {% endfor %}
    </div>
  {% else %}
    <p>연도별 데이터가 없습니다.</p>
  {% endif %}
</div>

<style>
.sidebar-date-navigation {
  margin-bottom: 2rem;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  padding: 1rem;
}

.test-content {
  margin-bottom: 1rem;
  padding: 0.5rem;
  background: #f8f9fa;
  border-radius: 4px;
}

.test-content p {
  margin: 0.25rem 0;
  font-size: 0.9rem;
}

.years-list {
  margin-top: 1rem;
}

.years-list h5 {
  margin: 0 0 0.5rem 0;
  color: #333;
  font-size: 0.9rem;
}

.year-item {
  padding: 0.25rem 0;
  font-size: 0.85rem;
  color: #666;
  border-bottom: 1px solid #eee;
}

.year-item:last-child {
  border-bottom: none;
}
</style> 