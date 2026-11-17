# Acervo do LEA

O acervo do Laboratório de Engenharia de Agrimensura e Cartográfica (LEA), do curso de
Engenharia de Agrimensura e Cartográfica da UFV: os equipamentos, a situação de cada unidade,
as aulas práticas que os usam e os empréstimos. Pensado para crescer além do empréstimo.

O empréstimo substitui o requerimento em papel: a pessoa escolhe as datas, vê o que está livre, monta o
pedido e assina o termo de responsabilidade. A coordenação da área e o responsável pelo
laboratório autorizam; o técnico confere os itens na entrega e na devolução; quem pediu dá
ciente das duas. Cada assinatura fica registrada com nome, data e hora.

## O que há aqui

| Pasta | Conteúdo |
| --- | --- |
| `src/` | Aplicação (React + TypeScript, Vite) |
| `src/dados/` | Acervo inicial e horário de aulas EAM |
| `db/` | Esquema PostgreSQL, regras do fluxo, dados iniciais e testes |
| `supabase/functions/lembretes/` | Envio dos lembretes por e-mail |
| `scripts/` | Importação do horário da DTI e geração do SQL do acervo |

## Rodar no computador

```bash
npm install
npm run dev
```

Sem configuração, o site abre em **modo demonstração**: os dados ficam só no navegador e há
seis pessoas fictícias, uma para cada papel, para percorrer o fluxo inteiro.

## Papéis

| Papel | O que faz |
| --- | --- |
| Solicitante | Qualquer pessoa com e-mail da UFV: pede, dá ciente de retirada e de devolução |
| Docente | Informa os equipamentos que cada disciplina usa nas aulas práticas |
| Coordenação da área | Primeira autorização |
| Responsável pelo LEA | Segunda autorização e prorrogações |
| Técnico do LEA | Cadastra equipamentos, entrega e recebe conferindo item a item |
| Administração | Define papéis e as datas do semestre |

## Disponibilidade

Uma unidade está livre num período quando está em circulação, não tem outro pedido nas
mesmas datas e não está reservada para aula. A reserva de aula vem do horário das
disciplinas EAM (DTI) cruzado com o que cada docente informou: nos dias com aula prática,
as unidades que a disciplina usa saem da disponibilidade para empréstimo.

Para atualizar o horário de um semestre:

```bash
node scripts/importar-horarios.mjs 2027 1
```

## Banco de dados (PostgreSQL)

As regras ficam no banco: quem pode assinar cada etapa, bloqueio de reserva em dobro,
prioridade das aulas e registro imutável das assinaturas. Para testar num Postgres local:

```bash
npm run db:teste   # cria um banco descartável e percorre o fluxo inteiro
npm run db:local   # cria o banco "lea" para explorar
```

### Colocar no ar com Supabase

1. Crie um projeto em supabase.com (plano gratuito).
2. No SQL Editor, rode `db/supabase_completo.sql` (os scripts 001 a 004 juntos; gere de novo
   com `npm run db:supabase` depois de mudar algum). O `000_local_auth.sql` é só para Postgres local.
3. Em Authentication, mantenha o acesso por link no e-mail e inclua o endereço do site em
   URL Configuration.
4. Copie `.env.example` para `.env` e preencha a URL e a chave `anon` do projeto.
5. Entre no site com o seu e-mail e torne-se administrador pelo SQL Editor:

   ```sql
   update pessoas set papeis = '{solicitante,admin}' where email = 'voce@ufv.br';
   ```

   A partir daí os demais papéis são definidos na tela **Pessoas**.
6. Informe as datas do semestre na tela **Aulas**.

### Lembretes por e-mail

A função `supabase/functions/lembretes` avisa quem precisa autorizar, entregar ou dar
ciente, e repete o aviso a cada 24 horas até a etapa andar. Ela usa o Resend para enviar.

```bash
supabase functions deploy lembretes
supabase secrets set RESEND_API_KEY=... LEMBRETE_REMETENTE="LEA <lea@seu-dominio>" SITE_URL=https://...
```

Agende a chamada (Database → Cron) a cada 30 minutos, por exemplo.

## Publicação

O fluxo `.github/workflows/publicar.yml` gera o site e publica no GitHub Pages a cada envio
para `main`. Em Settings → Pages, escolha "GitHub Actions" como fonte. Para ligar ao banco,
cadastre `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` em Settings → Variables.

## Na página do curso

O site gerado (`npm run build`, pasta `dist/`) usa caminhos relativos e rotas com `#`, então
funciona em qualquer endereço sem ajuste. Três formas de levá-lo ao site do curso:

1. **Link ou botão** na página do curso apontando para o endereço do GitHub Pages
   (`https://darlanmnunes.github.io/lea-eam-ufv/`). É a forma mais simples e a única em que o
   login funciona sem restrição.
2. **Copiar a pasta `dist/`** para o servidor do curso (por exemplo em `/lea/`). O sistema passa
   a ter o endereço do curso. Com o banco ligado, inclua esse endereço em Authentication →
   URL Configuration no Supabase.
3. **Embutir com `<iframe>`**, bom para mostrar o catálogo dentro de uma página já existente:

   ```html
   <iframe src="https://darlanmnunes.github.io/lea-eam-ufv/acervo.html"
           title="Acervo do LEA" style="width:100%;height:900px;border:0"></iframe>
   ```

   Dentro de um iframe de outro domínio, os navegadores isolam o armazenamento, e o login pelo
   link do e-mail abre fora dele. Para pedir e assinar, use o link direto (forma 1 ou 2).

## Autoria

Desenvolvido por Prof. Dr. Darlan Miranda Nunes, Departamento de Engenharia Civil, Universidade
Federal de Viçosa.
