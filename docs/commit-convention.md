커밋 컨벤션은 작업 내용 잘 설명하기.. 




kakao map flutter 지원 사양  

Android  
- SDK 6.0 (API 23) 이상
- armeabi-v7a, arm64-v8a 아키텍쳐 지원
- (x86, x64 아키텍쳐 미호환)
- OpenGL ES 2.0 이상

성현우 컴퓨터에서는
    cd D:\RunnersJeju\runnerJeju\frontend\app
    flutter run -P target-platform=android-arm64 -P disable-abi-filtering=true
AMD64 ryzen cpu 이슈로 이렇게 arm64로 명시적으로 지정하여 실행 필요