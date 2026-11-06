# Kopa

Jogo tático PvP por turnos em Godot 4.3. Cada jogador controla 5 personagens
(Tanque, Assassino, Arqueiro, Druida e Engenheiro) num tabuleiro 3D com câmera
estilo MOBA. O golpe que vence a partida não é encenado na hora: ele dispara uma
cinemática da partida inteira, do primeiro turno até o golpe final.

Os modelos são formas provisórias e os números de balanceamento são um ponto de partida.

## Como rodar

1. Abra o Godot 4.3 (ou mais recente da série 4.x) e importe a pasta do repositório.
2. Aperte F5. A partida é local: os dois jogadores revezam no mesmo computador.

Teste automático, com a IA jogando pelos dois lados até a cinemática:

```bash
godot --path . -- --autoplay
```

## Controles

| Ação | Tecla |
| --- | --- |
| Mover a câmera | WASD ou setas, ou arrastar com o botão do meio |
| Aproximar / afastar | Roda do mouse |
| Girar a câmera | Q / E |
| Centralizar no personagem da vez | F |
| Modo mover | M |
| Habilidades | 1 e 2 |
| Confirmar alvo / destino | Botão esquerdo |
| Cancelar | Botão direito ou Esc |
| Encerrar turno | Espaço |

## Regras atuais

- **Ordem de iniciativa alternada.** No início de cada rodada, cada jogador ordena
  seus personagens vivos por iniciativa. Os jogadores se alternam: o mais rápido
  do J1, o mais rápido do J2, o segundo do J1 e assim por diante. Começa quem tem
  a maior iniciativa; no empate, quem começa alterna a cada rodada.
- **Turno do personagem:** andar (até o valor de Movimento) e usar 1 habilidade,
  em qualquer ordem. O turno acaba sozinho quando as duas coisas são feitas.
- Distâncias em quadrados (sem diagonal). Obstáculos bloqueiam movimento e linha de visão.
- Vitória: eliminar os 5 personagens do rival (a torreta não conta).

| Classe | Vida | Mov. | Inic. | Habilidade 1 | Habilidade 2 |
| --- | --- | --- | --- | --- | --- |
| Tanque | 170 | 3 | 3 | Golpe de Escudo: 18, empurra | Muralha: −50% de dano até o próximo turno |
| Assassino | 85 | 5 | 9 | Apunhalar: 26 | Execução: 20, dobra abaixo de 40% de vida |
| Arqueiro | 90 | 3 | 7 | Flecha: 17, alcance 6 | Chuva de Flechas: 12 em área 3x3 |
| Druida | 95 | 3 | 5 | Cura: +30 | Espinhos: 12 e enraíza |
| Engenheiro | 100 | 3 | 4 | Torreta: atira 10 no fim do turno dele | Granada: 16 em área 3x3 |

Todos os números ficam em `scripts/core/game_data.gd`.

## Arquitetura

```
scripts/
  core/      lógica pura, sem nada visual
    game_data.gd        classes, habilidades, balanceamento
    match_state.gd      regras, turnos, comandos e registro de eventos
    tactical_ai.gd      IA simples (teste automático e futuro modo contra a máquina)
  world/     tabuleiro, personagens e câmera de jogo
  game/
    event_player.gd     encena eventos (usado no jogo e na cinemática)
    cinematic_director.gd  cinemática do golpe final
  ui/hud.gd  interface
  main.gd    liga tudo e trata a entrada do jogador
```

- **O registro é a fonte de verdade.** Cada comando (`move_to`, `use_ability`,
  `end_turn`) resolve na hora, sorteios incluídos, e grava eventos em
  `MatchState.events`. O jogo só encena esses eventos.
- **Golpe final.** O evento que encerra a partida vem marcado com `final`. O
  `main.gd` não o encena: chama o `CinematicDirector`, que recria o tabuleiro no
  estado inicial e encena o registro inteiro em sequência, sem pausas entre
  turnos e com uma câmera de cinema que acompanha a ação sem cortes. Só o último
  golpe entra em câmera lenta, congela no impacto com a câmera girando e retoma.
- **PvP online (próximo passo).** Como toda a partida vem dos comandos, basta
  sincronizar os comandos entre os jogadores, com um servidor validando. Cada
  aparelho monta a cinemática localmente, sem transmitir vídeo.
