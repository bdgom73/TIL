---
layout: home
title: "Gom's TIL"
permalink: /
author_profile: true
---

# 👋 안녕하세요! Gom's TIL 블로그입니다

매일 배우고 기록하는 **Today I Learned** 공간에 오신 것을 환영합니다! 🎉

## 📚 최근 학습 내용

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

## 💡 이 블로그는...

- **매일 학습한 내용**을 체계적으로 정리
- **실무에서 경험한 것들**을 기록
- **새로운 기술과 개념**을 학습하고 정리
- **개발자 커뮤니티**와 지식 공유

## 📈 학습 통계

- **총 글 수**: {{ site.posts.size }}개
- **카테고리 수**: {{ site.categories.size }}개
- **태그 수**: {{ site.tags.size }}개
- **마지막 업데이트**: {{ site.posts.first.date | date: "%Y년 %m월 %d일" }}

---

*매일 배우고 기록하는 것이 중요합니다! 🚀*