---
title: "Pinpoint APM Docker로 올리면서 놓쳤던 것들"
date: 2026-03-10
categories: [APM, DevOps]
tags: [Pinpoint, Docker, HBase, Spring Boot, APM, TIL]
excerpt: "공식 이미지 쓰면 쉽게 올라갈 줄 알았다. Zookeeper 하드코딩, curl 없는 이미지, localhost로 박힌 기본값, 그리고 설정 파일을 고쳤는데 적용이 안 되는 샘플링 레이트까지. 알고 나면 별거 아닌데, 모르면 계속 엉뚱한 곳을 본다."
author_profile: true
---

## 배경

서비스가 간헐적으로 느려지는데 로그에는 아무것도 없었다. 특정 API인지, DB인지, 외부 호출인지 구분이 안 됐다. 추측으로 디버깅하는 데 한계가 와서 APM 도입을 결정했다.

Pinpoint를 선택한 건 코드 수정이 필요 없어서다. JVM 옵션에 `-javaagent`만 추가하면 Call Stack, DB 쿼리, 외부 API 호출까지 자동으로 잡힌다. 운영 중인 서비스에 붙여야 하는 상황에서 코드 변경 없이 붙일 수 있다는 게 결정적이었다.

구성은 간단하게 잡았다. Pinpoint 인프라(Collector, Web, HBase 등)는 Docker Compose, Agent는 모니터링 대상 서버에 직접 설치. 버전은 3.0.4.

---

## 직접 빌드는 포기하고 공식 이미지로 갔다

처음엔 Dockerfile 직접 만들었다. HBase 설정이랑 Zookeeper 연결 타이밍이 얽히면서 수습이 안 됐다. `pinpointdocker` 공식 이미지로 전환했더니 바로 안정화됐다.

근데 공식 이미지라고 그냥 올라오진 않았다. 이미지 안에 뭐가 박혀있는지 모르면 계속 막힌다.

---

## Zookeeper 3개짜리 이미지를 1개로 쓰기

공식 예제가 Zookeeper를 zoo1, zoo2, zoo3 세 개로 구성한다. `pinpointdocker/pinpoint-hbase` 이미지 내부에도 이 세 개가 하드코딩되어 있다.

로컬 테스트에 Zookeeper 3개는 부담이다. 이미지를 다시 빌드하지 않고 설정을 바꾸는 방법은 `hbase-site.xml`을 볼륨으로 덮어쓰는 것이다.

```xml
<!-- hbase/hbase-site.xml -->
<property>
  <name>hbase.zookeeper.quorum</name>
  <value>zoo1</value>
</property>
```

```yaml
pinpoint-hbase:
  image: pinpointdocker/pinpoint-hbase:3.0.4
  volumes:
    - ./hbase/hbase-site.xml:/opt/hbase/hbase-2.2.6/conf/hbase-site.xml:ro
```

이미지 내부 파일을 읽기 전용 볼륨으로 교체하는 방식이라 이미지는 손대지 않아도 된다.

---

## healthcheck에서 예상 못한 곳에서 막혔다

`depends_on`으로 의존 관계를 걸면 healthcheck가 통과해야 다음 컨테이너가 뜬다. 공식 이미지들에 curl, nc 같은 기본 도구가 없어서 흔히 쓰는 방법들이 다 막혔다.

각각 다른 방식으로 우회했다.

**Zookeeper** — nc가 없어서 `echo ruok | nc` 불가. 대신 이미지에 포함된 zkServer.sh를 활용했다.

```yaml
test: ["CMD-SHELL", "zkServer.sh status 2>&1 | grep -qE 'leader|follower|standalone'"]
```

**HBase** — `hbase status` 출력이 실행마다 달라서 grep이 불안정했다. Master Web UI 엔드포인트가 더 신뢰할 수 있었다.

```yaml
test: ["CMD-SHELL", "curl -sf http://localhost:16010/master-status || exit 1"]
```

**Collector** — curl도 wget도 없었다. bash의 `/dev/tcp`로 TCP 연결 자체를 확인했다.

```yaml
test: ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/8081' 2>/dev/null || exit 1"]
```

---

## 공식 이미지 기본값이 로컬 기준으로 박혀있다

컨테이너가 다 올라왔는데 이번엔 서비스끼리 연결이 안 됐다. 공식 이미지 기본값이 로컬 개발 환경 기준으로 고정된 경우가 있어서, Docker 네트워크 환경에선 환경변수로 전부 덮어줘야 한다.

**Collector → Redis**: 기본값이 `localhost:6379`라 컨테이너 이름으로 바꿔줬다.

```yaml
pinpoint-collector:
  environment:
    SPRING_DATA_REDIS_HOST: redis
```

**Web → MySQL**: `localhost:13306`으로 찾고 있었다. JDBC URL을 두 군데 모두 바꿔야 한다. 하나만 바꾸면 여전히 에러 난다.

```yaml
pinpoint-web:
  environment:
    SPRING_DATASOURCE_HIKARI_JDBC_URL: jdbc:mysql://pinpoint-mysql:3306/pinpoint?characterEncoding=UTF-8
    SPRING_META_DATASOURCE_HIKARI_JDBC_URL: jdbc:mysql://pinpoint-mysql:3306/pinpoint?characterEncoding=UTF-8
```

**OTLP AutoConfiguration 충돌**: Pinpoint 이미지에 OTLP 의존성이 없는데 Spring Boot가 AutoConfiguration을 활성화하려다 터진다.

```
ClassNotFoundException: io.micrometer.registry.otlp.OtlpMeterRegistry$Builder
```

