---
title: "JWT 인증의 완성: Refresh Token을 활용한 똑똑한 세션 관리"
date: 2025-10-12
categories: [Spring, Security]
tags: [Spring Security, JWT, Refresh Token, Authentication, Authorization, TIL]
excerpt: "Stateless JWT 인증 방식에서 Access Token만 사용할 때 발생하는 보안과 편의성의 트레이드오프 문제를 분석합니다. Refresh Token을 도입하여 두 마리 토끼를 모두 잡는 세션 관리 전략과 그 안전한 구현 방법에 대해 심층적으로 학습합니다."
author_profile: true
---

# Today I Learned: JWT 인증의 완성: Refresh Token을 활용한 똑똑한 세션 관리

## 📚 오늘 학습한 내용

어제에 이어 JWT 인증 시스템에 대해 더 깊이 파고들었습니다. 특히 Access Token만으로는 해결하기 어려운 **'보안'과 '사용자 편의성'이라는 두 가지 상충하는 목표**를 어떻게 조화시킬 수 있는지에 초점을 맞추었습니다. 그 해답은 바로 **Refresh Token**을 도입하여 두 토큰의 역할을 명확히 분리하는 것에 있었습니다.

---

### 1. **문제 정의: 놀이공원의 자유이용권 (Access Token)**

JWT의 **Access Token**은 놀이공원의 '자유이용권'과 같습니다. 이 티켓만 있으면 유효 시간 동안 모든 놀이기구를 마음껏 탈 수 있습니다. 서버는 매번 티켓의 유효 기간만 확인할 뿐, 이 티켓을 누가 가지고 있는지 일일이 추적하지 않습니다 (Stateless).

-   **편리함**: 서버가 사용자의 상태를 기억할 필요가 없어 확장성이 뛰어납니다.
-   **딜레마**:
    -   만약 **유효 기간이 8시간**인 자유이용권을 잃어버린다면? 주운 사람은 8시간 동안 공짜로 놀이기구를 탈 수 있습니다. (토큰 탈취 시 보안 위협)
    -   만약 **유효 기간이 10분**이라면? 10분마다 매표소에 가서 신분증을 보여주고 티켓을 재발급받아야 합니다. (잦은 재로그인으로 인한 최악의 사용자 경험)

이처럼 Access Token의 유효 기간 설정은 보안과 편의성 사이의 고통스러운 트레이드오프를 야기합니다.

---

### 2. **해결책: 보관소 열쇠 (Refresh Token)의 도입**

이 문제를 해결하기 위해 '자유이용권'과 별개로 **'개인 보관소 열쇠(Refresh Token)'**를 추가로 발급하는 전략을 사용합니다.

-   **자유이용권 (Access Token)**
    -   **역할**: 놀이기구 탑승 (API 리소스 접근)
    -   **유효 기간**: **15분** (매우 짧게 설정하여 탈취 위험 최소화)

-   **개인 보관소 열쇠 (Refresh Token)**
    -   **역할**: 자유이용권이 만료됐을 때, 매표소에 가서 **새 자유이용권을 발급받는 용도**
    -   **유효 기간**: **7일** (길게 설정하여 사용자 편의성 보장)
    -   **특징**: 이 열쇠만으로는 놀이기구를 탈 수 없습니다.

#### **개선된 인증 흐름**

1.  **입장**: 사용자가 로그인하면, 서버는 짧은 수명의 **Access Token**과 긴 수명의 **Refresh Token**을 함께 발급합니다.
2.  **놀이기구 탑승**: 사용자는 15분간 Access Token으로 자유롭게 API를 호출합니다.
3.  **이용권 만료**: 15분이 지나 Access Token이 만료되면, API 서버는 `401 Unauthorized` 에러를 반환합니다.
4.  **재발급 요청**: 클라이언트는 이 에러를 감지하고, 보관하고 있던 **Refresh Token(보관소 열쇠)**을 재발급 전용 창구(`/api/token/refresh`)에 제시합니다.
5.  **신원 확인 및 재발급**: 서버는 **"이 열쇠가 우리가 발급한 것이 맞고, 여전히 유효한가?"**를 확인합니다. 이 과정이 성공하면, 새로운 15분짜리 **Access Token**을 발급해줍니다.
6.  **다시 탑승**: 클라이언트는 새로 받은 Access Token으로 아까 실패했던 API를 다시 호출합니다. 사용자는 재로그인 없이 서비스를 계속 이용할 수 있습니다.



