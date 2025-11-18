---
title: "AWS S3 Presigned URL을 활용한 안전하고 효율적인 파일 업로드/다운로드"
date: 2025-11-18
categories: [DevOps, AWS]
tags: [AWS S3, Presigned URL, Spring Boot, File Upload, DevOps, Security, TIL]
excerpt: "서버가 사용자의 파일 업로드/다운로드를 중개(Proxy)할 때 발생하는 트래픽 병목 현상을 학습합니다. AWS S3 Presigned URL을 생성하여, 클라이언트가 S3와 직접 통신하게 함으로써 서버 부하를 줄이고 보안을 강화하는 방법을 알아봅니다."
author_profile: true
---

# Today I Learned: AWS S3 Presigned URL을 활용한 안전하고 효율적인 파일 업로드/다운로드

## 📚 오늘 학습한 내용

Spring Boot 서버를 개발할 때, 이미지나 파일 업로드/다운로드 기능은 흔한 요구사항입니다. 저는 S3 버킷을 **비공개(Private)**로 설정하고, 서버가 파일을 받아 S3로 전달(Proxying)하는 방식을 사용해왔습니다.

-   **기존 방식의 문제점**:
    1.  **서버 트래픽 병목**: 클라이언트 ➡️ **서버** ➡️ S3. 모든 대용량 파일이 서버를 거쳐가기 때문에, 서버의 네트워크 대역폭과 메모리를 심각하게 소모합니다.
    2.  **느린 속도**: 사용자는 불필요하게 서버를 한 번 더 거치므로 업로드/다운로드 속도가 느려집니다.
    3.  **구현 복잡성**: 대용량 파일을 처리하기 위해 `multipart/form-data`를 파싱하는 로직이 복잡합니다.

오늘은 이 문제를 해결하기 위해, S3 버킷은 비공개로 유지하면서 클라이언트가 **S3와 직접 통신**할 수 있도록 허용하는 **Presigned URL(미리 서명된 URL)**에 대해 학습했습니다.

---

### 1. **Presigned URL이란 무엇인가? 🔑**

**Presigned URL**은 S3의 비공개 객체(Object)에 대해, **제한된 시간** 동안만 **특정 작업(GET, PUT 등)**을 수행할 수 있도록 허용하는 **임시 URL**입니다.

-   **핵심 원리**:
    1.  백엔드 서버는 AWS 자격증명(Access Key, Secret Key)을 가지고 있습니다. (클라이언트는 모름)
    2.  클라이언트가 파일 업로드/다운로드를 요청합니다.
    3.  백엔드 서버는 S3 SDK를 사용하여 "이 파일에 대해 10분간 PUT(업로드) 권한을 부여한다"는 내용이 담긴 **서명된 URL(Presigned URL)**을 생성하여 클라이언트에게 응답합니다.
    4.  클라이언트는 이 URL을 받아, 서버를 거치지 않고 **S3로 직접** `PUT` 요청을 보냅니다. S3는 이 URL의 서명을 검증하고 업로드를 허용합니다.



---

### 2. **Spring Boot (AWS SDK v2)로 Presigned URL 생성하기**

#### **1. `build.gradle` 의존성 추가**
AWS S3 SDK v2와 Presigner가 필요합니다.
```groovy
implementation platform('software.amazon.awssdk:bom:2.25.14') // AWS SDK BOM
implementation 'software.amazon.awssdk:s3'
implementation 'software.amazon.awssdk:s3-transfer-manager' // (선택) 고수준 관리
```
> **(주의)** `aws-java-sdk-s3` (v1)가 아닌 `software.amazon.awssdk:s3` (v2) 의존성을 사용해야 합니다. Presigner 설정이 v2에서 크게 변경되었습니다.

#### **2. S3 클라이언트 빈 설정**
`S3Client`와 `S3Presigner`를 빈으로 등록합니다.
```java
@Configuration
public class AwsS3Config {

    @Value("${aws.region}")
    private String region;

    @Value("${aws.credentials.access-key}")
    private String accessKey;
    
    @Value("${aws.credentials.secret-key}")
    private String secretKey;

    @Bean
    public S3Client s3Client() {
        AwsBasicCredentials credentials = AwsBasicCredentials.create(accessKey, secretKey);
        return S3Client.builder()
                .region(Region.of(region))
                .credentialsProvider(StaticCredentialsProvider.create(credentials))
                .build();
    }

    // Presigned URL 생성을 위한 전용 클라이언트
    @Bean
    public S3Presigner s3Presigner() {
        AwsBasicCredentials credentials = AwsBasicCredentials.create(accessKey, secretKey);
        return S3Presigner.builder()
                .region(Region.of(region))
                .credentialsProvider(StaticCredentialsProvider.create(credentials))
                .build();
    }
}
```

