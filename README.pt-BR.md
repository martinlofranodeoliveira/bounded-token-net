# Bounded Token Net

Versão de desenvolvimento **0.1.0**, por
[Lofrano Tecnologia](https://lofranotecnologia.com.br). Licença MIT.
[English](README.md).

Biblioteca Elixir sem dependências para modelos pequenos e finitos de recursos.
Dispara transições ponderadas atomicamente, explora vetores alcançáveis e
reconstrói testemunhos mínimos de deadlock. Não executa workflows. Não inicia
processos, não usa relógios, persistência, telemetria, APIs de modelos, Hex,
NIFs ou serviços externos.

## Instalação, testes e demonstração

Use Elixir 1.18 ou uma versão 1.x posterior compatível, com Erlang/OTP. A matriz
de CI tem como alvos Elixir 1.18 e 1.20.5 em imagens oficiais; isso não é uma
afirmação de execução bem-sucedida. No diretório do projeto:

```sh
mix compile --warnings-as-errors
mix test --seed 0
mix run demo/assert_demo.exs
mix run demo/assert_demo.exs --json
```

Não há preparação de dependências. O alias `run` compila silenciosamente antes
de executar. A saída padrão exata da demonstração bem-sucedida é:

```text
DEMO_OK states=4 deadlocks=1 witness=take1,take2
```

A opção para leitura por máquina produz uma única linha JSON:

```json
{"complete":true,"states":4,"deadlocks":1,"witness":["take1","take2"]}
```

Alternativa com imagem oficial, registrando o digest realmente resolvido:

```sh
docker pull elixir:1.18
docker image inspect elixir:1.18 --format '{{index .RepoDigests 0}}'
docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp -e ERL_FLAGS="+S 2:2 +SDcpu 1 +SDio 1" -v "$PWD:/project" -w /project elixir:1.18 mix test --seed 0
```

Guarde o digest impresso com o registro dos testes. A CI registra o digest no
resumo da execução. Não há digest nem resultado de execução inventado aqui.
Em outro projeto Mix vizinho, acrescente
`{:bounded_token_net, path: "../bounded-token-net"}` à lista `deps`.
Trata-se de dependência local, não de alegação de publicação de pacote.

## Exemplo pequeno

```elixir
alias BoundedTokenNet, as: BTN
net = BTN.Examples.toggle()
:ok = BTN.validate(net)
{:ok, m} = BTN.marking(net, [1, 0])
{:ok, go} = BTN.transition(net, "go")
{:ok, true} = BTN.enabled(m, go)
{:ok, next} = BTN.fire(m, go)
next.tokens # [0, 1]
{:ok, report} = BTN.explore(net, m)
{report.complete, report.state_count, report.edge_count} # {true, 2, 2}
{:ok, ["go"]} = BTN.witness(report, {0, 1})
{:ok, %{conserved_value: 1}} = BTN.verify_invariant(net, [1, 1])
```

Os campos dos mapas são átomos definidos pela biblioteca; IDs são binários
limitados, nunca convertidos em átomos. A ordem dos lugares define o vetor.
IDs de transição são ordenados lexicalmente. A marcação vinculada contém os
lugares, capacidades e tokens, permitindo verificar disparos isolados.

```elixir
net = %{
  places: [%{id: "slot", capacity: 1}],
  initial: [1],
  transitions: [%{id: "reuse", pre: [{"slot", 1}], post: [{"slot", 1}]}],
  terminals: []
}
{:ok, m} = BTN.marking(net, [1])
{:ok, reuse} = BTN.transition(net, "reuse")
{:ok, m} = BTN.fire(m, reuse)
{:ok, m} = BTN.fire(m, reuse)
{:error, %{code: :InsufficientTokens}} = BTN.fireBatch(m, [reuse, reuse])
```

O lote exige todos os tokens na marcação **original**. Saídas do próprio lote
não financiam entradas. `fire_batch/2` é o alias idiomático de `fireBatch/2`.
Erros não devolvem uma marcação alterada; lote vazio preserva a marcação.

## Resultados e limites

```elixir
net = BTN.Examples.toggle()
{:ok, partial} = BTN.explore(net, net.initial, %{max_states: 1})
{partial.complete, partial.reason} # {false, :state_limit}
{:ok, []} = BTN.witness(partial, partial.initial)
```

Limites rígidos: 32 lugares, 64 transições, capacidades e pesos de arco até
255, 256 ocorrências por lote. A exploração usa por padrão 10.000 estados
novos e 100.000 tentativas de transição, contando também as desabilitadas.
É possível reduzir, mas não aumentar esses dois orçamentos.

Exploração incompleta conserva testemunhos descobertos, mas não demonstra
inalcançabilidade, ausência de deadlocks, segurança ou vivacidade. Campos
`enabled` e `deadlock` iguais a `nil` indicam expansão não concluída. Terminais
são rótulos declarados: não interrompem a busca. Deadlock inesperado é uma
marcação alcançável não terminal sem transição habilitada.

## Modelo sintético e escolhas de projeto

A demonstração é um **modelo sintético finito de aquisição única de recursos**:
lugares `r1,r2,h1,h2`, capacidade 1, inicial `[1,1,0,0]`,
`take1: r1 → h1`, `take2: r2 → h2`, sem liberações nem terminais.
Estados: `[1,1,0,0]`, `[0,1,1,0]`, `[1,0,0,1]`, `[0,0,1,1]`.
O último é o único deadlock; seu testemunho canônico mínimo é `take1,take2`.
Isso **não prova espera circular real** em sistemas.

Validação, aritmética de vetores e BFS ficam separadas. Predecessores compactos
permitem reconstruir caminhos sem guardar todos os prefixos repetidos.
Invariantes inteiros verificam deltas de incidência de todas as transições;
não constituem certificação formal. Um simulador independente de arcos esparsos
e testes exaustivos de redes minúsculas verificam o motor de vetores densos.

## Limitações e documentação

Capacidades e transições são hipóteses do autor do modelo. Até uma busca
completa descreve somente esse modelo finito, não uma implementação. Não há
provas para redes ilimitadas, tempo, aleatoriedade, PNML/XML, autorização,
execução de workflows ou alegação de conformidade industrial. Termos de entrada
já precisam caber na memória do chamador; os limites cobrem o trabalho e os
resultados da biblioteca, não a criação prévia desses termos.

* [Contrato preciso em inglês](docs/contract.md)
* [Projeto e referências](docs/design.md)
* [Semântica em português](docs/semantics.pt-BR.md)
* [Contribuições](CONTRIBUTING.md) e [segurança](SECURITY.md)

Contato geral: [site oficial](https://lofranotecnologia.com.br).
Repositório: https://github.com/martinlofranodeoliveira/bounded-token-net
