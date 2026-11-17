// Monta src/dados/acervo.json a partir de:
//   dados-fonte/emprestimo_sala108.json  (planilha de controle de empréstimo; modelos com foto e descrição própria)
//   dados-fonte/patrimonio_sala108.json  (relação de patrimônio da sala 108)
// Uso: node scripts/montar-acervo.mjs && node scripts/gerar-sql-acervo.mjs
import { readFileSync, writeFileSync } from 'node:fs'

const ler = (p) => JSON.parse(readFileSync(new URL(`../${p}`, import.meta.url)))
const emprestimo = ler('dados-fonte/emprestimo_sala108.json')
const patrimonio = ler('dados-fonte/patrimonio_sala108.json')

const categorias = [
  { id: 'estacao-total', nome: 'Estações totais', sigla: 'ET' },
  { id: 'gnss', nome: 'Receptores GNSS e RTK', sigla: 'GN' },
  { id: 'nivel', nome: 'Níveis', sigla: 'NV' },
  { id: 'teodolito', nome: 'Teodolitos', sigla: 'TD' },
  { id: 'laser-scanner', nome: 'Laser scanner', sigla: 'LS' },
  { id: 'aeronave', nome: 'Drones e VANT', sigla: 'VT' },
  { id: 'medicao', nome: 'Bússolas e instrumentos de medição', sigla: 'MD' },
  { id: 'acessorio', nome: 'Miras, tripés e acessórios', sigla: 'AC' },
  { id: 'desenho', nome: 'Planímetros e desenho', sigla: 'DS' },
  { id: 'apoio', nome: 'Apoio de campo', sigla: 'AP' },
].map((c, i) => ({ ...c, ordem: i + 1 }))

// Modelos da planilha de empréstimo: nome, foto e descrição escritos à mão
const CURADOS = {
  'GEODETIC GD2I': { id: 'geodetic-gd2i', categoria: 'estacao-total', marca: 'Geodetic', nome: 'GD2i', foto: 'geodetic-gd2i.webp', descricao: 'Estação total das aulas práticas de Topografia. É o modelo com mais unidades no laboratório.' },
  'GEODETIC GT2+': { id: 'geodetic-gt2-plus', categoria: 'estacao-total', marca: 'Geodetic', nome: 'GT2+', foto: 'geodetic-gt2-plus.webp', descricao: 'Estação total para levantamento planialtimétrico e locação.' },
  'GEODETIC GD8I': { id: 'geodetic-gd8i', categoria: 'estacao-total', marca: 'Geodetic', nome: 'GD8i', foto: 'geodetic-gd8i.webp', descricao: 'Estação total para levantamento planialtimétrico e locação.' },
  'TOPCON 212': { id: 'topcon-gts-212', categoria: 'estacao-total', marca: 'Topcon', nome: 'GTS-212', foto: 'topcon-212.webp', descricao: 'Estação total para levantamento planialtimétrico e locação.' },
  'TOPCON 102N': { id: 'topcon-gts-102n', categoria: 'estacao-total', marca: 'Topcon', nome: 'GTS-102N', foto: 'topcon-102n.webp', descricao: 'Estação total para levantamento planialtimétrico e locação.' },
  'TOPCON ES 65': { id: 'topcon-es-65', categoria: 'estacao-total', marca: 'Topcon', nome: 'ES-65', foto: 'topcon-es-65.webp', descricao: 'Estação total para levantamento planialtimétrico e locação.' },
  'TOPOMAP T10': { id: 'topomap-t10', categoria: 'gnss', marca: 'Topomap', nome: 'T10', foto: 'rtk-topomap-t10.webp', descricao: 'Receptor GNSS para posicionamento RTK, usado em par como base e rover.' },
  'CHC NAV I50': { id: 'chc-i50', categoria: 'gnss', marca: 'CHC Nav', nome: 'i50', foto: 'chc-nav-i50.webp', descricao: 'Receptor GNSS para posicionamento RTK.' },
  'HI-TARGET V200': { id: 'hi-target-v200', categoria: 'gnss', marca: 'Hi-Target', nome: 'V200', foto: null, descricao: 'Receptor GNSS para posicionamento RTK.' },
  'TRIMPH-1': { id: 'javad-triumph-1', categoria: 'gnss', marca: 'Javad', nome: 'Triumph-1', foto: 'javad-trimph-1.webp', descricao: 'Receptor GNSS geodésico para rastreio estático e apoio de campo.' },
  'REACH RS2': { id: 'emlid-reach-rs2', categoria: 'gnss', marca: 'Emlid', nome: 'Reach RS2', foto: 'emild-reach-rs2.webp', descricao: 'Receptor GNSS multifrequência para posicionamento RTK.' },
  'REACH RS2+': { id: 'emlid-reach-rs2-plus', categoria: 'gnss', marca: 'Emlid', nome: 'Reach RS2+', foto: 'emilid-reach-rs2-plus.webp', descricao: 'Receptor GNSS multifrequência para posicionamento RTK.' },
  'TOPCON DL-502': { id: 'topcon-dl-502', categoria: 'nivel', marca: 'Topcon', nome: 'DL-502', foto: 'nivel-topcon-dl-502.webp', descricao: 'Nível digital para nivelamento geométrico.' },
  'RIEGL VZ 400': { id: 'riegl-vz-400', categoria: 'laser-scanner', marca: 'Riegl', nome: 'VZ-400', foto: 'riegl-vz-400.webp', descricao: 'Laser scanner terrestre para nuvens de pontos.' },
  'BATMAP II': { id: 'batmap-ii', categoria: 'aeronave', marca: 'Batmap', nome: 'II', foto: 'batmap-ii.webp', descricao: 'VANT de asa fixa para aerolevantamento.' },
  'DJI MAVIC AIR 2': { id: 'dji-mavic-air-2', categoria: 'aeronave', marca: 'DJI', nome: 'Mavic Air 2', foto: 'drone-dji-mavic-air-2.webp', descricao: 'Drone multirrotor para imagens aéreas.' },
  'BUFFALO BFG 2500': { id: 'buffalo-bfg-2500', categoria: 'apoio', marca: 'Buffalo', nome: 'BFG 2500', foto: 'gerador-buffalo-bfg-2500.webp', descricao: 'Gerador a gasolina para energia em campo.' },
  BOSCH: { id: 'bosch-martelete', categoria: 'apoio', marca: 'Bosch', nome: 'Martelete', foto: 'martelete-bosch.webp', descricao: 'Martelete perfurador e rompedor para implantação de marcos e pinos.' },
}

