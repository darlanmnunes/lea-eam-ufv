# Acervo do LEA

Catálogo e empréstimo de equipamentos do Laboratório de Engenharia de Agrimensura e
Cartográfica (LEA), do curso de Engenharia de Agrimensura e Cartográfica da UFV.

Substitui o requerimento em papel: a pessoa escolhe as datas, vê o que está livre, monta o
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
2. No SQL Editor, rode nesta ordem: `db/001_esquema.sql`, `db/002_regras.sql`,
   `db/003_acervo.sql`, `db/004_horarios.sql`. (O `000_local_auth.sql` é só para Postgres local.)
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
