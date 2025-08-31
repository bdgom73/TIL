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
`글
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
  
---