// Bens móveis: não entram no acervo
const MOBILIARIO = /^(ESTANTE|ARMARIO|CADEIRA|BANQUETA|DESUMIDIFICADOR)/

// O arquivo de patrimônio perdeu os acentos (caractere de substituição U+FFFD). Corrige as palavras que aparecem.
const X = '�'
const ACENTO = Object.fromEntries(Object.entries({
  [`ALUM${X}NIO`]: 'ALUMÍNIO', [`DURALUM${X}NIO`]: 'DURALUMÍNIO', [`TRIP${X}`]: 'TRIPÉ', [`${X}TICO`]: 'ÓPTICO',
  [`PROTE${X}${X}O`]: 'PROTEÇÃO', [`FIXA${X}AO`]: 'FIXAÇÃO', [`N${X}VEL`]: 'NÍVEL', [`TOPOGR${X}FICO`]: 'TOPOGRÁFICO',
  [`TOPOGR${X}FICA`]: 'TOPOGRÁFICA', [`APLICA${X}${X}O`]: 'APLICAÇÃO', [`CABE${X}A`]: 'CABEÇA', [`CABE${X}OTE`]: 'CABEÇOTE',
  [`HIDR${X}ULICA`]: 'HIDRÁULICA', [`R${X}PIDO`]: 'RÁPIDO', [`M${X}XIMA`]: 'MÁXIMA', [`ELETR${X}NICA`]: 'ELETRÔNICA',
  [`PE${X}AS`]: 'PEÇAS', [`CONSTRU${X}AO`]: 'CONSTRUÇÃO', [`ESTA${X}${X}O`]: 'ESTAÇÃO', [`CLIS${X}METRO`]: 'CLISÍMETRO',
  [`NIVELA${X}AO`]: 'NIVELAÇÃO', [`COMPENSA${X}${X}O`]: 'COMPENSAÇÃO', [`INSTRU${X}OES`]: 'INSTRUÇÕES',
  [`FOCALIZA${X}AO`]: 'FOCALIZAÇÃO', [`MET${X}LICA`]: 'METÁLICA', [`PRECIS${X}O`]: 'PRECISÃO', [`MEDI${X}${X}O`]: 'MEDIÇÃO',
  [`BAST${X}ES`]: 'BASTÕES', [`ESF${X}RICO`]: 'ESFÉRICO', [`GRADUA${X}${X}O`]: 'GRADUAÇÃO', [`SERVI${X}OS`]: 'SERVIÇOS',
  [`C${X}MERA`]: 'CÂMERA', [`ARM${X}RIO`]: 'ARMÁRIO', [`BRA${X}O`]: 'BRAÇO', [`P${X}S`]: 'PÉS', [`REFOR${X}ADOS`]: 'REFORÇADOS', [`SAT${X}LITES`]: 'SATÉLITES', "TRIP'C9": 'TRIPÉ',
  TOPOGRAFICO: 'TOPOGRÁFICO', TOPOGRAFICA: 'TOPOGRÁFICA', TOPOGRAFICOS: 'TOPOGRÁFICOS', METALICO: 'METÁLICO', METALICA: 'METÁLICA',
  PORTATIL: 'PORTÁTIL', OTICO: 'ÓPTICO', OTICA: 'ÓPTICA', ALUMINIO: 'ALUMÍNIO', PRECISAO: 'PRECISÃO', MEDICAO: 'MEDIÇÃO',
  GEODESICA: 'GEODÉSICA', GEODESICO: 'GEODÉSICO', ELETRONICA: 'ELETRÔNICA', ELETRONICO: 'ELETRÔNICO', ESTACAO: 'ESTAÇÃO',
  BUSSOLA: 'BÚSSOLA', PLASTICO: 'PLÁSTICO', MAXIMA: 'MÁXIMA', DIAMETRO: 'DIÂMETRO', DIMENSOES: 'DIMENSÕES',
  REGULAVEL: 'REGULÁVEL', REGULAVEIS: 'REGULÁVEIS', NIVEL: 'NÍVEL', NIVEIS: 'NÍVEIS', PLANIMETRO: 'PLANÍMETRO',
  ALTIMETRO: 'ALTÍMETRO', CLINOMETRO: 'CLINÔMETRO', TELEMETRO: 'TELÊMETRO', PODOMETRO: 'PODÔMETRO', PANTOMETRO: 'PANTÔMETRO',
  ESTEREOSCOPIO: 'ESTEREOSCÓPIO', NORMOGRAFO: 'NORMÓGRAFO', MICROMETRO: 'MICRÔMETRO', BINOCULO: 'BINÓCULO', TRIPE: 'TRIPÉ',
  DOBRAVEL: 'DOBRÁVEL', GRADUACAO: 'GRADUAÇÃO', ANGULOS: 'ÂNGULOS', ANGULO: 'ÂNGULO', REFERENCIAS: 'REFERÊNCIAS',
  REGUA: 'RÉGUA', REGUAS: 'RÉGUAS', MADEIRO: 'MADEIRA', CAPACIDADE: 'CAPACIDADE', DISTANCIA: 'DISTÂNCIA', NUMERO: 'NÚMERO',
  NUMEROS: 'NÚMEROS', JUNCAO: 'JUNÇÃO', RESTITUICAO: 'RESTITUIÇÃO', ACONDICIONAMENTO: 'ACONDICIONAMENTO', MAGNETICA: 'MAGNÉTICA',
  TRIPEEM: 'TRIPÉ EM', MADEIRASEM: 'MADEIRA SEM', ACONDICIONADOEM: 'ACONDICIONADO EM', COMTRIPE: 'COM TRIPÉ',
  MEDIAPRECISAO: 'MÉDIA PRECISÃO', OBJEITVA: 'OBJETIVA', LUMETA: 'LUNETA', HASTS: 'HASTES', INTEIRICA: 'INTEIRIÇA',
  EXTENSIVEIS: 'EXTENSÍVEIS', DIDATICOS: 'DIDÁTICOS', MICROMETRICO: 'MICROMÉTRICO', PROCEDENCIA: 'PROCEDÊNCIA', ALEMA: 'ALEMÃ',
  PENDULO: 'PÊNDULO', DECIMETROS: 'DECÍMETROS', ACESSORIOS: 'ACESSÓRIOS', TAQUIOMETRO: 'TAQUEÔMETRO', AJUSTAVEL: 'AJUSTÁVEL',
  PLASTICA: 'PLÁSTICA', AUTOMATICA: 'AUTOMÁTICA', ATE: 'ATÉ', PES: 'PÉS', ALCA: 'ALÇA', DISCO: 'DISCO',
  TERMOMETRO: 'TERMÔMETRO', UMIDO: 'ÚMIDO', ZENITAL: 'ZENITAL', CORRECAO: 'CORREÇÃO', CONSTELACOES: 'CONSTELAÇÕES',
  AUTOMATICO: 'AUTOMÁTICO', AUTOMATICA: 'AUTOMÁTICA', HORIZONTAIS: 'HORIZONTAIS', CIRCULO: 'CÍRCULO', LEITURAS: 'LEITURAS',
}).map(([k, v]) => [k, v]))

