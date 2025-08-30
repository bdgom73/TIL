---
layout: default
---

# Today I Learned

{% assign sorted_posts = site.posts | sort: "date" | reverse %}

<ul>
  {% for post in sorted_posts %}
    <li>
      <a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a> ({{ post.date | date: "%Y-%m-%d" }})
    </li>
  {% endfor %}
</ul>