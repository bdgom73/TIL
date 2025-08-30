---
layout: home
title: 전체 글 목록 (아카이브)
sidebar:
  - title: "전체 글 목록"
    include: sidebar-archive.html
---

# 전체 글 목록

<ul>
  {% for post in site.posts %}
    <li>
      <a href="{{ post.url }}">{{ post.date | date: "%Y-%m-%d" }} - {{ post.title }}</a>
    </li>
  {% endfor %}
</ul>