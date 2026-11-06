class_name GameData
extends RefCounted
## Dados de design: classes, habilidades e números de balanceamento.
## Tudo que é ajuste de design fica aqui, separado da lógica.

const GRID_W := 14
const GRID_H := 10
const TILE := 2.0

const CRIT_CHANCE := 0.1
const CRIT_MULT := 1.5

const TURRET_RANGE := 4
const TURRET_DAMAGE := 10

const TEAM_COLORS := [Color(0.25, 0.78, 1.0), Color(1.0, 0.36, 0.42)]
const TEAM_NAMES := ["Jogador 1", "Jogador 2"]

const ROSTER := ["tanque", "assassino", "arqueiro", "druida", "engenheiro"]

const CLASSES := {
	"tanque": {"nome": "Tanque", "sigla": "TAN", "hp": 170, "mov": 3, "ini": 3,
		"habilidades": ["golpe_escudo", "muralha"]},
	"assassino": {"nome": "Assassino", "sigla": "ASS", "hp": 85, "mov": 5, "ini": 9,
		"habilidades": ["apunhalar", "execucao"]},
	"arqueiro": {"nome": "Arqueiro", "sigla": "ARQ", "hp": 90, "mov": 3, "ini": 7,
		"habilidades": ["flecha", "chuva_flechas"]},
	"druida": {"nome": "Druida", "sigla": "DRU", "hp": 95, "mov": 3, "ini": 5,
		"habilidades": ["cura", "espinhos"]},
	"engenheiro": {"nome": "Engenheiro", "sigla": "ENG", "hp": 100, "mov": 3, "ini": 4,
		"habilidades": ["torreta", "granada"]},
	"torreta": {"nome": "Torreta", "sigla": "TOR", "hp": 45, "mov": 0, "ini": 0, "estrutura": true,
		"habilidades": []},
}

## alvo: inimigo | aliado | area | si | vazio
## anim: melee | projetil | arco | si | invocar (como a ação é encenada)
const ABILITIES := {
	"golpe_escudo": {"nome": "Golpe de Escudo", "alvo": "inimigo", "alcance": 1, "dano": 18, "empurra": 1,
		"recarga": 0, "anim": "melee",
		"desc": "Corpo a corpo. 18 de dano e empurra o alvo 1 quadrado."},
	"muralha": {"nome": "Muralha", "alvo": "si", "alcance": 0, "efeito": "muralha", "recarga": 3, "anim": "si",
		"desc": "Recebe 50% menos dano até o próximo turno dele."},
	"apunhalar": {"nome": "Apunhalar", "alvo": "inimigo", "alcance": 1, "dano": 26, "recarga": 0, "anim": "melee",
		"desc": "Corpo a corpo. 26 de dano."},
	"execucao": {"nome": "Execução", "alvo": "inimigo", "alcance": 1, "dano": 20, "execucao": 0.4,
		"recarga": 2, "anim": "melee",
		"desc": "Corpo a corpo. 20 de dano, dobrado se o alvo estiver abaixo de 40% da vida."},
	"flecha": {"nome": "Flecha", "alvo": "inimigo", "alcance": 6, "dano": 17, "visao": true, "recarga": 0,
		"anim": "projetil", "cor": Color(1.0, 0.9, 0.6),
		"desc": "Alcance 6, precisa de linha de visão. 17 de dano."},
	"chuva_flechas": {"nome": "Chuva de Flechas", "alvo": "area", "alcance": 5, "raio": 1, "dano": 12,
		"recarga": 3, "anim": "arco", "cor": Color(1.0, 0.85, 0.5),
		"desc": "Área 3x3 a até 5 quadrados. 12 de dano em cada inimigo."},
	"cura": {"nome": "Cura", "alvo": "aliado", "alcance": 4, "cura": 30, "visao": true, "recarga": 0,
		"anim": "projetil", "cor": Color(0.5, 1.0, 0.55),
		"desc": "Cura 30 de vida de um aliado (ou de si) a até 4 quadrados."},
	"espinhos": {"nome": "Espinhos", "alvo": "inimigo", "alcance": 4, "dano": 12, "efeito": "enraizar",
		"visao": true, "recarga": 2, "anim": "projetil", "cor": Color(0.4, 0.9, 0.3),
		"desc": "12 de dano e enraíza: o alvo não anda no próximo turno."},
	"torreta": {"nome": "Torreta", "alvo": "vazio", "alcance": 2, "invoca": "torreta", "recarga": 4,
		"anim": "invocar",
		"desc": "Monta uma torreta (45 de vida) que atira no inimigo mais próximo ao fim de cada turno do engenheiro. Uma por vez."},
	"granada": {"nome": "Granada", "alvo": "area", "alcance": 4, "raio": 1, "dano": 16, "recarga": 2,
		"anim": "arco", "cor": Color(1.0, 0.55, 0.2),
		"desc": "Área 3x3 a até 4 quadrados. 16 de dano em cada inimigo."},
}
