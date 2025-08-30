---
title: 2025년 08월 29일 Today I Learned
date: 2025-08-29
categories:
  - Vercel
tags:
  - Serverless
  - 빌드 최적화
  - 캐시 관리
---

# Vercel 배포 시 Serverless Function 사이즈 초과 문제 해결하기

오늘 Next.js 프로젝트를 Vercel에 배포하던 중 빌드가 실패하는 이슈를 겪었습니다. 원인을 분석하고 해결하는 과정을 정리해 보았습니다.

### 문제 상황: Serverless Function 최대 용량 초과

배포 과정에서 다음과 같은 에러 로그와 함께 빌드가 중단되었습니다.

```text
Error: A Serverless Function has exceeded the unzipped maximum size of 250 MB.
```

Vercel의 공식 문서에 따르면, Serverless Function의 압축 해제 후 최대 크기는 **250MB**로 제한됩니다. 
이 용량에는 코드, 종속성 등 함수 실행에 필요한 모든 파일이 포함되며, 이 제한은 사용자가 변경할 수 없습니다.

**원인 분석: 빌드 캐시 포함**

배포 로그를 자세히 살펴보니, 불필요한 캐시 파일이 빌드 결과물에 포함되어 용량을 초과시킨 것이 원인이었습니다

```text
Large Dependencies           Uncompressed size
.next/cache/webpack                  412.14 MB
...
```

Next.js가 빌드 과정에서 생성하는 .next/cache 디렉토리 하나만으로 이미 400MB가 넘어, Vercel의 제한을 훌쩍 넘기고 있었습니다.

### ✅ 해결 과정

문제의 원인이 불필요한 캐시 파일이었으므로, 배포 번들에서 이 파일들을 제외하는 방식으로 문제를 해결했습니다. 

(기준: Next.js 15, `src/app` 구조)

#### 해결책 1: `vercel.json`으로 배포 파일 제외하기

Vercel은 `vercel.json` 설정 파일을 통해 배포에 포함하거나 제외할 파일을 직접 지정하는 기능을 제공합니다. 프로젝트 최상단에 `vercel.json` 파일을 생성하고 아래와 같이 작성했습니다.

`vercel.json`
```json
{
  "functions": {
    "src/app/api/**": {
      "excludeFiles": "{.next/cache,node_modules/.cache,tests,docs,scripts,tmp}/**"
    }
  }
}
```

#### 해결책 2: `next.config.js`로 빌드 추적에서 제외하기

Next.js 설정에서 특정 파일들을 빌드 시점의 파일 추적(File Tracing) 과정에서부터 제외하여, 근본적으로 빌드 결과물에 포함되지 않도록 설정했습니다.

`next.config.(js/ts)` 파일에 `outputFileTracingExcludes` 옵션을 추가했습니다.

`next.config.(js/ts)`
```js
const nextConfig = {
  // ... 기타 설정
  outputFileTracingExcludes: {
    '/': [
      '.next/cache/**',
      'node_modules/.cache/**',
      '.git/**',
    ],
  },
};

module.exports = nextConfig;
```

이 설정은 Next.js가 빌드를 진행할 때 `.git`, `.next/cache` 등 불필요한 디렉토리를 아예 추적 대상에서 제외하여 최종 번들 크기를 효과적으로 줄여줍니다.


#### 핵심 정리
Vercel과 같은 배포 플랫폼은 리소스 제한이 존재하므로, 배포 번들의 크기를 최적화하는 것이 중요합니다. 특히 `.next/cache`와 같이 용량이 큰 캐시 디렉토리가 배포에 포함되지 않도록 **vercel.json**과 **next.config.js**를 활용하여 명시적으로 제외하는 방법을 통해 문제를 해결할 수 있습니다.
