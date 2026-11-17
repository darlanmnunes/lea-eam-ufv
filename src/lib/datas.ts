const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
const MESES_LONGOS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']

/** data local em AAAA-MM-DD */
export function hoje(deslocamento = 0): string {
  const d = new Date()
  d.setDate(d.getDate() + deslocamento)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function dia(iso: string): string {
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  const ano = a === new Date().getFullYear() ? '' : ` ${a}`
  return `${d} ${MESES[m - 1]}${ano}`
}

export function diaLongo(iso: string): string {
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  return `${d} de ${MESES_LONGOS[m - 1]} de ${a}`
}

export function diaHora(iso: string): string {
  const d = new Date(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} | ${p(d.getHours())}h${p(d.getMinutes())}`
}

export function periodo(de: string, ate: string): string {
  return de === ate ? dia(de) : `${dia(de)} a ${dia(ate)}`
}

export function diasEntre(de: string, ate: string): number {
  return Math.round((Date.parse(ate) - Date.parse(de)) / 86400000)
}

export function sobrepoe(de1: string, ate1: string, de2: string, ate2: string): boolean {
  return de1 <= ate2 && ate1 >= de2
}
