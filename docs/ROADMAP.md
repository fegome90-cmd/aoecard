# AoECard — Roadmap ejecutivo

> **Fuente de verdad estratégica.** M0-M10 (del roadmap original) + estado real verificado contra el código.
> El detalle táctico de cada milestone vive en `docs/sprint-<milestone>/tasklist.md`.
> Última actualización: 2026-06-19.

## Estado de hitos (2026-06-19)

| Milestone | Estado | Cobertura |
|---|---|---|
| **M0** — Congelar baseline y reglas | 🟡 Parcial | git tag `v0.6-baseline` pendiente; reglamento mínimo ejecutable pendiente |
| **M1** — Rules Fidelity | 🔴 En progreso (2/14 items done) | M1-1, M1-3, M1-4 ✅; 9 abiertos; ver `docs/sprints/m1-rules-fidelity/tasklist.md` |
| **M2** — Legal Actions | ⏳ Pendiente | bloqueado por M1 |
| **M3** — Eventos y replay | ⏳ Pendiente | bloqueado por M1/M2 |
| **M4** — Partida humana en terminal | ⏳ Pendiente | bloqueado por M2/M3 |
| **M5** — IA heurística | ⏳ Pendiente | bloqueado por M4 |
| **M6** — Vertical slice jugable | ⏳ Pendiente | gate de jugabilidad real |
| **M7** — Aplicación macOS | ⏳ Pendiente | post-M6 |
| **M8** — Entorno neuronal | ⏳ Pendiente | post-M6 |
| **M9** — Imitación, PPO y liga | ⏳ Pendiente | post-M8 |
| **M10** — Laboratorio de meta | ⏳ Pendiente | post-M9 |

**Punto de juego funcional**: M6. M7 agrega presentación; M8-M10 lo convierten en un sistema tipo "DeepMind pequeño".

---

## M0 — Congelar baseline y reglas

* Crear una referencia estable de v0.6 (git tag `v0.6-baseline`).
* Escribir el reglamento mínimo ejecutable (`docs/reglamento-minimo.md`).
* Definir fases, pagos, combate, información oculta y victoria.
* Identificar qué cartas entran al primer pool jugable.

**Gate**: cada carta incluida tiene un efecto tipado y una interpretación única.

**Estado**: 🟡 tag pendiente; reglamento pendiente. Es la fase `m0-baseline-freeze` del sprint M1.

---

## M1 — Rules Fidelity

> **Detalle completo**: `docs/sprints/m1-rules-fidelity/tasklist.md` (reality-check con evidencia file:line, dependency graph, effort summary).

Corregir antes de cualquier nuevo balance. **Estado real (2026-06-19)**:

### ✅ Resueltos (3/14)
* **M1-1** Eliminar una sola copia al jugar — `firstIndex(of:)`+`remove(at:)` (commit `cb837be`, archived)
* **M1-3** IDs deterministas — commit `f1e9298` (REL-03); observable-level
* **M1-4** Un Recurso por turno — flag interno + reset + 3-guard chain (commit `82c6623`, archived); + fix producer-side `StrategyAI.legalActions` (commit `415d349`)

### 🔴 Abiertos — críticos (8)
* **M1-2** Recursos iniciales duplicados — `makePlayer` no filtra `deck.empire` (`m1-starting-deck-integrity`, Phase 1 front)
* **M1-6** Tácticas gratuitas — `playTactic` no llama `Economy.solve/commit`; CRÍTICO (Phase 4)
* **M1-7** Strongholds sin habilidades reales + bug Mongol-flavor universal (línea 443); CRÍTICO (Phase 4)
* **M1-8** Edificios sin Provincia + `accumulateActiveEffects` solo atacante (línea 509) (Phase 3)
* **M1-10** `DestinyInPlay` sin campo defense — la data YAML se pierde (Phase 3)
* **M1-11** `LiveCounters` global, no A/B — métricas mezclan jugadores (Phase 5)
* **M1-12** `generic_modifier` en 37 sitios (Phase 1)
* **M1-5** Victoria ignorando el YAML — `checkVictory` hardcodeado (Phase 6)

### 🔴 Abiertos — instrumentación (1)
* **M1-13** `state.round` nunca incrementado; `cardsPlayed` cuenta combates; `keywordUses` doble-contado; `deadCardsCount`/`deadTurns` hardcoded 0 (Phase 5)

### Gate de M1

*"1.000 partidas aleatorias sin crash, acciones ilegales ni divergencias deterministas."*
* No crash: 89 unit tests pasan; harness 1k pendiente.
* No illegal actions: **falla hoy** (M1-2/6/7/8/13).
* No determinism divergence: ✓ observable-level (UUID tech-debt pendiente para byte-identical).

**Camino crítico**: Phase 0 (reglamento) → Phase 1 (M1-2 → M1-12) → Phase 4 (tactics/stronghold) → Phase 6 (victory + 1000 games).

**⚠ No reanudar balance de cartas hasta que el gate de M1 pase.** El motor aún malrepresenta: tamaño de mazo, coste de tácticas, stronghold, defensa de edificios/destinos, métricas por jugador.

---

## M2 — Legal Actions

Crear una única frontera entre reglas y decisiones:

* `GameAction`
* `LegalActionService`
* `DecisionProvider`
* `PlayerView`
* información pública y privada
* rechazo de acciones inválidas

**Gate**: RandomAI completa 10.000 partidas y nunca ve la mano rival.

