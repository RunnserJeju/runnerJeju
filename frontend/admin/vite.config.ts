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
      '/admin': 'http://localhost:8000',
    },
  },
})
