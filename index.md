---
layout: home
title: 전체 글 목록 (아카이브)
---

# 전체 글 목록

이 페이지는 모든 글을 연도와 월별로 정리한 목록입니다.

{% assign postsByYear = site.posts | group_by_exp:"post", "post.date | date: '%Y'" %}
<ul>
  {% for year in postsByYear %}
    <li>
      <h2>{{ year.name }}년</h2>
      {% assign postsByMonth = year.items | group_by_exp:"post", "post.date | date: '%-m'" %}
      <ul>
        {% for month in postsByMonth %}
          <li>
            <h3>{{ month.name }}월</h3>
            <ul>
              {% for post in month.items %}
                <li>
                  <a href="{{ site.baseurl }}{{ post.url }}">{{ post.date | date: "%d" }}일 - {{ post.title }}</a>
                </li>
              {% endfor %}
            </ul>
          </li>
        {% endfor %}
      </ul>
    </li>
  {% endfor %}
</ul>