#### **3. Presigned URL 생성 서비스 구현**

**① 파일 업로드 (PUT) URL 생성**
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class FileUploadService {

    private final S3Presigner s3Presigner;

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    /**
     * 클라이언트가 파일을 업로드(PUT)할 수 있는 Presigned URL을 생성
     */
    public String generatePresignedUploadUrl(String objectKey, String contentType) {
        try {
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(bucketName)
                    .key(objectKey) // "uploads/images/my-image.jpg"
                    .contentType(contentType) // "image/jpeg"
                    .build();

            PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                    .signatureDuration(Duration.ofMinutes(10)) // 1. 10분간 유효
                    .putObjectRequest(putObjectRequest)
                    .build();

            PresignedPutObjectRequest presignedUrl = s3Presigner.presignPutObject(presignRequest);
            
            log.info("Generated PUT URL: {}", presignedUrl.url().toString());
            return presignedUrl.url().toString();

        } catch (S3Exception e) {
            log.error("Error generating presigned URL for PUT", e);
            throw new RuntimeException(e);
        }
    }

    /**
     * 클라이언트가 파일을 다운로드(GET)할 수 있는 Presigned URL을 생성
     */
    public String generatePresignedDownloadUrl(String objectKey) {
        // ... (GetObjectRequest, GetObjectPresignRequest 사용) ...
    }
}
```

---

### 4. **클라이언트(Frontend)의 역할**

이제 프론트엔드(e.g., JavaScript)의 역할이 중요해집니다.

1.  파일 업로드 버튼 클릭 시, 먼저 **우리 백엔드 서버(`/api/files/presigned-url?filename=...`)**를 호출하여 위에서 만든 `Presigned URL`을 받아옵니다.
2.  받아온 URL을 `action` 주소로 하여, `fetch`나 `axios`를 사용해 `PUT` 메서드로 **실제 파일 데이터(Binary)**를 S3로 직접 전송합니다.

```javascript
// Frontend (JavaScript) Example
async function uploadFile(file) {
    // 1. 우리 서버에 Presigned URL 요청
    const response = await fetch(`/api/files/presigned-url?filename=${file.name}&contentType=${file.type}`);
    const { presignedUrl } = await response.json();

    // 2. S3로 파일 직접 PUT 요청 (서버를 거치지 않음!)
    const uploadResponse = await fetch(presignedUrl, {
        method: 'PUT',
        body: file,
        headers: {
            'Content-Type': file.type
        }
    });

    if (uploadResponse.ok) {
        console.log("Upload Success!");
        // 3. (선택) 업로드 완료 사실을 우리 서버에 다시 알림
        // await fetch(`/api/files/upload-complete?filename=${file.name}`);
    }
}
```

---

## 💡 배운 점

1.  **서버 트래픽을 오프로딩(Offloading)하라**: 이 아키텍처의 핵심은 S3의 리소스를 사용하면서, 그로 인한 트래픽 부담(비용)은 클라이언트에게 넘기는 것입니다. 이는 서버 리소스를 핵심 비즈니스 로직 처리에만 집중할 수 있게 하여, 시스템 전체의 확장성과 비용 효율성을 극대화합니다.
2.  **보안은 타협하지 않는다**: S3 버킷을 `public-read`로 열어두는 것은 가장 쉽지만 위험한 방법입니다. Presigned URL을 사용하면 버킷을 비공개로 유지하면서, **'누가'(서명 검증), '무엇을'(objectKey), '어떻게'(GET/PUT), '얼마나'(Duration)** 접근할 수 있는지 100% 제어할 수 있습니다.
3.  **백엔드의 역할 변화**: 모든 것을 중개하던 중앙 집중형 백엔드에서, 권한을 발급하고 흐름을 제어하는 '교통 경찰' 역할의 백엔드로 역할이 변화하고 있음을 깨달았습니다. 이는 3~4년차 개발자로서 가져야 할 중요한 아키텍처 설계 관점입니다.

---

## 🔗 참고 자료

-   [AWS SDK for Java 2.x - S3 Presigner](https://sdk.amazonaws.com/java/api/latest/software/amazon/awssdk/services/s3/presigner/S3Presigner.html)
-   [Amazon S3 Presigned URLs (Official Docs)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html)
-   [S3 Presigned URLs with Spring Boot (Baeldung)](https://www.baeldung.com/aws-s3-presigned-urls-spring)