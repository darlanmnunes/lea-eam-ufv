import { useEffect, useRef, type HTMLAttributes, type PointerEvent } from 'react'

/**
 * Luz suave que acompanha o ponteiro dentro de um cartão e acende a borda mais próxima.
 * Adaptado do componente "Spotlight" de kevingirelli no 21st.dev: só atualiza duas
 * variáveis CSS por quadro, sem re-renderizar. Em tela de toque não faz nada.
 */
export function Holofote({ className = '', children, onPointerMove, ...props }: HTMLAttributes<HTMLLIElement>) {
  const quadro = useRef(0)
  useEffect(() => () => cancelAnimationFrame(quadro.current), [])

  const mover = (e: PointerEvent<HTMLLIElement>) => {
    onPointerMove?.(e)
    if (e.pointerType === 'touch') return
    const alvo = e.currentTarget
    const { clientX, clientY } = e
    cancelAnimationFrame(quadro.current)
    quadro.current = requestAnimationFrame(() => {
      const r = alvo.getBoundingClientRect()
      alvo.style.setProperty('--luz-x', `${clientX - r.left}px`)
      alvo.style.setProperty('--luz-y', `${clientY - r.top}px`)
    })
  }

  return (
    <li className={`holofote ${className}`} onPointerMove={mover} {...props}>
      <span className="holofote-luz" aria-hidden="true" />
      <span className="holofote-borda" aria-hidden="true" />
      {children}
    </li>
  )
}