---

### 3. **가장 중요한 것: Refresh Token은 반드시 서버가 기억해야 한다**

Refresh Token 전략의 핵심 보안 요건은 **서버가 발급한 모든 Refresh Token을 저장하고 추적**하는 것입니다.

-   **왜?**: 만약 Refresh Token이 탈취당했을 때, 서버가 그 토큰을 강제로 무효화할 수 있어야 하기 때문입니다. 서버에 저장된 Refresh Token 목록에서 해당 토큰을 삭제하면, 공격자는 더 이상 새로운 Access Token을 발급받을 수 없습니다.
-   **구현**:
    -   사용자 로그인 시 Refresh Token을 생성하여 클라이언트에 보내는 동시에, 해당 토큰을 **DB나 Redis**에 `(사용자 ID, Refresh Token)` 형태로 저장합니다.
    -   토큰 재발급 요청이 오면, 클라이언트가 보낸 Refresh Token이 우리 DB에 저장된 값과 일치하는지 반드시 확인합니다.
    -   사용자가 로그아웃하면, DB에서 해당 Refresh Token을 삭제하여 세션을 즉시 종료시킵니다.

```java
// 재발급 로직의 핵심 (개념 코드)
public TokenInfo reissue(String refreshToken) {
    // 1. 토큰 자체의 유효성 검증 (만료일, 서명 등)
    validateToken(refreshToken);

    // 2. 서버 저장소에 해당 토큰이 존재하는지, 유효한지 확인
    RefreshToken storedToken = refreshTokenRepository.findByToken(refreshToken)
        .orElseThrow(() -> new SecurityException("Invalid or expired refresh token."));

    // 3. 검증 완료. 새로운 토큰 쌍 발급
    String userId = storedToken.getUserId();
    String newAccessToken = createAccessToken(userId);
    String newRefreshToken = createRefreshToken(); // RTR(Refresh Token Rotation) 적용 시

    // 4. 새로운 Refresh Token으로 저장소 업데이트
    storedToken.updateToken(newRefreshToken);
    refreshTokenRepository.save(storedToken);

    return new TokenInfo(newAccessToken, newRefreshToken);
}
```

---

## 💡 배운 점

1.  **역할의 분리**: Access Token은 '인증'을 위한 소모성 티켓, Refresh Token은 '인증 갱신'을 위한 장기적인 신분 증명서로 역할을 명확히 분리하는 것이 핵심임을 이해했습니다.
2.  **Stateless의 함정**: JWT는 Stateless 통신을 가능하게 하지만, 완벽한 보안을 위해서는 Refresh Token의 유효성을 검증하는 'Stateful'한 메커니즘이 서버 측에 반드시 필요합니다. '모든 것을 Stateless로 해야 한다'는 강박에서 벗어나, 상황에 맞게 상태를 관리하는 것이 중요합니다.
3.  **사용자 경험과 보안은 함께 간다**: Refresh Token 전략은 보안을 강화하면서도(Access Token 탈취 시 피해 최소화) 사용자에게는 재로그인의 불편함을 주지 않는, 두 마리 토끼를 모두 잡는 매우 실용적이고 성숙한 해결책임을 깨달았습니다.

---

## 🔗 참고 자료

-   [JWT.io - Introduction to JSON Web Tokens](https://jwt.io/introduction)
-   [Stop using JWT for sessions (joepie91's blog)](https://joepie91.medium.com/stop-using-jwt-for-sessions-5969242a4933)
-   [Refreshing JWTs with a Refresh Token (Baeldung)](https://www.baeldung.com/spring-security-oauth-refresh-token)