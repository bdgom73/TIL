---
layout: none
---

<div class="sidebar-tags">
  <h4>🏷️ 인기 태그</h4>
  <div class="tags-cloud">
    {% assign tags = site.tags | sort_by: 'size' | reverse %}
    {% for tag in tags limit:15 %}
    {% assign tag_name = tag[0] %}
    {% assign posts_count = tag[1].size %}
    {% assign font_size = posts_count | times: 2 | plus: 12 %}
    <span class="tag-link" style="font-size: {{ font_size }}px;">
      {{ tag_name }}
      <span class="tag-count">{{ posts_count }}</span>
    </span>
    {% endfor %}
  </div>
</div>

<style>
.sidebar-tags {
  margin-bottom: 2rem;
}

.tags-cloud {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.tag-link {
  display: inline-flex;
  align-items: center;
  padding: 0.3rem 0.6rem;
  background-color: #e9ecef;
  color: #495057;
  border-radius: 15px;
  font-weight: 500;
  line-height: 1;
}

.tag-count {
  background-color: #6c757d;
  color: white;
  font-size: 0.7rem;
  padding: 0.1rem 0.4rem;
  border-radius: 10px;
  margin-left: 0.3rem;
  font-weight: 600;
  min-width: 16px;
  text-align: center;
}
</style> 