const corrige = (s) => s.toUpperCase()
  .replace(/([A-Z\ufffd])-\s?([A-Z\ufffd]{2,})/g, '$1$2')       // hifenização herdada de quebra de linha
  .replace(/(\d)(SEGUNDOS|MINUTO)/g, '$1 $2').replace(/(SEGUNDOS)(NO)\b/g, '$1 $2')
  .replace(/[A-Z0-9�']+/g, (w) => ACENTO[w] ?? w)
const SIGLAS = /\b(gps|rtk|gnss|pvc|gtr-g2|ni-b3)\b/g
const frase = (s) => { const t = corrige(s).toLowerCase().replace(SIGLAS, (x) => x.toUpperCase()).replace(/marca wild/, 'marca Wild'); return t.charAt(0).toUpperCase() + t.slice(1) }
const tipoDe = (desc) => corrige(desc).split(/[\s,.(/-]+/)[0].normalize('NFD').replace(/[̀-ͯ]/g, '')

const TIPOS = {
  TEODOLITO: ['teodolito', 'Teodolito'], NIVEL: ['nivel', 'Nível'], LUNETA: ['nivel', 'Luneta de nível'],
  MIRA: ['acessorio', 'Mira'], BALIZA: ['acessorio', 'Baliza'], TRIPE: ['acessorio', 'Tripé'], BASE: ['acessorio', 'Base topográfica'],
  PRUMO: ['acessorio', 'Prumo zenital'], EQUIPAMENTO: ['acessorio', 'Prisma'], MICROMETRO: ['acessorio', 'Micrômetro óptico'],
  ESTOJO: ['acessorio', 'Oculares'], CONJUNTO: ['acessorio', 'Oculares'],
  PLANIMETRO: ['desenho', 'Planímetro'], NORMOGRAFO: ['desenho', 'Normógrafo'], REGUA: ['desenho', 'Régua de escala'],
  ESTEREOSCOPIO: ['desenho', 'Estereoscópio'],
  BUSSOLA: ['medicao', 'Bússola'], CLINOMETRO: ['medicao', 'Clinômetro'], ALTIMETRO: ['medicao', 'Altímetro'],
  PODOMETRO: ['medicao', 'Podômetro'], MEDIDOR: ['medicao', 'Medidor topográfico'], TELEMETRO: ['medicao', 'Telêmetro'],
  PANTOMETRO: ['medicao', 'Pantômetro'], BINOCULO: ['medicao', 'Binóculo'], TRENA: ['medicao', 'Trena eletrônica'],
  PRANCHETA: ['medicao', 'Prancheta topográfica'],
  RECEPTOR: ['gnss', 'Receptor GNSS'], SISTEMA: ['gnss', 'Receptor GNSS'], ESTACAO: ['estacao-total', 'Estação total'],
  SCANNER: ['laser-scanner', 'Laser scanner'], CAMERA: ['apoio', 'Câmera digital'], AERONAVE: ['aeronave', 'VANT'],
  MARTEL: ['apoio', 'Martelete'],
}

const SEM_MARCA = new Set(['', 'NT', 'GPS', 'RTK', 'SEM MARCA'])
const MARCAS = { 'CARL ZEISS': 'Zeiss', 'CARL ZEIS': 'Zeiss', ZEISS: 'Zeiss', SNRAY: 'Sunray', VASCONSELOS: 'Vasconcelos', 'K.E.': 'K+E', 'K.E': 'K+E', MIRATEL: 'Miratec', TRIDENTE: 'Trident', DESETEC: 'Desetec/Trident', 'CARL ZEISS JENA': 'Zeiss Jena', 'DESENTEC/TRIDENT': 'Desetec/Trident', 'DESETEC/TRIDENT': 'Desetec/Trident', 'HI TARGET': 'Hi-Target', BOCH: 'Bosch', 'K+E': 'K+E', 'OSAKA-TAMAYA': 'Osaka-Tamaya', 'LEROY-KEUFFELESSER': 'Leroy/Keuffel & Esser', 'TAMA SOKKI': 'Tama Sokki' }
const marcaDe = (m) => {
  const u = m.trim().toUpperCase()
  if (SEM_MARCA.has(u)) return null
  if (MARCAS[u]) return MARCAS[u]
  return u.length <= 3 ? u : u.toLowerCase().replace(/(^|[\s/-])\p{L}/gu, (c) => c.toUpperCase())
}
const slug = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\+/g, '-plus').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

const resumo = (desc) => {
  let t = frase(desc).replace(/\s+/g, ' ').trim()
  if (t.length > 220) { const c = t.slice(0, 220); t = c.slice(0, Math.max(c.lastIndexOf(','), c.lastIndexOf('.'), 120)).replace(/[,.]$/, '') + '.' }
  return /[.!]$/.test(t) ? t : `${t}.`
}

// 1. modelos curados com as unidades da planilha de empréstimo
const modelos = new Map()
const usados = new Set()
const situacaoPat = new Map(patrimonio.map((p) => [p.patrimonio, p]))
for (const e of emprestimo) {
  const c = CURADOS[e.modelo.trim().toUpperCase()]
  if (!c) throw new Error(`Modelo sem cadastro: ${e.modelo}`)
  if (!modelos.has(c.id)) modelos.set(c.id, { ...c, emprestavel: true, unidades: [] })
  const bruto = e.patrimonio.replace(/\*$/, '').trim()
  const temPat = /^\d+$/.test(bruto) && !e.patrimonio.endsWith('*')
  const u = temPat ? { patrimonio: bruto } : /^\d+$/.test(bruto) ? { serie: bruto } : { obs: 'Sem número de patrimônio na planilha.' }
  const p = temPat && situacaoPat.get(bruto)
  if (p && /defeito/i.test(p.situacao)) { u.situacao = 'manutencao'; u.obs = 'Consta como "Com defeito" no patrimônio.' }
  if (temPat) usados.add(bruto)
  modelos.get(c.id).unidades.push(u)
}

// 2. o restante do patrimônio, agrupado por tipo e marca
let fora = 0
for (const p of patrimonio) {
  if (usados.has(p.patrimonio)) continue
  const tipo = tipoDe(p.descricao)
  if (MOBILIARIO.test(tipo)) { fora++; continue }
  const t = TIPOS[tipo]
  if (!t) throw new Error(`Tipo sem categoria: ${tipo} (${p.patrimonio})`)
  const marca = marcaDe(p.marca)
  const id = slug(`${t[1]} ${marca ?? 'sem marca'}`)
  if (!modelos.has(id)) {
    modelos.set(id, { id, categoria: t[0], marca: t[1], nome: marca ?? 'sem marca', foto: null, descricao: resumo(p.descricao), emprestavel: true, unidades: [] })
  }
  const u = { patrimonio: p.patrimonio }
  if (p.serie && !SEM_MARCA.has(p.serie.toUpperCase())) u.serie = p.serie
  if (/defeito/i.test(p.situacao)) { u.situacao = 'manutencao'; u.obs = 'Consta como "Com defeito" no patrimônio.' }
  else if (p.observacao) u.obs = frase(p.observacao).slice(0, 160)
  modelos.get(id).unidades.push(u)
}

const ordemCat = Object.fromEntries(categorias.map((c) => [c.id, c.ordem]))
const lista = [...modelos.values()].sort((a, b) =>
  ordemCat[a.categoria] - ordemCat[b.categoria] || (b.foto ? 1 : 0) - (a.foto ? 1 : 0) || b.unidades.length - a.unidades.length || a.id.localeCompare(b.id))

writeFileSync(new URL('../src/dados/acervo.json', import.meta.url), JSON.stringify({ categorias, modelos: lista }, null, 1) + '\n')
const n = lista.reduce((s, m) => s + m.unidades.length, 0)
console.log(`${lista.length} modelos, ${n} unidades (${fora} itens de mobiliário fora do acervo)`)
