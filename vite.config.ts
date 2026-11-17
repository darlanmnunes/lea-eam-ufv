import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'node:path'

// base relativa: o mesmo build serve em darlanmnunes.github.io/<repo>/ e em domínio próprio.
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        inicio: resolve(import.meta.dirname, 'index.html'),
        acervo: resolve(import.meta.dirname, 'acervo.html'),
      },
    },
  },
})
