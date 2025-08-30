---
layout: none
---

<div class="sidebar-categories">
  <h4>📁 카테고리별</h4>
  <div class="categories-list">
    {% for category in site.categories %}
    {% assign category_name = category[0] %}
    {% assign posts_count = category[1].size %}
    <div class="category-item">
      <div class="category-link">
        <span class="category-name">{{ category_name }}</span>
        <span class="category-count">{{ posts_count }}</span>
      </div>
    </div>
    {% endfor %}
  </div>
</div>

<style>
.sidebar-categories {
  margin-bottom: 2rem;
}

.categories-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.category-item {
  flex: 1 1 calc(50% - 0.25rem);
  min-width: 120px;
}

.category-link {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 0.75rem;
  background-color: #f8f9fa;
  border: 1px solid #e9ecef;
  border-radius: 6px;
  color: #333;
  font-size: 0.85rem;
}

.category-name {
  font-weight: 500;
}

.category-count {
  background-color: #dee2e6;
  color: #495057;
  padding: 0.2rem 0.5rem;
  border-radius: 12px;
  font-size: 0.75rem;
  font-weight: 600;
  min-width: 20px;
  text-align: center;
}
</style> 