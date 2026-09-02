import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// base: FastAPI가 이 빌드를 /admin-ui 에서 서빙한다(server/app/main.py).
// proxy: 개발 서버에서 API 호출을 로컬 FastAPI(8000)로 넘긴다 — 운영과 같은
// 동일 오리진 상대경로 호출을 개발에서도 그대로 쓰기 위해서다.
export default defineConfig({
  plugins: [react()],
  base: '/admin-ui/',
  server: {
    proxy: {
      // '/admin'만 쓰면 prefix 매칭이라 /admin-ui(이 앱 자신)까지 FastAPI로
      // 넘어가 옛 빌드가 보인다 — /admin-ui는 제외한다.
      '^/admin(?!-ui)': 'http://localhost:8000',
    },
  },
})