**Bloqueado por**: M1 (las reglas deben ser fieles antes de formalizar la frontera legal/ilegal).

> Nota M1-4: el fix de `StrategyAI.legalActions` que aterrizó en M1 (commit `415d349`) ya movió el primer criterio de legalidad (one-resource-per-turn) al productor. M2 formaliza todo ese contrato.

---

## M3 — Eventos y replay

Registrar toda modificación de estado: robo, pagos, despliegues, habilidades, batallas, tácticas, daño, captura, ruptura, victoria.

**Gate**: semilla + acciones reproducen exactamente el mismo estado y log.

**Bloqueado por**: M1 (determinismo observable), M2 (action surface estable).

> Nota: el tech-debt de `EntityID` determinista (para byte-identical, no solo observable) debería resolverse acá o antes — M3 promete "exactamente el mismo estado y log", lo que exige más que "observable results".

---

## M4 — Partida humana en terminal

```bash
swift run SimCLI play \
  --human mongoles \
  --opponent britanos \
  --ai random \
  --seed 42
```

La terminal debe permitir: ver mesa y mano, elegir pagos, declarar batalla, seleccionar participantes, jugar tácticas, pasar, conceder, guardar y continuar.

**Gate**: una persona termina diez partidas sin intervención del desarrollador.

**Bloqueado por**: M2 (PlayerView), M3 (save/load + replay).

---

## M5 — IA heurística

Crear una IA explicable con perfiles:

* Mongoles: Ruta-Incursión, Horda Mangudai, Khan Tempo.
* Britanos: Control de Colinas, Empuje de Ariete, Cielo Oscurecido.
* Mapuches: Anfibio, Malón, Toqui Midrange.

**Gate**: supera consistentemente a RandomAI, reserva defensa y puede cerrar partidas.

**Bloqueado por**: M4 (necesita jugabilidad humana para calibrar perfiles).

> Nota M1-7: el fix del stronghold (cuando aterrice) es prerrequisito de los perfiles Mongoles (Khan Tempo depende de habilidad real de Stronghold).

---

## M6 — Vertical slice jugable

Alcance reducido: tres civilizaciones, conquista como única victoria, tres a cinco Destinos, 18-24 cartas de Imperio funcionales por civ, 10-14 tácticas funcionales por civ, tres estrategias reales por civ, sin Maravillas/Reliquias/Rey.

**Gate**: primera versión realmente jugable de AoECard.

**Bloqueado por**: M5.

> Nota M1-12: la limpieza de `generic_modifier` (banned vs tipado) define cuántas cartas llegan realmente funcionales al slice. La decisión banned-first (recomendada en el tasklist) reduce el pool pero acelera M6.

---

## M7 — Aplicación macOS

SwiftUI después de cerrar el vertical slice. La interfaz solo representa `PlayerView` y envía `GameAction`. No contiene reglas.

**Bloqueado por**: M6.

---

## M8 — Entorno neuronal

Reglas en Swift, entrenamiento en Python/PyTorch. El entorno entrega: observación, máscara de acciones legales, recompensa, estado terminal.

**Gate**: múltiples partidas paralelas y ninguna filtración de información rival.

**Bloqueado por**: M6.

---

## M9 — Imitación, PPO y liga

1. Imitación de la IA heurística.
2. PPO con autojuego.
3. Checkpoints históricos.
4. Liga de agentes especializados.
5. Evaluación Elo y matrices por estrategia.

**Bloqueado por**: M8.

---

## M10 — Laboratorio de meta

En cada sesión: detectar estrategia dominante, detectar estrategia muerta, identificar matchup o loop problemático, modificar máximo tres o cuatro variables, entrenar y enfrentar agentes nuevos contra históricos, validar con jugadores humanos.

**No se balancean cartas aisladas.** Se balancean estrategias, matchups y experiencia de juego.

**Bloqueado por**: M9.

---

## Tech-debt que afecta al roadmap

Registrados en `docs/architecture/tech-debt.md` y en `openspec/changes/archive/`:

| Item | Origen | Impacto en roadmap |
|---|---|---|
| `EntityID` determinista (vs UUID) | M1-1 spec scope-down | M3 necesita byte-identical replay; reducir el claim o implementar EntityID |
| `resolve()` complejidad 31 | audit AF-05 (commit `c04f01d`) | M5/M8 legibilidad del resolver |
| `writeRun` 8 params | audit | estilo; no bloquea |
| `producesKind` 3-tuple | audit | estilo; no bloquea |
| `isReady` 3-writer fragility (AF-02) | audit | tocado por M1-4 (ortogonal); M1-7 lo puedeagravar si stronghold toca tap |
| Suite wall-clock 140s→640s local | M1-1 archive-report | M1-GATE 1000 games será caro; considerar CI runner perf |

---

## Cómo usar este documento

1. **Para estrategia (¿qué milestone sigue?)**: lee la tabla de estado de hitos + la sección del milestone objetivo.
2. **Para táctica (¿qué item ahora?)**: ve al `docs/sprint-<milestone>/tasklist.md` correspondiente — ahí está el detalle con evidencia file:line, dependencias y esfuerzo.
3. **Para histórico**: el changelog de cada tasklist + los `openspec/changes/archive/` son el audit trail.
4. **Actualizar después de cada SDD change archived**: mueve la fila del milestone en la tabla de estado, y abre/cierra items en el tasklist del milestone activo.
