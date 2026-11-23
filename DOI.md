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
| 1.1.2 | 2026-11-23 | [10.5281/zenodo.24483932](https://doi.org/10.5281/zenodo.24483932) | `v1.1.2` / `ea62ff13021ea2221d83592ee33e37a33d52ef6d` | Versão vigente: pacote só com o código, sem fotos nem inventário |
| 1.1.1 | 2026-11-23 | 10.5281/zenodo.24478307 | (tag reescrita) | Pedido de remoção ao Zenodo: o pacote levou números de patrimônio e fotos. Não usar. |

### Hashes do pacote 1.1.2 (`darlanmnunes/lea-eam-ufv-v1.1.2.zip`, 297.343 bytes, baixado do Zenodo)

- MD5 (o mesmo que o Zenodo mostra): `6fb84db6d34f36ceb76da57eb8203f0e`
- SHA-256: `9a5132283e6ac7ac1a28db7f163713f1edddc77a698b887a048c4c58e6632cb9`
- SHA-512: `3325a7682290e729b954945e0f218569be91ab4e2a274d65d2310ba95abbf896e339bf9dfb9552e0e1de249d5140047281154f9ce3e90ea875d5f859678109a8`

Para conferir: baixe o .zip da página do DOI da versão e rode `shasum -a 512 lea-eam-ufv-v1.1.2.zip`.

O pacote é o .zip do release no GitHub. Desde a 1.1.2, o `.gitattributes` deixa de fora as fotos, as marcas,
as capturas de tela e o `.gitignore`. Patrimônio, número de série e fotos originais não fazem parte do
repositório (ficam em `dados-fonte/privado/` e `db/privado/`, que o git ignora).

## Ao publicar uma versão nova

O release publicado no GitHub gera um DOI de versão novo e mantém o DOI conceito. Acrescente uma linha na tabela,
com os hashes do pacote (`shasum -a 512` no .zip baixado da página do DOI), e atualize `version`, `date-released`
e o DOI da versão em `identifiers` no CITATION.cff. Commits sem release, como ajustes de README ou de rodapé,
não mudam nenhum DOI.
