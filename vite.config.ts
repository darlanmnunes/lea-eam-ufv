import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'node:path'

// base relativa: o mesmo build serve em darlanmnunes.github.io/<repo>/ e em domínio próprio.
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    assetsDir: 'app',
    rollupOptions: {
      input: {
        acervo: resolve(import.meta.dirname, 'acervo.html'),
      },
    },
  },
})