```yaml
environment:
  SPRING_AUTOCONFIGURE_EXCLUDE: >-
    org.springframework.boot.actuate.autoconfigure.metrics.export.otlp.OtlpMetricsExportAutoConfiguration
```

**MySQL 스키마**: Pinpoint가 필요로 하는 테이블이 수십 개다. 직접 init SQL 작성하다가 포기하고 `pinpointdocker/pinpoint-mysql:latest` 공식 이미지로 바꿨다. 컨테이너 뜰 때 자동으로 초기화해준다. 버전 태그는 없고 `latest`만 있다.

---

## 최종 docker-compose.yml

```yaml
x-tz: &tz
  TZ: Asia/Seoul

services:
  zoo1:
    image: zookeeper:3.8
    environment:
      <<: *tz
      ZOO_MY_ID: 1

  pinpoint-hbase:
    image: pinpointdocker/pinpoint-hbase:3.0.4
    volumes:
      - ./hbase/hbase-site.xml:/opt/hbase/hbase-2.2.6/conf/hbase-site.xml:ro
    depends_on:
      zoo1:
        condition: service_healthy

  pinpoint-mysql:
    image: pinpointdocker/pinpoint-mysql:latest
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}

  redis:
    image: redis:7.0

  pinpoint-collector:
    image: pinpointdocker/pinpoint-collector:3.0.4
    environment:
      SPRING_DATA_REDIS_HOST: redis
      SPRING_AUTOCONFIGURE_EXCLUDE: >-
        org.springframework.boot.actuate.autoconfigure.metrics.export.otlp.OtlpMetricsExportAutoConfiguration
    depends_on:
      pinpoint-hbase:
        condition: service_healthy

  pinpoint-web:
    image: pinpointdocker/pinpoint-web:3.0.4
    environment:
      SPRING_DATASOURCE_HIKARI_JDBC_URL: jdbc:mysql://pinpoint-mysql:3306/pinpoint?characterEncoding=UTF-8
      SPRING_META_DATASOURCE_HIKARI_JDBC_URL: jdbc:mysql://pinpoint-mysql:3306/pinpoint?characterEncoding=UTF-8
    ports:
      - "8083:8080"
```

`x-tz: &tz`로 시간대 설정을 YAML anchor로 묶었다. 각 서비스에 `<<: *tz`로 주입하면 TZ 하나만 바꿔도 전체에 반영된다.

---

## Agent 설치

Agent는 Docker 내부가 아니라 모니터링 대상 서버에 직접 설치한다. GitHub Releases에서 받아서 압축 풀면 된다.

로컬 테스트용 실행 스크립트:

```bat
@echo off
cd /d %~dp0
java ^
  -javaagent:./pinpoint-agent/pinpoint-bootstrap-3.0.4.jar ^
  -Dpinpoint.agentId=my-test-agent ^
  -Dpinpoint.applicationName=my-test-app ^
  -Dpinpoint.profiler.profiles.active=release ^
  -Dspring.profiles.active=local ^
  -Dfile.encoding=UTF-8 ^
  -Duser.timezone=Asia/Seoul ^
  -jar my-app.jar
pause
```

Collector 주소는 `pinpoint-root.config`에서 지정한다.

```properties
profiler.transport.grpc.collector.ip=127.0.0.1
```

---

## 가장 오래 헤맸던 부분 — 샘플링 레이트

인프라 다 올리고 요청 10개를 보냈는데 Server Map에 1개밖에 안 찍혔다. Collector 연결은 정상, Agent 상태도 READY인데 데이터가 거의 안 들어왔다.

처음엔 Collector 문제라고 생각했다. 로그 다 뒤져봤는데 연결 자체는 문제없었다. 그러다 Agent 로그에서 이 줄을 발견했다.

```
CountingSamplerFactory.Config:Config{samplingRate=20}
```

`pinpoint-root.config`에 `sampling-rate=1`로 설정했는데 실제로는 20으로 동작하고 있었다. 20건 중 1건만 트레이싱한다는 뜻이니, 요청 10개 보내면 0~1개밖에 안 잡히는 게 맞다.

원인은 `-Dpinpoint.profiler.profiles.active=release` 옵션이었다. **이 옵션이 있으면 `pinpoint-root.config`가 아니라 `profiles/release/pinpoint.config`가 우선 적용된다.** release 프로파일의 기본값이 `sampling-rate=20`이었던 것.

`pinpoint-root.config`를 고쳤는데 왜 적용이 안 되지 하고 한참 헤맸는데, 프로파일을 지정하면 해당 프로파일 설정 파일을 직접 봐야 한다는 걸 몰랐던 게 문제였다.

```properties
# profiles/release/pinpoint.config 를 직접 수정
profiler.sampling.counting.sampling-rate=1
```

COUNTING 방식은 1/n 비율이다. 운영에서는 트래픽에 맞게 조정하면 된다.

| 값 | 비율 | 적합한 상황 |
|---|---|---|
| 1 | 100% | 개발, 저트래픽 |
| 10 | 10% | 중간 규모 |
| 20 | 5% | release 기본값, 고트래픽 |

---

## 리소스

zoo1 + HBase + Collector + Web + MySQL + Redis 합치면 최소 3~4GB는 필요하다. Docker Desktop에서 돌린다면 메모리 설정부터 확인하고 시작하는 게 맞다.

HBase 올라오는 데 시간이 꽤 걸린다. 그냥 기다리면 된다. healthcheck가 통과하기 전까지 다음 컨테이너는 뜨지 않는 구조라, 터미널이 멈춰 보여도 죽은 게 아니다.
