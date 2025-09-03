---
title: "Spring의 심장, IoC와 DI는 왜 쓸까?"
date: 2025-09-01
categories: [Spring]
tags: [Spring, IoC, DI]
excerpt: "오늘은 매일 당연하게 사용하던 `@Autowired`가 과연 무엇이고, Spring 프레임-워크의 핵심 철학이라는 **IoC(Inversion of Control)**와 **DI(Dependency Injection)**가 왜 필요한지에 대해 근본적인 질문을 던져보았다."
author_profile: true
---

# [TIL] Spring의 심장, IoC와 DI는 왜 쓸까?

오늘은 매일 당연하게 사용하던 `@Autowired`가 과연 무엇이고, Spring 프레임-워크의 핵심 철학이라는 **IoC(Inversion of Control)**와 **DI(Dependency Injection)**가 왜 필요한지에 대해 근본적인 질문을 던져보았다.

---

## 1. '제어'가 역전되기 전의 세상 😥

Spring이 없던 시절, 또는 이 개념을 적용하지 않았을 때의 코드를 상상해 봤다.

```java
public class MemberController {
    // Controller가 Service 객체를 직접 생성하고 제어한다.
    private MemberService memberService = new MemberServiceImpl();
    
    // ...
}
```

위 코드에는 심각한 문제가 있다.
* **강한 결합도 (Tight Coupling)**: `MemberController`는 `MemberServiceImpl`이라는 구체적인 구현 클래스에 직접 의존한다. 만약 `NewMemberServiceImpl`로 구현체를 바꿔야 한다면, `MemberController`의 코드를 직접 수정해야만 한다.
* **테스트의 어려움**: 단위 테스트 시 `MemberService`를 가짜 객체(Mock)로 대체하기가 매우 까다롭다. 진짜 `MemberServiceImpl`을 사용할 수밖에 없다.
* **SOLID 원칙 위배**: 특히 의존관계 역전 원칙(DIP)을 위배한다. `MemberController`라는 상위 모듈이 `MemberServiceImpl`이라는 하위 모듈에 의존하고 있다.

---

## 2. 패러다임의 전환: IoC (제어의 역전) 🔄

**IoC (Inversion of Control, 제어의 역전)**는 이 문제에 대한 해결 철학이다.

* **What I Learned**: 객체의 생성, 관리, 연결 등 모든 **제어권**을 개발자가 아닌 **프레임워크(Spring Container)에게 넘기는 것**을 의미한다.
* **핵심 비유**: 내가 필요한 부품(객체)을 직접 만드는 게 아니라, 거대한 부품 공장(Spring Container)에 "나 이런 부품이 필요해!"라고 **요청**만 하면, 공장이 알아서 만들어서 가져다주는 것과 같다. 객체에 대한 제어권이 나에게서 공장으로 역전된 것이다.

---

## 3. 그래서 '어떻게' 하는데?: DI (의존성 주입) 💉

**DI (Dependency Injection, 의존성 주입)**는 IoC라는 철학을 실제로 구현하는 **핵심 기술**이다.

* **What I Learned**: 클래스 내부에서 직접 의존 객체를 생성하는 것이 아니라, 외부(Spring Container)에서 **이미 만들어진 객체를 주입**받아 사용하는 방식이다.
* **의존성 주입의 종류**:
    1.  **생성자 주입 (Constructor Injection)**: **Spring이 가장 권장하는 방식.**
    2.  필드 주입 (Field Injection): `@Autowired`
    3.  수정자 주입 (Setter Injection)

### 왜 생성자 주입을 써야 할까?

오늘 학습하며 가장 중요하다고 생각한 부분이다. 필드 주입(`@Autowired`)이 편해 보이지만, 생성자 주입을 써야 하는 명확한 이유가 있었다.

* **불변성(Immutability) 보장**: 생성자에서 주입받은 의존관계는 `final` 키워드를 붙여서 변경 불가능하게 만들 수 있다.
* **의존성 누락 방지**: 객체가 생성되는 시점에 모든 의존성이 주입되어야 하므로, `NullPointerException`을 원천적으로 방지할 수 있다.
* **순환 참조 감지**: 의존하는 Bean들이 서로를 물고 늘어지는 '순환 참조'가 발생했을 때, 애플리케이션 실행 시점에 바로 에러를 발생시켜 문제를 빠르게 인지할 수 있다.

```java
@RestController
public class MemberController {
    
    private final MemberService memberService; // final 키워드 사용 가능

    // 생성자가 하나일 경우 @Autowired 생략 가능
    public MemberController(MemberService memberService) {
        this.memberService = memberService;
    }
}
```
---

## 오늘의 결론

IoC와 DI는 단순히 코드를 몇 줄 줄여주는 편의 기능이 아니었다. **객체 지향의 핵심인 느슨한 결합(Loose Coupling)을 가능하게 하여, 유연하고 테스트하기 쉬운 코드를 만들도록 돕는 Spring의 근본 철학**임을 깨달았다. 앞으로는 무심코 `@Autowired`를 사용하기보다, 생성자 주입을 통해 의존관계를 명확히 드러내는 습관을 들여야겠다.
