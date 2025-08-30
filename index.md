---
layout: home
title: 전체 글 목록 (아카이브)
---

# 전체 글 목록

<ul>
  {% for post in site.posts %}
    <li>
      <a href="{{ site.baseurl }}{{ post.url }}">
        {{ post.date | date: "%Y-%m-%d" }} - {{ post.title }}
      </a>
    </li>
  {% endfor %}
</ul>