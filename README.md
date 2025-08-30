# 🚀 Gom's TIL (Today I Learned) 블로그

매일 배우고 기록하는 기술 블로그입니다. GitHub Pages를 통해 호스팅됩니다.

## ✨ 주요 기능

- 📚 **일일 학습 기록**: 매일 배운 내용을 체계적으로 정리
- 🏷️ **카테고리 & 태그**: 주제별, 키워드별로 글 분류 및 검색
- 📅 **연도별 아카이브**: 시간순으로 정리된 학습 기록
- 🔍 **검색 기능**: 태그 기반 검색으로 원하는 내용 빠르게 찾기
- 📱 **반응형 디자인**: 모바일과 데스크톱에서 최적화된 UI
- 🎨 **모던한 디자인**: Minimal Mistakes 테마 기반의 깔끔한 디자인

## 🛠️ 기술 스택

- **정적 사이트 생성기**: Jekyll 4.3.0
- **테마**: Minimal Mistakes
- **호스팅**: GitHub Pages
- **언어**: Ruby, HTML, CSS, JavaScript
- **플러그인**: Jekyll SEO, Sitemap, Feed, Pagination

## 🚀 로컬 개발 환경 설정

### 1. 사전 요구사항
- Ruby 2.6.0 이상
- RubyGems
- GCC 및 Make

### 2. 설치 및 실행

```bash
# 저장소 클론
git clone https://github.com/bdgom73/TIL.git
cd TIL

# Ruby 의존성 설치
bundle install

# 로컬 서버 실행
bundle exec jekyll serve
```

### 3. 접속
브라우저에서 `http://localhost:4000`으로 접속

## 📝 새 글 작성하기

### 1. 포스트 생성
`_posts/` 디렉토리에 `YYYY-MM-DD-title.md` 형식으로 파일 생성

### 2. Front Matter 작성
```yaml
---
title: "글 제목"
date: YYYY-MM-DD
categories: [카테고리1, 카테고리2]
tags: [태그1, 태그2, 태그3]
excerpt: "글 요약 (메인 페이지에 표시됨)"
author_profile: true
---
```

### 3. 마크다운으로 내용 작성
```markdown
# 제목

## 소제목

내용...

### 코드 예시
```java
public class Example {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
```

## 📁 프로젝트 구조

```
TIL/
├── _config.yml          # Jekyll 설정 파일
├── _includes/           # 재사용 가능한 컴포넌트
│   ├── sidebar-archive.md
│   ├── sidebar-categories.md
│   ├── sidebar-recent.md
│   └── sidebar-tags.md
├── _layouts/            # 레이아웃 템플릿
├── _pages/             # 추가 페이지들
│   ├── posts.md        # 전체 글 목록
│   ├── categories.md   # 카테고리별 글
│   ├── tags.md         # 태그별 글
│   └── archive.md      # 연도별 아카이브
├── _posts/             # TIL 글들
│   ├── 2025-08-29-today-i-learned.md
│   └── 2025-08-30-today-i-learned.md
├── index.md            # 메인 페이지
├── Gemfile            # Ruby 의존성
└── README.md          # 프로젝트 설명
```

## 🌐 배포

### GitHub Pages 자동 배포 (권장)
1. **GitHub 저장소 설정**:
   - 저장소 → Settings → Pages
   - Source: "GitHub Actions" 선택
   - Branch: `main` 선택

2. **자동 워크플로우**:
   - GitHub가 자동으로 Jekyll 워크플로우 생성
   - `main` 브랜치에 푸시하면 자동 배포
   - 배포 URL: `https://bdgom73.github.io/TIL`

### 수동 배포
```bash
# 빌드
bundle exec jekyll build

# _site/ 디렉토리의 내용을 웹 서버에 업로드
```

## 🎨 커스터마이징

### 테마 변경
`_config.yml`에서 `remote_theme` 설정을 수정

### 색상 변경
CSS 변수를 수정하여 색상 테마 변경 가능

### 사이드바 수정
`_includes/` 디렉토리의 파일들을 수정하여 사이드바 커스터마이징

## 📚 유용한 링크

- [Jekyll 공식 문서](https://jekyllrb.com/)
- [Minimal Mistakes 테마](https://mmistakes.github.io/minimal-mistakes/)
- [GitHub Pages](https://pages.github.com/)
- [Markdown 가이드](https://www.markdownguide.org/)

## 🤝 기여하기

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 `LICENSE` 파일을 참조하세요.

## 📞 연락처

- **이름**: Gom
- **이메일**: bdgom73@naver.com
- **GitHub**: [@bdgom73](https://github.com/bdgom73)

---

⭐ 이 프로젝트가 도움이 되었다면 스타를 눌러주세요! 