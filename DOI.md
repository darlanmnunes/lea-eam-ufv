# DOI e registro das versões

Acervo do LEA, arquivado no Zenodo pela integração com o GitHub.

## DOI conceito (todas as versões)

**10.5281/zenodo.24478306**: https://doi.org/10.5281/zenodo.24478306

Aponta sempre para a versão mais recente. Usado no README, no rodapé do site e no campo `doi` do CITATION.cff.

## DOI de cada versão

Cada DOI de versão identifica exatamente um pacote de código. Use-o onde for preciso citar a versão exata, por
exemplo no Formulário I (registro de programa de computador) e no Lattes, junto com o hash.

| Versão | Data | DOI da versão | Tag / commit | Pacote no Zenodo |
| --- | --- | --- | --- | --- |
| 1.1.1 | 2026-11-23 | [10.5281/zenodo.24478307](https://doi.org/10.5281/zenodo.24478307) | `v1.1.1` / `a5709580d5b546f4e7a4e3da2373ab6fbf5cd7ad` | `darlanmnunes/lea-eam-ufv-v1.1.1.zip` (7.398.070 bytes) |

### Hashes do pacote 1.1.1 (arquivo .zip baixado do Zenodo)

- MD5 (o mesmo que o Zenodo mostra): `e84f1d15e5eea9fd610fa8483a9be14c`
- SHA-256: `29236c93bc5b63af0e29f85d1770ad10d32aec4ad6a782ab1e5824e9390a2562`
- SHA-512: `2910559a146a95a7d109a93f9788cf5eb93a03599cee7ab1e4d8ccd5e91cd953862a9d9ebdce24a7ef5ed4f19169c29cc57731a8005bdc28561bc374588588c1`

Para conferir: baixe o .zip da página do DOI da versão e rode `shasum -a 512 lea-eam-ufv-v1.1.1.zip`.

## Ao publicar uma versão nova

O release publicado no GitHub gera um DOI de versão novo e mantém o DOI conceito. Acrescente uma linha na tabela, com
os hashes do pacote, e atualize `version`, `date-released` e o DOI da versão em `identifiers` no CITATION.cff.
Commits sem release, como ajustes de README ou de rodapé, não mudam nenhum DOI.
