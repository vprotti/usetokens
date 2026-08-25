# Contribuir · Contributing

*Português abaixo do inglês.*

---

## English

Thanks for taking a look.

**Bugs.** Open an issue with what you did, what you expected and what happened,
plus your macOS version and how you installed UseTokens. A screenshot usually says
more than a paragraph.

**Ideas.** Open an issue and describe the problem you are trying to solve, not
only the feature you have in mind. UseTokens is deliberately small — a change that
makes it do one thing well beats a change that adds a switch.

**Pull requests.**

1. Fork, branch, and keep the change focused on one thing.
2. Build it: `./scripts/build.sh` has to finish clean, with no new warnings.
3. Match the surrounding code. No external dependencies — the app builds with
   Apple's Command Line Tools alone and stays that way.
4. Comments explain *why* something is the way it is, not what the line does.
5. Write the PR description as if the reader has not seen the issue.

**What will not be merged:** analytics, crash reporters, ad SDKs, anything that
sends data off the user's Mac, and anything that requires an account.

## Português

Obrigado por dar uma olhada.

**Bugs.** Abra uma issue com o que voce fez, o que esperava e o que aconteceu,
mais a versao do macOS e como instalou o UseTokens. Um print costuma dizer mais
que um paragrafo.

**Ideias.** Abra uma issue e descreva o problema que quer resolver, nao so a
funcionalidade que imaginou. O UseTokens e pequeno de proposito — uma mudanca que
faz ele resolver uma coisa bem vale mais que uma que adiciona um botao.

**Pull requests.**

1. Fork, branch, e mantenha a mudanca focada em uma coisa so.
2. Compile: `./scripts/build.sh` precisa terminar limpo, sem avisos novos.
3. Siga o estilo do codigo em volta. Sem dependencia externa — o app compila so
   com as Command Line Tools da Apple e vai continuar assim.
4. Comentario explica *por que* algo e assim, nao o que a linha faz.
5. Escreva a descricao do PR como se quem le nao tivesse visto a issue.

**O que nao entra:** analytics, crash reporter, SDK de anuncio, qualquer coisa
que mande dado para fora do Mac do usuario, e qualquer coisa que exija conta.
