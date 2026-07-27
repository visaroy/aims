# AIMS — AI Session Management System

**Autor**: The AIMS authors · **Wersja**: 2026-07-17 · **Repo**: `<your-data-repo-url>`

Kanoniczna dokumentacja AIMS. Reguły operacyjne (egzekwowane przez agentów) żyją w `AI.md`
(Rule #5, #16–#21). Ten plik wyjaśnia **jak system działa jako całość**.

---

## 1. Czym jest AIMS i po co

System pracy wielu agentów AI (claude / codex / opencode / gemini) na wielu maszynach (macOS, Linux),
gdzie **każda jednostka pracy = gałąź git** (`ai/<session-id>`) w izolowanym worktree. Cel: równoległa
praca bez konfliktów, pełna historia, przenośność między maszynami i agentami, odtwarzalność po awarii.

**Źródło prawdy: `origin` (GitHub).** Maszyny nie łączą się ze sobą — każda tylko **push/pull do origin**.
Dlatego „nikt nie ma dostępu do Maca" NIE jest problemem: Mac wypycha do GitHuba, inne maszyny stamtąd
ściągają. Sesja nie żyje „na maszynie X" — żyje na origin; maszyna to tylko miejsce ostatniego push.

## 2. Dwie warstwy — rozróżnienie fundamentalne

| Warstwa | Co to | Gdzie | Przenośna? |
|---|---|---|---|
| **Praca** | gałąź `ai/<sid>`, worktree, pliki sesji, worklog, commity | origin (git) | ✅ TAK — każda maszyna, każdy agent |
| **Kontekst agenta** | transkrypt/rozumowanie (np. `~/.claude/…jsonl`) | lokalnie, `.gitignore` | ❌ NIE — nieprzenośny, harness-specific |

**Konsekwencja**: przejmując sesję, kontynuujesz z **ARTEFAKTÓW** (worklog + commity + plan), NIGDY
z głowy poprzedniego agenta. Dlatego commity i worklog muszą być samowystarczalnym handoverem.
`claude --resume` odtwarza warstwę B, ale to funkcja Claude Code, NIE mechanizm AIMS (nie działa
dla codex/opencode/gemini, przywiązana do jednej maszyny).

## 3. Cykl życia sesji

```
                    aims start <projekt> <temat> <agent>
                              │  (tworzy gałąź ai/<sid> + worktree z origin/main)
                              ▼
        ┌──────────────  PRACA w worktree  ──────────────┐
        │  aims save  = checkpoint plików sesji + push   │  (można wielokrotnie)
        └──────────────────────┬─────────────────────────┘
                               │
          ┌────────────────────┼─────────────────────────┐
          ▼                    ▼                          ▼
   aims handoff         aims publish              (porzucenie)
   „przekaż maszynę"     „zamknij, scal do main"    usuń gałąź
   status=handoff        rejestr sNNN=done          bez merge
   push KOMPLET          gałąź usunięta z origin
          │
          ▼
   na DRUGIEJ maszynie:  aims adopt <sid>
   (fetch z origin, worktree z istniejącej gałęzi, kontynuacja)
```

## 4. Komendy

| Komenda | Gdzie uruchomić | Co robi |
|---|---|---|
| `aims start <projekt> <temat> [agent] [--scope ...]` | `$AIMS_HOME` | Nowa sesja: gałąź `ai/<sid>` + worktree z `origin/main` + szablon `metadata.json` (w tym pusty blok `environment`). |
| `aims save` | w worktree | Checkpoint: `git add -A` (CAŁY worktree sesji — STATE.md, session-*.md, kod, artefakty) + commit + **push gdy ahead of origin**. Po naprawie 2026-07-18 nie gubi już plików projektu. |
| `aims handoff [notka]` | w worktree | **Przekazanie maszyny** (polecenie USERA). `git add -A` (KOMPLET), commit, push, `status=handoff`. NIE scala do main. |
| `aims handoff <sid>` | `$AIMS_HOME/.worktrees/` | Przekazanie jednej wskazanej lokalnej sesji bez ręcznego `cd` do jej katalogu. Waliduje, że worktree, branch `ai/<sid>` i metadata są zgodne, następnie wykonuje zwykły handoff. |
| `aims handoff-all [--yes]` | `$AIMS_HOME` | Przekazanie wszystkich prawidłowych lokalnych worktree’ów. Domyślnie pyta o wpisanie `HANDOFF`; `--yes` jest dla świadomej automatyzacji. NIE scala, nie usuwa worktree’ów i nie force-pushuje. |
| `aims adopt <sid> [--remote]` | `$AIMS_HOME` (dowolna maszyna) | Przejęcie z origin: raport środowiska + guardy, worktree z istniejącej gałęzi, wpis ADOPTED. `--remote` = tylko raport. |
| `aims publish <sid>` | `$AIMS_HOME` | Domknięcie: merge gałęzi → main, wpis rejestru `sNNN`, usunięcie gałęzi z origin. Działa niezależnie od tego, który agent zaczął. |
| `aims list` | `$AIMS_HOME` | Aktywne gałęzie `ai/*` z wiekiem, scope i flagą STALE (>48h). |

## 5. Blok `environment` — handover środowiska pracy

`metadata.json` każdej sesji zawiera `environment`. Sesja dotykająca kodu (nie czysta analiza) MUSI go
wypełnić — to jedyny sposób, by adoptujący agent wiedział, czego potrzebuje, zanim zacznie kodować:

```json
"environment": {
  "code_repos": ["~/code/your-project"],  // repo kodu, ZWYKLE inne niż $AIMS_HOME
  "toolchain":  [],                                            // tylko narzędzia potrzebne LOKALNIE
  "exec_host":  "",                                            // host gdzie środowisko stoi; puste = przenośne
  "setup":      "git pull",                                    // przygotowanie
  "test":       "CI: GitHub Actions (PR)"                      // "local: <cmd>" LUB "CI: ..."
}
```

**Rozróżnienie `test: local` vs `CI` jest krytyczne.** Sesja może NIE mieć toolchainu lokalnie, bo
weryfikuje przez CI (realny przypadek: kod Fluttera edytowany na hoście bez Fluttera, buildy zielone
w GitHub Actions). `aims adopt` czyta ten blok, sonduje bieżący host (`command -v`) i rekomenduje
adopcję lokalną vs zdalną (`--remote`) vs doinstalowanie.

## 6. Guardy i bezpieczeństwo

- **Żywy pisarz** (`aims adopt`): jeśli gałąź ruszana < 120 min, a `status ≠ handoff` → ostrzeżenie
  (ryzyko dwóch pisarzy). Przy `status=handoff` → wyciszone (źródło jawnie zwolniło).
- **Granica origin** (`aims adopt`): raport mówi wprost, że pokazuje stan WYPCHNIĘTY — niewypchnięta
  praca maszyny źródłowej nie jest widoczna. Dlatego przed przesiadką: `aims handoff` (push kompletu).
- **Odmowa** (`aims adopt`): sesja scalona/usunięta → nie ma czego adoptować.
- **Push na `main` zablokowany** hookiem `pre-push` — wyłącznie przez `aims publish`.
- **`restore.sh` NIGDY z worktree** — tylko z kanonicznego `$AIMS_HOME` (uruchomienie z worktree zniszczyło
  `$AIMS_HOME` 2026-07-15).
- **`$AIMS_HOME` NIGDY nie kopiować** między maszynami — tylko `git clone` + `restore.sh` (kopia = ścieżki
  obcej maszyny + cichy dryf).
- **Sekrety**: do sesji NAZWA zmiennej i lokalizacja, NIGDY wartość (Rule #20). Sekrety w
  `$AIMS_HOME/credentials/*.env` (gitignored). `validate-no-secrets.sh` skanuje też `.md`.

## 7. Reguły w AI.md (mapa)

| Rule | Temat |
|---|---|
| #5 | Session Protocol — start/save/publish, izolacja worktree, konflikty scope |
| #16 | Dokumentacja natychmiast po zmianie (inline: co, dlaczego, logika) |
| #17 | Testy przed zamknięciem sesji (unit + integration + manual acceptance) |
| #18 | Terminologia: „dokumentacja" vs „zapisz sesję" vs „zapisz i zamknij" — + „przekaż sesję" (handoff) |
| #19 | Konwencje kodu i repo (build/lint/test, gałęzie, nazewnictwo) |
| #20 | Sekrety — nazwa nie wartość; skaner widzi `.md` |
| #21 | Adopcja/kontynuacja cudzej sesji — `aims adopt`; analiza środowiska; artefakty nie kontekst |

## 8. Wiring agentów (kto skąd czyta reguły)

Wszystkie 4 agenty rozwiązują reguły do jednego `AI.md` (przez `restore.sh`):

| Agent | Entry-point | Mechanizm |
|---|---|---|
| claude | `~/.claude/CLAUDE.md` → `../AI.md` | symlink |
| gemini | `~/.gemini/GEMINI.md` → `../AI.md` | symlink |
| codex | `~/.codex/AGENTS.md` → `AI.md` | symlink global (NIE `~/AGENTS.md` — codex nie sięga wyżej niż korzeń projektu) |
| opencode | `~/.claude/CLAUDE.md` (fallback) + `instructions:[~/AGENTS.md, ~/.claude/CLAUDE.md]` | config + fallback |

`doctor.sh` weryfikuje, że każdy entry-point faktycznie rozwiązuje się do `AI.md` (realpath).
