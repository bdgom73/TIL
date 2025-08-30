---
layout: home
title: "Gom's TIL"
permalink: /
---

# 👋 환영합니다!

이 블로그는 제가 배우고 기록한 기술들을 정리한 공간입니다.  
최신 글들을 확인해보세요!

<ul>
  {% for post in site.posts %}
    <li>
      <a href="{{ site.baseurl }}{{ post.url }}">
        {{ post.title }}
      </a>
    </li>
  {% endfor %}
</ul>