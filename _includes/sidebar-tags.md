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
    <a href="{{ site.baseurl }}/tags/#{{ tag_name | slugify }}" 
       class="tag-link" 
       style="font-size: {{ font_size }}px;">
      {{ tag_name }}
      <span class="tag-count">{{ posts_count }}</span>
    </a>
    {% endfor %}
  </div>
  <div class="tags-more">
    <a href="{{ site.baseurl }}/tags/" class="btn btn--small">전체 태그</a>
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
  text-decoration: none;
  border-radius: 15px;
  font-weight: 500;
  transition: all 0.2s ease;
  position: relative;
  line-height: 1;
}

.tag-link:hover {
  background-color: #007acc;
  color: white;
  transform: translateY(-1px);
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
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

.tag-link:hover .tag-count {
  background-color: rgba(255,255,255,0.2);
}

.tags-more {
  text-align: center;
}

.btn--small {
  padding: 0.25rem 0.75rem;
  font-size: 0.8rem;
  background-color: #007acc;
  color: white;
  border-radius: 3px;
  text-decoration: none;
  transition: background-color 0.2s ease;
}

.btn--small:hover {
  background-color: #005a9e;
  color: white;
}
</style> 