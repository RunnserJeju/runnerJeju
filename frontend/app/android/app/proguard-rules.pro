# 카카오맵 네이티브 SDK는 리플렉션으로 접근하는 클래스가 있어 난독화에서 제외한다.
# 이 규칙이 없으면 코드 축소를 켠 릴리즈 빌드에서만 지도가 뜨지 않는다.
-keep class com.kakao.vectormap.** { *; }
-keep interface com.kakao.vectormap.**
