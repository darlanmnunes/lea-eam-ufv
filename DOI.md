# DOI e registro das versões

Acervo do LEA, arquivado no Zenodo pela integração com o GitHub.

## DOI conceito (todas as versões)

**10.5281/zenodo.24478306**: https://doi.org/10.5281/zenodo.24478306

Aponta sempre para a versão mais recente. Usado no README, no rodapé do site e no campo `doi` do CITATION.cff.

## DOI de cada versão

Cada DOI de versão identifica exatamente um pacote de código. Use-o onde for preciso citar a versão exata, por
exemplo no Formulário I (registro de programa de computador) e no Lattes, junto com o hash.

| Versão | Data | DOI da versão | Tag / commit | Situação |
| --- | --- | --- | --- | --- |
| 1.1.2 | 2026-11-23 | (preencher após o release) | `v1.1.2` | Versão vigente: pacote só com o código, sem fotos nem inventário |
| 1.1.1 | 2026-11-23 | 10.5281/zenodo.24478307 | (tag reescrita) | Pedido de remoção ao Zenodo: o pacote levou números de patrimônio e fotos. Não usar. |

O pacote é o .zip do release no GitHub. Desde a 1.1.2, o `.gitattributes` deixa de fora as fotos, as marcas,
as capturas de tela e o `.gitignore`. Patrimônio, número de série e fotos originais não fazem parte do
repositório (ficam em `dados-fonte/privado/` e `db/privado/`, que o git ignora).

## Ao publicar uma versão nova

O release publicado no GitHub gera um DOI de versão novo e mantém o DOI conceito. Acrescente uma linha na tabela,
com os hashes do pacote (`shasum -a 512` no .zip baixado da página do DOI), e atualize `version`, `date-released`
e o DOI da versão em `identifiers` no CITATION.cff. Commits sem release, como ajustes de README ou de rodapé,
não mudam nenhum DOI.
