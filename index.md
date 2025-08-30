---
layout: home
title: "Gom's TIL"
permalink: /
author_profile: true
---

# 👋 안녕하세요! Gom's TIL 블로그입니다

매일 배우고 기록하는 **Today I Learned** 공간에 오신 것을 환영합니다! 🎉

## 📚 최근 학습 내용

{% raw %}
{% for post in site.posts limit:5 %}
<div class="post-preview">
  <h3><a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a></h3>
  <p class="post-meta">
    <i class="far fa-calendar-alt"></i> {{ post.date | date: "%Y년 %m월 %d일" }}
    {% if post.categories %}
    <i class="fas fa-folder-open"></i> {{ post.categories | join: ", " }}
    {% endif %}
    {% if post.tags %}
    <i class="fas fa-tags"></i> {{ post.tags | join: ", " }}
    {% endif %}
  </p>
  {% if post.excerpt %}
  <p class="post-excerpt">{{ post.excerpt | strip_html | truncatewords: 30 }}</p>
  {% endif %}
</div>
{% endfor %}
{% endraw %}

## 🚀 빠른 탐색

- **[📖 전체 글 목록]({{ site.baseurl }}/posts/)** - 모든 TIL 글을 한눈에
- **[🏷️ 카테고리별]({{ site.baseurl }}/categories/)** - 주제별로 정리된 글들
- **[🔍 태그 검색]({{ site.baseurl }}/tags/)** - 키워드로 원하는 내용 찾기
- **[📅 연도별 아카이브]({{ site.baseurl }}/archive/)** - 시간순으로 정리된 글들

## 💡 이 블로그는...

- **매일 학습한 내용**을 체계적으로 정리
- **실무에서 경험한 것들**을 기록
- **새로운 기술과 개념**을 학습하고 정리
- **개발자 커뮤니티**와 지식 공유

## 📈 학습 통계

{% raw %}
- **총 글 수**: {{ site.posts.size }}개
- **카테고리 수**: {{ site.categories.size }}개
- **태그 수**: {{ site.tags.size }}개
- **마지막 업데이트**: {{ site.posts.first.date | date: "%Y년 %m월 %d일" }}
{% endraw %}

---

*더 많은 내용을 보고 싶으시다면 [전체 글 목록]({{ site.baseurl }}/posts/)을 확인해보세요!*