---
layout: none
---

<div class="sidebar-date-navigation">
  <h4>📅 날짜별 이동</h4>
  
  <!-- 연도별 아코디언 -->
  {% assign years = site.posts | group_by_exp: "post", "post.date | date: '%Y'" | sort: "name" | reverse %}
  {% for year in years %}
  {% assign year_name = year.name %}
  {% assign year_posts = year.items | sort: "date" | reverse %}
  
  <div class="year-accordion">
    <div class="year-header" onclick="toggleYear('{{ year_name }}')">
      <span class="year-title">{{ year_name }}년</span>
      <span class="year-count">{{ year_posts.size }}개</span>
      <i class="fas fa-chevron-down year-icon" id="icon-{{ year_name }}"></i>
    </div>
    
    <div class="year-content" id="content-{{ year_name }}">
      <!-- 월별 그룹 -->
      {% assign months = year_posts | group_by_exp: "post", "post.date | date: '%m'" | sort: "name" | reverse %}
      {% for month in months %}
      {% assign month_name = month.name %}
      {% assign month_posts = month.items | sort: "date" | reverse %}
      {% assign month_label = month_name | plus: 0 %}
      
      <div class="month-group">
        <div class="month-header" onclick="toggleMonth('{{ year_name }}-{{ month_name }}')">
          <span class="month-title">{{ month_label }}월</span>
          <span class="month-count">{{ month_posts.size }}개</span>
          <i class="fas fa-chevron-right month-icon" id="month-icon-{{ year_name }}-{{ month_name }}"></i>
        </div>
        
        <div class="month-content" id="month-content-{{ year_name }}-{{ month_name }}">
          {% for post in month_posts %}
          <div class="date-post">
            <a href="{{ site.baseurl }}{{ post.url }}" class="date-post-link">
              <span class="post-day">{{ post.date | date: "%d" }}</span>
              <span class="post-title">{{ post.title }}</span>
            </a>
          </div>
          {% endfor %}
        </div>
      </div>
      {% endfor %}
    </div>
  </div>
  {% endfor %}
</div>

<style>
.sidebar-date-navigation {
  margin-bottom: 2rem;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  overflow: hidden;
}

.year-accordion {
  border-bottom: 1px solid #f0f0f0;
}

.year-accordion:last-child {
  border-bottom: none;
}

.year-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem;
  background: #f8f9fa;
  cursor: pointer;
  transition: background-color 0.2s ease;
  user-select: none;
}

.year-header:hover {
  background: #e9ecef;
}

.year-title {
  font-weight: 600;
  color: #333;
  font-size: 1.1rem;
}

.year-count {
  background: #007acc;
  color: white;
  padding: 0.2rem 0.6rem;
  border-radius: 12px;
  font-size: 0.8rem;
  font-weight: 600;
}

.year-icon {
  color: #666;
  transition: transform 0.3s ease;
}

.year-icon.rotated {
  transform: rotate(180deg);
}

.year-content {
  max-height: 0;
  overflow: hidden;
  transition: max-height 0.3s ease;
}

.year-content.expanded {
  max-height: 2000px;
}

.month-group {
  border-top: 1px solid #f0f0f0;
}

.month-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem 0.75rem 2rem;
  background: #fafbfc;
  cursor: pointer;
  transition: background-color 0.2s ease;
  user-select: none;
}

.month-header:hover {
  background: #f1f3f4;
}

.month-title {
  font-weight: 500;
  color: #555;
  font-size: 1rem;
}

.month-count {
  background: #6c757d;
  color: white;
  padding: 0.15rem 0.5rem;
  border-radius: 10px;
  font-size: 0.75rem;
  font-weight: 600;
}

.month-icon {
  color: #888;
  transition: transform 0.3s ease;
  font-size: 0.8rem;
}

.month-icon.rotated {
  transform: rotate(90deg);
}

.month-content {
  max-height: 0;
  overflow: hidden;
  transition: max-height 0.3s ease;
}

.month-content.expanded {
  max-height: 1000px;
}

.date-post {
  border-top: 1px solid #f0f0f0;
}

.date-post:last-child {
  border-bottom: 1px solid #f0f0f0;
}

.date-post-link {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1rem 0.75rem 3rem;
  text-decoration: none;
  color: #333;
  transition: background-color 0.2s ease;
}

.date-post-link:hover {
  background: #f8f9fa;
  color: #007acc;
}

.post-day {
  background: #007acc;
  color: white;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.8rem;
  font-weight: 600;
  flex-shrink: 0;
}

.post-title {
  font-size: 0.9rem;
  line-height: 1.4;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}

/* 반응형 디자인 */
@media (max-width: 768px) {
  .sidebar-date-navigation {
    margin-bottom: 1rem;
  }
  
  .year-header, .month-header {
    padding: 0.75rem;
  }
  
  .date-post-link {
    padding: 0.5rem 0.75rem 0.5rem 2rem;
  }
  
  .post-title {
    font-size: 0.85rem;
  }
}
</style>

<script>
// 연도별 아코디언 토글
function toggleYear(year) {
  const content = document.getElementById('content-' + year);
  const icon = document.getElementById('icon-' + year);
  
  if (content.classList.contains('expanded')) {
    content.classList.remove('expanded');
    icon.classList.remove('rotated');
  } else {
    content.classList.add('expanded');
    icon.classList.add('rotated');
  }
}

// 월별 아코디언 토글
function toggleMonth(monthId) {
  const content = document.getElementById('month-content-' + monthId);
  const icon = document.getElementById('month-icon-' + monthId);
  
  if (content.classList.contains('expanded')) {
    content.classList.remove('expanded');
    icon.classList.remove('rotated');
  } else {
    content.classList.add('expanded');
    icon.classList.add('rotated');
  }
}

// 페이지 로드 시 현재 연도와 월 자동 확장
document.addEventListener('DOMContentLoaded', function() {
  const currentDate = new Date();
  const currentYear = currentDate.getFullYear().toString();
  const currentMonth = (currentDate.getMonth() + 1).toString().padStart(2, '0');
  
  // 현재 연도 자동 확장
  const currentYearContent = document.getElementById('content-' + currentYear);
  const currentYearIcon = document.getElementById('icon-' + currentYear);
  if (currentYearContent && currentYearIcon) {
    currentYearContent.classList.add('expanded');
    currentYearIcon.classList.add('rotated');
  }
  
  // 현재 월 자동 확장
  const currentMonthContent = document.getElementById('month-content-' + currentYear + '-' + currentMonth);
  const currentMonthIcon = document.getElementById('month-icon-' + currentYear + '-' + currentMonth);
  if (currentMonthContent && currentMonthIcon) {
    currentMonthContent.classList.add('expanded');
    currentMonthIcon.classList.add('rotated');
  }
});
</script> 