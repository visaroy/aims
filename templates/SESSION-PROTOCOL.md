# AIMS — AI Session Management System

**Version**: 4.2
**Last Updated**: 2026-07-04
**Author**: The AIMS authors
**Rename**: 2026-07-03 system przemianowany z SMS na AIMS; stare komendy `sms-*` działają jako aliasy `aims *`
**v4.2 (2026-07-04)**: `--scope` w aims start, wiek+scope w aims list, auto-wiersz rejestru w aims publish, pre-push guard na main, podział CONTEXT.md (rdzeń + `context/ARCHIVE-*`)

## Zasada główna

AIMS v4 używa Git branches/worktrees zamiast markerów `.active`. Dirty `$AIMS_HOME` nigdy nie blokuje rozpoczęcia innej pracy. Agent pracuje w osobnym checkoutcie `$AIMS_HOME/.worktrees/<session-id>/` na branchu `ai/<session-id>` i często commit+pushuje swój branch.

## Gdzie jest checkout agenta

```text
$AIMS_HOME/                         # main checkout, stabilna pamięć
$AIMS_HOME/.worktrees/<session-id>/  # checkout agenta, branch ai/<session-id>
```

## Aktywna sesja

Aktywna sesja = istnieje remote branch `origin/ai/<session-id>`.

Nie ma obowiązkowych markerów `.active`. Obecność i scope sesji są w:

```text
sessions/work/<session-id>/metadata.json
```

## Start sesji

```bash
cd $AIMS_HOME
aims start <project> <topic> <agent> --scope host:server1,repo:my-repo   # scope obowiązkowy
```

Skrypt:
1. tworzy `session-id`,
2. tworzy branch `ai/<session-id>` z `origin/main`,
3. tworzy worktree `$AIMS_HOME/.worktrees/<session-id>/`,
4. tworzy `sessions/work/<session-id>/metadata.json` (z podanym `scope`),
5. commit+pushuje branch agenta.

Po starcie agent przechodzi do worktree i pracuje tylko tam.

**⚠️ Dyscyplina cwd**: KAŻDA komenda edytująca pliki sesji musi być uruchamiana w worktree
(ścieżki bezwzględne albo jawne `cd` w tej samej komendzie). Edycja w `$AIMS_HOME` na main = błąd;
pre-push guard zablokuje push, ale nie edycję.

## Czytanie pamięci na start (progressive loading)

1. `CONTEXT.md` — TYLKO rdzeń (~20 KB): mandaty + ostatnie wpisy + tabela "jak doczytać więcej"
2. `<project>/STATE.md` — stan i TODOs twojego projektu (obowiązkowe)
3. `context/ARCHIVE-*.md` — starsza historia, TYLKO gdy temat sesji tego wymaga: `grep -il '<temat>' $AIMS_HOME/context/`
4. NIE ładuj całych archiwów ani starych sesji "na zapas".

## Praca w trakcie sesji

Agent zapisuje bieżące informacje w:

```text
sessions/work/<session-id>/
├── metadata.json
├── prompt-log.md
├── worklog.md
├── commands.md
├── tests.md
└── final-summary.md
```

Zapis bieżący:

```bash
./scripts/aims save
```

`aims save` commit+pushuje branch `ai/<session-id>`. Nie dotyka main.

## Zakończenie sesji

Agent uzupełnia `final-summary.md`, opcjonalnie aktualizuje właściwe `STATE.md`, `SESSIONS.md`, `CONTEXT.md` w swoim branchu, potem publikuje:

```bash
cd $AIMS_HOME
./scripts/aims publish <session-id>
```

Skrypt publikuje przez osobny publish-worktree, robi merge branchu `ai/<session-id>` do `main`,
**automatycznie dopisuje wiersz rejestru do `SESSIONS.md`** (kolejny `sNNN` liczony na zmergowanym
drzewie — NIE dodawaj wiersza ręcznie), pushuje `main` (z `AIMS_PUBLISH=1` dla pre-push guarda),
usuwa remote branch i lokalne worktree.

Przy konflikcie merge skrypt sprząta po sobie i wypisuje instrukcję: w swoim worktree
`git fetch origin main && git rebase origin/main`, rozwiąż konflikty, `aims save`, ponów publish.

## Higiena sesji

- `aims list` pokazuje wiek każdej sesji i flaguje `⚠️ STALE(>48h)` — takie sesje opublikuj albo usuń
  (`git push origin --delete ai/<sid>` + `git worktree remove`).
- Pre-push guard: `./scripts/aims install-hooks` instaluje hook blokujący bezpośredni push na `main`
  (wspólny dla wszystkich worktree). Po klonie/restore uruchom raz.
- `CONTEXT.md` rdzeń: max ~20 KB / 10 wpisów; najstarsze wpisy przenoś 1:1 do `context/ARCHIVE-<rok>-H<n>.md`.
  Zakaz wklejania dumpów komend i treści per-projekt (te → `<project>/STATE.md`).

## Konflikty

Nie blokuje:
- dirty `$AIMS_HOME`,
- aktywny branch innego agenta,
- nieopublikowana sesja innego agenta,
- ten sam projekt bez overlapping scope.

Blokuje tylko realny konflikt pracy:
- ten sam host,
- ta sama VM/CT,
- ten sam repo kodu/IaC,
- ten sam plik konfiguracyjny,
- ta sama usługa produkcyjna,
- ten sam publiczny dokument, który ma być edytowany równocześnie.

## Lista aktywnych sesji

```bash
cd $AIMS_HOME
./scripts/aims list
```

## Reguły plików

- `$AIMS_HOME` na `main` służy do czytania i publikacji końcowej.
- Agent nie pracuje w checkoutcie `$AIMS_HOME` na main.
- Agent pracuje w `$AIMS_HOME/.worktrees/<session-id>/`.
- `.worktrees/` jest ignorowane przez git.
- W trakcie pracy agent preferuje własny katalog `sessions/work/<session-id>/`.
- Wspólne pliki (`STATE.md`, `SESSIONS.md`, `CONTEXT.md`) aktualizuje dopiero pod koniec sesji w swoim branchu.

## Kompatybilność

Stare `.active/.done` markery są legacy i nie blokują pracy. `scripts/session-preflight` jest legacy helperem i nie może blokować rozpoczęcia pracy w AIMS v4.

Komendy `scripts/sms-start`, `sms-save`, `sms-publish`, `sms-list` to aliasy legacy (od 2026-07-03) wywołujące odpowiedniki `aims *` — agenci ze starymi instrukcjami nadal działają. Nowe instrukcje używają wyłącznie `aims *`.

**Remember**: branch jest sesją. Worktree jest checkoutem agenta. Main nie jest miejscem pracy aktywnego agenta.
