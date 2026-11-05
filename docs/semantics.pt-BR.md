# Semântica da versão de desenvolvimento 0.1.0

O contrato normativo de campos e retornos está em [contract.md](contract.md).
Este texto explica o mesmo modelo discreto e suas limitações em português.

## Lugares, vetores e arcos

Um lugar tem ID binário ASCII de 1 a 64 bytes e capacidade inteira de 0 a 255.
Há de 1 a 32 lugares, em ordem explícita. A marcação é um vetor de inteiros
não negativos, de aridade exata, sem exceder as capacidades. A estrutura
`Marking` vincula esse vetor à ordem e às capacidades para disparos isolados.

Há até 64 transições, cada uma com ID único e arcos de entrada e saída. IDs
obedecem a `[A-Za-z0-9][A-Za-z0-9_.-]*`; não se criam átomos a partir deles.
Lugares e transições usam espaços de nomes separados. Arcos são tuplas
`{id_do_lugar, peso}`, com peso inteiro de 1 a 255 e lugar conhecido. Repetir
um lugar na mesma lista de entrada ou na mesma lista de saída é erro. É
permitido usar o mesmo lugar uma vez na entrada e uma vez na saída.
Lista vazia de arcos significa peso zero. Floats e booleanos não são aceitos
como inteiros. Listas impróprias e campos extras são rejeitados.

Para um disparo, primeiro se exige `m[i] >= pre[i]` para todos os lugares.
Depois se calcula `m'[i] = m[i] - pre[i] + post[i]` e se verifica cada capacidade.
Não basta verificar apenas a diferença líquida: a entrada precisa existir antes.
Nenhuma falha devolve marcação parcialmente modificada.

## Lotes

Um lote contém até 256 ocorrências; a mesma transição pode se repetir.
Validam-se todas antes da aritmética. Somam-se separadamente entradas e saídas.
Todos os requisitos de entrada devem caber na marcação original. Só então se
calcula o vetor final e se verificam as capacidades. Não há ordem intermediária
de disparo. Saídas do lote não podem financiar entradas do mesmo lote.

Assim, consumir e repor o único token duas vezes em sequência é permitido;
duas ocorrências dessa transição em um lote falham com `InsufficientTokens`.
Um lote vazio preserva a marcação, mas também valida sua forma e seus limites.

## Exploração e evidência

A busca usa fila FIFO, IDs ordenados lexicalmente e chaves de tupla imutáveis.
Predecessores de primeira descoberta formam os testemunhos mínimos. Em empate,
a sequência lexicalmente menor vence. `witness(report, chave)` reconstrói a
lista de IDs; o caminho inicial é vazio. Não há relógios nem durações.

O limite padrão e máximo é de 10.000 estados descobertos e 100.000 tentativas.
Toda tentativa conta, inclusive transições desabilitadas. Os parâmetros Elixir
são `max_states` e `max_firings`; aceitam inteiros entre 1 e 10.000, e entre 0 e
100.000, respectivamente. A igualdade do limite de estados não interrompe
ciclos já visitados: só um sucessor realmente novo além do limite interrompe.
A igualdade de trabalho pode concluir se não houver outra tentativa pendente.

Terminais são até 256 vetores únicos declarados e validados, mesmo que não
sejam alcançáveis. São rótulos, não barreiras de exploração. Deadlock inesperado
é uma marcação alcançável não terminal sem transição habilitada. Uma marcação
terminal sem saídas não é contada como deadlock inesperado.

Relatórios incompletos têm `complete: false` e motivo `state_limit` ou
`firing_limit`. Conservam estados e predecessores válidos. Uma linha ainda não
expandida totalmente tem `enabled: nil` e `deadlock: nil`, não listas vazias ou
falso. Rótulos terminais já são conhecidos na descoberta; deadlocks só são
confirmados após examinar todas as transições daquele estado.

Um relatório incompleto não prova inalcançabilidade, ausência de deadlocks,
segurança ou vivacidade. Mesmo um relatório completo descreve apenas o modelo
finito fornecido, nunca a implementação real do protocolo. Não se deve editar
um relatório e continuar tratando seus testemunhos como evidência original.

## Invariantes

Cada peso inteiro tem módulo até 1.000.000. Para toda transição calcula-se
exatamente `soma(peso[i] * (post[i] - pre[i]))`. O primeiro delta não nulo na
ordem canônica é retornado com ID e valor exato. Sucesso retorna o produto
escalar dos pesos com a marcação inicial declarada. Verificam-se também
transições inalcançáveis. Isso é aritmética de incidência, não certificação.

No toggle com IDs `go` e `return`, `[1,1]` conserva valor 1; `[1,0]` viola em
`go` com delta -1. Renomear `return` para `back` muda a primeira violação
canônica para `back`, delta +1, pois a ordem é lexical.

## Demonstração exata e exclusões

O modelo sintético finito de aquisição única usa `r1,r2,h1,h2`, capacidade 1,
inicial `[1,1,0,0]`, sem terminais. `take1` move um token de r1 para h1;
`take2` move um de r2 para h2. Não há liberações. Os quatro estados são:

| Vetor | Testemunho |
| --- | --- |
| `[1,1,0,0]` | vazio |
| `[0,1,1,0]` | `take1` |
| `[1,0,0,1]` | `take2` |
| `[0,0,1,1]` | `take1,take2` |

O último estado é o único deadlock. Esse exemplo não demonstra espera circular
real em sistemas; a ausência de liberações é uma hipótese explícita.

Não há execução de workflows, persistência, autorização, PNML/XML, redes
ilimitadas, tempo, estocasticidade ou alegação de conformidade industrial.
Operações puras permitem chamadas concorrentes independentes, mas não impõem
limites globais ao número de chamadores. Limites de entrada e trabalho não
constituem promessa de tempo ou de memória do sistema inteiro.
