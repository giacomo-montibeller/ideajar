# Plan: Slice 12 — Eliminare un'idea con conferma modal

**Created**: 2026-05-04
**Branch**: main (trunk-based)
**Status**: approved (post review iter-3, 2026-05-04)
**Spec**: `docs/specs/delete-idea.md`

## Build conventions (carried from prior slices)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Every commit** through the `commit-message` skill.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test`. Same gates run in CI on every push.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy in italiano; nuove stringhe vanno appese alla tabella canonica in `docs/conventions.md` nello **stesso commit** che le introduce.

## Goal

Aggiungere alla home LiveView un'azione "Elimina" su ogni card idea, gated da una **modal di conferma** "Eliminare questa idea?" che mostra il titolo dell'idea (HTML-escaped). Conferma → `Ideajar.Ideas.delete_idea/1` (hard delete); il cascade FK già presente sul join `idea_categories` (`on_delete: :delete_all`, migration iniziale) si occupa dei link di categoria. Race con altro device → flash `"Idea già eliminata"` + refresh + focus sicuro su `#add-idea-button`; errore DB inatteso → flash `"Eliminazione non riuscita, riprova"` con `role="alert"` e modal **lasciata aperta** per il retry. Focus post-delete deterministico: card successiva → card precedente (se ultima) → `#add-idea-button` (se lista vuota). Filtri attivi preservati dopo delete. Edit idea fuori scope (slice futura).

## Decisioni architetturali pre-build (post review iter-1)

Queste decisioni sono fissate qui e gli step le applicano meccanicamente. Niente "or equivalent" su scelte strutturali.

- **A1 — Hard delete**: `Repo.delete/1`, niente `deleted_at`. Allineato al "no audit / no created_by" del progetto.
- **A2 — Cascade in DB**: il context `delete_idea/1` non tocca `idea_categories`. Il FK ha già `on_delete: :delete_all` dalla migration iniziale (`priv/repo/migrations/20260503000001_initial_schema.exs:52`). **Nessuna nuova migration.** Il test cascade è comportamentale (delete idea → query `idea_categories` per quell'`idea_id` ritorna 0 righe) — agnostico SQLite/Postgres.
- **A3 — Domain API atomicity-safe** (revisione iter-1+iter-2):
  ```elixir
  @spec delete_idea(integer()) :: {:ok, Idea.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def delete_idea(id) when is_integer(id) do
    case Repo.get(Idea, id) do
      nil -> {:error, :not_found}
      idea -> delete_struct_safe(idea)
    end
  end

  @doc false
  # Test seam: extracted so F12 can drive a true concurrent-delete scenario
  # against a stale struct without going back through `Repo.get/2` (which
  # would short-circuit into the nil-guard branch).
  def delete_struct_safe(%Idea{} = idea) do
    try do
      Repo.delete(idea)
    rescue
      Ecto.StaleEntryError -> {:error, :not_found}
    end
  end
  ```
  Il `try/rescue` chiude la finestra di race in cui due processi superano `Repo.get/2` e il secondo `Repo.delete/1` solleva `Ecto.StaleEntryError`. Mappato a `{:error, :not_found}` perché lato chiamante è semanticamente identico. L'helper `delete_struct_safe/1` è marcato `@doc false` (test-only API): F12 lo invoca direttamente per esercitare la branch rescue su una struct stale, scenario non riproducibile via `delete_idea/1` (che ri-fa `Repo.get` e cadrebbe nel nil-guard).
- **A4 — Stato modal in LV**: nuovo assign `@deletion :: nil | %{id: integer(), title: String.t()}`. Quando non-nil la modal è renderizzata (HEEx conditional, no CSS-hidden). Il titolo viene letto **dall'assign `@ideas`** già caricato (no DB hit a `request_delete`).
- **A5 — Markup modal**: HEEx **inline** in `index.html.heex` (no LiveComponent/function-component dedicato — KISS, una sola modal in tutto il LV). Contiene `role="dialog"`, `aria-modal="true"`, `aria-labelledby="delete-modal-title"`, `aria-describedby="delete-modal-body"`, `id="delete-modal"`.
- **A6 — Chiusura modal: tre paths**:
  - `Annulla` → `phx-click="cancel_delete"`.
  - `Esc` → `phx-window-keydown="cancel_delete"` `phx-key="Escape"` montato sul dialog wrapper.
  - Backdrop → `<div class="backdrop" phx-click="cancel_delete">` **fratello** del dialog interno nel DOM (no nesting), così il click sul dialog non bubble al backdrop senza `stopPropagation`.
  - Tutti e tre gli handler **leggono l'id da `socket.assigns.deletion.id`**, non da params. Motivo (revisione iter-1): `phx-window-keydown` non garantisce di propagare `phx-value-*` del wrapper, e l'assign è comunque la fonte di verità (la modal è aperta solo se `@deletion != nil`). I `phx-value-id` rimangono sui bottoni `Annulla`/backdrop solo come hint diagnostico.
- **A7 — Focus management**: stesso pattern di slice 2 — `push_event("ideajar:focus", %{to: "..."})` dal server + listener in `assets/js/app.js` esistente. Payload key è `to`, allineato a `lib/ideajar_web/live/idea_live/index.ex:106`. Targets:
  - apertura modal → `#delete-cancel-btn`
  - chiusura senza delete → `#delete-btn-<id>` della card sorgente
  - successo delete → `#delete-btn-<next.id>` (card successiva), fallback `#delete-btn-<prev.id>` (card precedente, se era l'ultima), fallback `#add-idea-button` (lista vuota).
  - **race con altro device** (revisione iter-1: UX blocker) → `#add-idea-button` (target sicuro: la card sorgente non esiste più, focus al browser default è disorientante per keyboard user).
- **A8 — Test seam per error path**: il LV inietta una `delete_idea_fun` opzionale via assign, **parallelo al pattern esistente** `create_idea_fun` (vedi `lib/ideajar_web/live/idea_live/index.ex:644-648`). Default = `&Ideas.delete_idea/1`. Permette ai test LV di iniettare uno stub che ritorna `{:error, %Ecto.Changeset{}}` per coprire lo scenario "Repo failure" senza dipendere da DB instabile.
- **A9 — `phx-disable-with`** sul bottone `Elimina` con copy `Eliminazione…`. Client-side double-click guard (parallelo a slice 2 `Salvataggio…`). Server-side idempotency via curl fuori scope (2-user app fidata).
- **A10 — Filtri preservati**: dopo `{:ok, _}` il LV chiama il helper `reload_ideas/1` esistente (vedi `mount/3` in `index.ex`) che ricostruisce `opts` dagli assigns dei filtri attivi. Niente `Ideas.list_ideas/0`.
- **A11 — Auth defense-in-depth**: gli handler `request_delete`, `cancel_delete`, `confirm_delete` ereditano la session check del `mount/3` esistente. Test esplicito che un mount con session non valida redirige a `/login?return_to=%2F`.
- **A12 — Race a `request_delete`**: se l'evento arriva con un `id` non presente in `@ideas` (race tab/altro device tra render e click), il LV ignora silenzioso (no modal aperta, `{:noreply, socket}`). Solo `confirm_delete` su id assente solleva il flash `"Idea già eliminata"` + refresh — è quello il punto in cui l'utente ha esplicitamente richiesto l'azione.
- **A13 — Affordance bottone trash** (revisione iter-1: WCAG 2.4.6):
  - Posizione: in alto a destra di ogni card.
  - Markup: `<button type="button" id="delete-btn-<id>" aria-label="Elimina idea" phx-click="request_delete" phx-value-id={idea.id} class="trash-btn">🗑<span class="sr-only">Elimina</span></button>`. Lo `<span class="sr-only">` è ridondante con `aria-label` ma copre tooling che ignora `aria-label` su elementi senza testo visibile (es. ricerche full-text).
  - Hit area minima 44×44 CSS px (WCAG 2.5.5) imposta da Tailwind classes (`min-w-[44px] min-h-[44px]`).
- **A14 — Bottone `Elimina` danger-style** (revisione iter-1: WCAG 1.4.3): classi Tailwind che producono background rosso con contrasto **≥4.5:1** sul testo bianco (es. `bg-red-700 text-white hover:bg-red-800`). La scelta concreta delle classi va verificata in V1a Lighthouse — se < 4.5:1, salire di livello.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/delete-idea.md`. Aggiunte AC fini-grana per la non-atomicità (F12), per il branch error-DB (F9), per i target di focus (F10).

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano come test ExUnit (`Phoenix.LiveViewTest` per il LiveView, `DataCase` per il context).
- [ ] **F2** — `Ideas.delete_idea/1` con id valido → `{:ok, %Idea{}}`; `Repo.get/2` post-delete ritorna `nil`.
- [ ] **F3** — `Ideas.delete_idea/1` con id inesistente → `{:error, :not_found}`. Nessuna chiamata a `Repo.delete/1` (verificabile via stub o sandbox log).
- [ ] **F4** — `Ideas.delete_idea/1` su un'idea con N link in `idea_categories` rimuove la riga `ideas` e tutte le N righe in `idea_categories` per quell'`idea_id`. Le righe in `categories` restano invariate.
- [ ] **F5** — La modal renderizza il titolo dell'idea HTML-escaped (test esplicito su titolo `<script>alert(1)</script>`: il rendering contiene `&lt;script&gt;...` e non contiene il literal).
- [ ] **F6** — Click su `Annulla`, click su backdrop, tasto `Esc` chiudono la modal senza effetto sul DB.
- [ ] **F7** — Dopo delete riuscito: flash `"Idea eliminata"` con `role="status"`, lista rerender via `reload_ideas/1` (filtri preservati), `assign(deletion: nil)`.
- [ ] **F8** — Race con altro device: `confirm_delete` su id già rimosso → flash `"Idea già eliminata"` con `role="status"`, lista rerender, focus a `#add-idea-button` (A7), no crash.
- [ ] **F9** — Errore DB inatteso (stub di `delete_idea_fun` che ritorna `{:error, %Ecto.Changeset{}}`): flash `"Eliminazione non riuscita, riprova"` **con `role="alert"`**, modal resta visibile (`@deletion` invariato), lista invariata, processo LV non crasha.
- [ ] **F10** — Focus targets verificati via assertion su `push_event("ideajar:focus", %{to: ...})`:
  - `request_delete` → `#delete-cancel-btn`
  - `cancel_delete` (tutti i paths) → `#delete-btn-<id>` della card sorgente
  - `confirm_delete` con successor → `#delete-btn-<next.id>`
  - `confirm_delete` su ultima card di lista non vuota → `#delete-btn-<prev.id>`
  - `confirm_delete` su unica card → `#add-idea-button`
  - `confirm_delete` su id già rimosso (race) → `#add-idea-button`
- [ ] **F11** — `request_delete` con `id` non presente in `@ideas` → `{:noreply, socket}` silenzioso (no modal aperta, no crash).
- [ ] **F12** — Atomicità race: due `delete_idea/1` in parallelo sullo stesso id non solleva `Ecto.StaleEntryError`. Il secondo riceve `{:error, :not_found}`. Verificato via test che chiama direttamente `Repo.delete!/1` su un'entità in-memory già persistita e poi `Ideas.delete_idea/1` con lo stesso id (simula la race).
- [ ] **F13** — Bottone `Elimina` ha `phx-disable-with="Eliminazione…"` (assertion sull'attributo, non solo sulla classe).

### Security

- [ ] **S1** — XSS su title nel body modal: titolo `<script>alert(1)</script>` renderizzato come testo escapato.
- [ ] **S2** — Auth: mount con session non valida → redirect a `/login?return_to=%2F`. Test esplicito.
- [ ] **S3** — Idempotency soft: `phx-disable-with` + secondo `confirm_delete` riceve `{:error, :not_found}`. Server-side guard via curl esplicitamente fuori scope.

### Operational / data

- [ ] **O1** — Nessuna nuova migration. Cascade asserito comportamentalmente in F4.

### A11y / Validation venue

- [ ] **V1** — 2 screenshot mobile-viewport (uno con modal aperta, uno con lista post-delete o empty state) committati in `docs/screenshots/slice-12/`.
- [ ] **V1b** — Manual keyboard walkthrough verificato: Tab → trash button → Enter → modal aperta con focus su `Annulla` → Esc → modal chiusa con focus tornato al trash. Non documentato come file separato; verifica diretta in `mix phx.server`.

### Documentation

- [ ] **D1** — `docs/conventions.md` "UI copy" table aggiornata con le stringhe canoniche (vedi tabella sotto), nello stesso commit che introduce le stringhe in HEEx.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Aria-label bottone trash su card | `Elimina idea` |
| Modal title | `Eliminare questa idea?` |
| Modal body (template) | `Elimina l'idea "<title>". L'idea sarà rimossa definitivamente.` |
| Bottone modal annulla | `Annulla` |
| Bottone modal conferma (danger) | `Elimina` |
| `phx-disable-with` su `Elimina` | `Eliminazione…` |
| Flash success (`role="status"`) | `Idea eliminata` |
| Flash race (`role="status"`) | `Idea già eliminata` |
| Flash errore DB (`role="alert"`) | `Eliminazione non riuscita, riprova` |

> Tutte le stringhe usano l'apostrofo dritto ASCII `'` (U+0027). La copy table di `docs/conventions.md` è la sorgente canonica; HEEx escape `\'` dove serve dentro stringhe Elixir.

## User-Facing Behavior

> Verbatim da `docs/specs/delete-idea.md`. Vedi spec per i 13 scenari completi (Background con 3 idee fixture; affordance; apertura; XSS; chiusura via 3 paths; happy path; empty state; previous-card focus; cascade; race; in-flight disabled; DB error; auth; filter preservation).

## Steps

### Step 1: Domain `Ideas.delete_idea/1` con cascade + race-atomicity

**Complexity**: standard
**RED**: 4 test in `test/ideajar/ideas_test.exs`:
  1. happy path — `delete_idea(idea.id)` → `{:ok, %Idea{}}`; `Repo.get(Idea, id)` post → `nil`.
  2. not_found — `delete_idea(99_999)` → `{:error, :not_found}`.
  3. cascade (F4) — fixture: idea + 2 categorie + 2 righe `idea_categories`. `delete_idea(idea.id)` → query diretta `idea_categories` per quell'`idea_id` ritorna `[]`. Le 2 categorie esistono ancora.
  4. race-atomicity (F12) — il test deve **realmente** entrare nel ramo `try/rescue Ecto.StaleEntryError` (non nel nil-guard `Repo.get → nil → :not_found`). Setup: idea persistita. Esecuzione:
     ```elixir
     # Tieni un Idea struct "stale" via due Repo.get paralleli prima dei delete.
     [a, b] =
       Task.await_many([
         Task.async(fn -> Repo.get(Idea, id) end),
         Task.async(fn -> Repo.get(Idea, id) end)
       ])
     # Forza la race: il primo delete passa, il secondo riceverebbe StaleEntryError
     # se il dominio non lo rescue-asse. Bypassa Ideas.delete_idea/1 (che
     # ri-fa Repo.get) — invochiamo direttamente il helper privato che
     # incapsula il try/rescue, oppure rendiamo il try/rescue isolabile via
     # uno helper esposto (`@doc false`) `Ideas.__delete_struct_safe__/1`.
     {:ok, _} = Ideas.__delete_struct_safe__(a)
     assert {:error, :not_found} = Ideas.__delete_struct_safe__(b)
     ```
     Implementazione GREEN: estrai il `try/rescue` in un private+`@doc false` helper `delete_struct_safe/1` chiamato da `delete_idea/1` dopo il `Repo.get`. Il test attacca direttamente quel helper. **Razionale**: il test esercita il try/rescue su un'istanza realmente stale, cosa non possibile passando solo l'`id` (che farebbe sempre re-`Repo.get` e cadrebbe nel nil-guard). L'helper privato resta non-API per i chiamanti normali (no scope creep — è solo test seam interno).
**GREEN**: aggiunge `delete_idea/1` come da blocco di codice in A3. Niente perf fixture (drop di P1 — single SELECT + DELETE è trivialmente veloce a scala 2-user).
**REFACTOR**: aggiorna `@moduledoc` con la riga "Slice 12 adds `delete_idea/1`. Cascade su `idea_categories` is delegated to the FK on_delete: :delete_all (initial migration); the context does not touch the join table. The try/rescue closes the concurrent-delete window without leaking `Ecto.StaleEntryError` to callers."
**Files**: `lib/ideajar/ideas.ex`, `test/ideajar/ideas_test.exs`
**Commit**: `Add Ideas.delete_idea/1 with cascade and race-safe atomicity`

### Step 2: Bottone trash su ciascuna card + UI copy seed

**Complexity**: standard
**RED**: in `index_test.exs`:
  - mount con 3 idee fixture; render contiene 3 `button[aria-label="Elimina idea"][type="button"][phx-click="request_delete"]`.
  - ciascuno ha `phx-value-id` corrispondente all'id dell'idea, `id="delete-btn-#{idea.id}"`, e contiene il fallback `<span class="sr-only">Elimina</span>`.
  - in `test/ideajar/docs_test.exs` (verifica esistenza file; se assente, crea minimal): assertion che `docs/conventions.md` contiene la stringa `Elimina idea` (l'unica copy introdotta da questo step).
**GREEN**: in `index.html.heex`, dentro il template della card aggiunge il bottone come da A13. Aggiunge stub `def handle_event("request_delete", _, s), do: {:noreply, s}` per evitare crash da "no handler" (verrà espanso in Step 3). Appende la riga `Elimina idea` alla tabella UI copy in `docs/conventions.md`.
**REFACTOR**: nessuno.
**Files**: `lib/ideajar_web/live/idea_live/index.html.heex`, `lib/ideajar_web/live/idea_live/index.ex`, `docs/conventions.md`, `test/ideajar_web/live/idea_live/index_test.exs`, `test/ideajar/docs_test.exs`
**Commit**: `Render delete button on each idea card`

### Step 3: `request_delete` apre la modal con titolo escapato

**Complexity**: standard
**RED**: in `index_test.exs`:
  - "Clicking the delete icon opens the confirm modal" — `render_click(view, "#delete-btn-1")` → render contiene `role="dialog"`, `aria-modal="true"`, `aria-labelledby="delete-modal-title"`, `aria-describedby="delete-modal-body"`. Title contiene `Eliminare questa idea?`, body contiene la stringa templatizzata con il titolo idea.
  - assert focus → `assert_push_event view, "ideajar:focus", %{to: "#delete-cancel-btn"}`.
  - "the dialog body has id delete-modal-body" — assertion sull'id dell'`<p>` per coerenza con `aria-describedby`.
  - **F13 (`phx-disable-with`)** — `assert html =~ ~s|phx-disable-with="Eliminazione…"|` sul bottone `Elimina`.
  - XSS (F5) — fixture con titolo `<script>alert(1)</script>`; render della modal contiene `&lt;script&gt;` e non contiene il literal.
  - F11 — invia `request_delete` con id 99_999; render NON contiene `role="dialog"`, no crash.
  - **NON-bubble check** (verifica R2 di iter-1) — click sul `<div class="dialog">` (id selector) NON rimuove la modal: test esplicito di "click intra-dialog" senza `cancel_delete`.
  - in `test/ideajar/docs_test.exs`: assertion che `docs/conventions.md` ora contiene `Eliminare questa idea?`, `Annulla`, `Elimina`, `Eliminazione…`, e la stringa template del body.
**GREEN**: in `index.ex`:
  1. Aggiunge assign iniziale `:deletion → nil` nel `mount/3` e nel reducer di reload.
  2. Aggiunge `def handle_event("request_delete", %{"id" => raw}, socket)` con int-safe parse (riusa il helper esistente se presente, vedi handler `cycle_filter` di slice 4 — altrimenti definisce un `parse_id/1` privato locale): se trovata in `socket.assigns.ideas` → assign `:deletion` + push_event focus; altrimenti `{:noreply, socket}`.
  3. In `index.html.heex`, **subito dopo** la lista idee:
     ```heex
     <%= if @deletion do %>
       <div role="dialog" aria-modal="true"
            aria-labelledby="delete-modal-title"
            aria-describedby="delete-modal-body"
            id="delete-modal" phx-window-keydown="cancel_delete" phx-key="Escape">
         <div class="backdrop" phx-click="cancel_delete"></div>
         <div class="dialog">
           <h2 id="delete-modal-title">Eliminare questa idea?</h2>
           <p id="delete-modal-body">
             Elimina l'idea "<%= @deletion.title %>". L'idea sarà rimossa definitivamente.
           </p>
           <button id="delete-cancel-btn" type="button" phx-click="cancel_delete">Annulla</button>
           <button type="button" phx-click="confirm_delete"
                   phx-disable-with="Eliminazione…"
                   class="bg-red-700 hover:bg-red-800 text-white">Elimina</button>
         </div>
       </div>
     <% end %>
     ```
  4. Appende all'UI copy table le 5 nuove stringhe introdotte in questo step.
**REFACTOR**: nessuno (il template è breve abbastanza da restare inline; promosso a function-component solo se compare una seconda modal — vedi A5).
**Files**: `lib/ideajar_web/live/idea_live/index.ex`, `index.html.heex`, `docs/conventions.md`, `index_test.exs`, `docs_test.exs`
**Commit**: `Open delete confirmation modal on trash click`

### Step 4: Chiusura modal — Annulla, Esc, backdrop (id da assign)

**Complexity**: standard
**RED**: 3 test paths, ognuno con fixture 3 idee + modal aperta su idea-1:
  - click `#delete-cancel-btn`
  - `render_keydown(view, "cancel_delete", %{"key" => "Escape"})` triggerato sul `#delete-modal`
  - click su `.backdrop`
  Per ognuno: dopo l'evento `@deletion == nil`, modal non in render, count idee invariato, `assert_push_event view, "ideajar:focus", %{to: "#delete-btn-1"}`.
**GREEN**: aggiunge in `index.ex`:
```elixir
def handle_event("cancel_delete", _params, %{assigns: %{deletion: nil}} = socket),
  do: {:noreply, socket}

def handle_event("cancel_delete", _params, %{assigns: %{deletion: %{id: id}}} = socket) do
  socket =
    socket
    |> assign(deletion: nil)
    |> push_event("ideajar:focus", %{to: "#delete-btn-#{id}"})
  {:noreply, socket}
end
```
L'id è letto da `assigns.deletion.id`, **non da params** (vedi A6 — `phx-window-keydown` non garantisce di propagare `phx-value-*`).
**REFACTOR**: nessuno.
**Files**: `index.ex`, `index_test.exs`
**Commit**: `Close delete modal via Annulla, Esc, or backdrop`

### Step 5: `confirm_delete` happy path con focus successor

**Complexity**: standard
**RED**: in `index_test.exs`, 3 scenari fixture-driven:
  - "Confirming the deletion removes the idea" — fixture 3 idee, apri modal su idea-1, `render_click "#delete-modal button[phx-click=confirm_delete]"` → `assert html =~ "Idea eliminata"`, `assert html =~ ~s|role="status"|` sul flash, `refute html =~ "Mare a Sirolo"`, count = 2, `assert_push_event view, "ideajar:focus", %{to: "#delete-btn-2"}`.
  - "Deleting the last card focuses previous" — apri su idea-3 → focus su `#delete-btn-2` (verifica del `Enum.find_index` + `Enum.at(i-1)` della logica corretta).
  - "Deleting the only idea leaves empty state" — workspace con 1 idea, delete → empty state visibile, focus su `#add-idea-button`.
**GREEN**: in `index.ex`:
```elixir
def handle_event("confirm_delete", _params, %{assigns: %{deletion: nil}} = socket),
  do: {:noreply, socket}

def handle_event("confirm_delete", _params, %{assigns: %{deletion: %{id: id}, ideas: prev_ideas}} = socket) do
  delete_fun = socket.assigns[:delete_idea_fun] || (&Ideas.delete_idea/1)

  case delete_fun.(id) do
    {:ok, _idea} ->
      target = focus_target_after_delete(prev_ideas, id)

      socket
      |> reload_ideas()
      |> assign(deletion: nil)
      |> put_flash(:info, "Idea eliminata")
      |> push_event("ideajar:focus", %{to: target})
      |> noreply()

    # Step 6 aggiunge gli altri rami
  end
end

defp focus_target_after_delete(ideas, deleted_id) do
  case Enum.find_index(ideas, &(&1.id == deleted_id)) do
    nil ->
      "#add-idea-button"
    i ->
      cond do
        length(ideas) == 1 -> "#add-idea-button"
        i < length(ideas) - 1 -> "#delete-btn-#{Enum.at(ideas, i + 1).id}"
        true -> "#delete-btn-#{Enum.at(ideas, i - 1).id}"
      end
  end
end
```
Inizializza `delete_idea_fun` in `mount/3` con `assign_new(:delete_idea_fun, fn -> &Ideas.delete_idea/1 end)`, parallelo a `create_idea_fun` esistente (`index.ex:644-648`).
**REFACTOR**: se `focus_target_after_delete/2` rivela duplicazione con un eventuale helper in `create_idea` post-success, valuta l'estrazione; altrimenti lascia locale.
**Files**: `index.ex`, `index_test.exs`
**Commit**: `Confirm delete: remove idea, refresh list, focus successor`

### Step 6: `confirm_delete` error branches — race + DB failure

**Complexity**: standard
**RED**: 2 scenari nello stesso step (rami della stessa `case` expression):
  - **Race** (F8): fixture 3 idee; apri modal su idea-2; **fuori-band** `Repo.delete!(idea_2)`; `render_click` sul bottone Elimina → flash `"Idea già eliminata"` con `role="status"`, modal chiusa, count = 2, focus a `#add-idea-button` (`assert_push_event view, "ideajar:focus", %{to: "#add-idea-button"}`), processo vivo (`Process.alive?(view.pid)`).
  - **DB failure** (F9): mount con assign override `delete_idea_fun: fn _ -> {:error, %Ecto.Changeset{errors: [base: {"db down", []}], valid?: false}} end`; apri modal; `render_click` Elimina → flash `"Eliminazione non riuscita, riprova"` con `role="alert"`, `@deletion != nil` (modal ancora aperta — verificabile via render contiene `role="dialog"`), count idee invariato, processo vivo.
**GREEN**: aggiunge i due rami a `confirm_delete`:
```elixir
{:error, :not_found} ->
  socket
  |> reload_ideas()
  |> assign(deletion: nil)
  |> put_flash(:info, "Idea già eliminata")
  |> push_event("ideajar:focus", %{to: "#add-idea-button"})
  |> noreply()

{:error, _changeset} ->
  socket
  |> put_flash(:error, "Eliminazione non riuscita, riprova")
  |> noreply()
  # NB: deletion assign non azzerato → modal resta aperta per retry/cancel
```
**REFACTOR**: aggiunge un commento sopra il catch-all `{:error, _changeset}` che documenta perché il branch è generico ("If a typed cause becomes recurring, promote it to its own clause").
**Files**: `index.ex`, `index_test.exs`
**Commit**: `Handle race and unexpected failures on delete confirm`

### Step 7: Filtri attivi preservati dopo delete

**Complexity**: standard
**RED**: scenario "Deleting an idea while a filter is active preserves the filter":
  - fixture: 3 idee, idea-1 e idea-3 in categoria "Weekend", idea-2 no.
  - `live(conn, "/?required=Weekend")` (verifica path/param schema con i test esistenti di `cycle_filter` slice 4).
  - Apri modal su idea-1, conferma → render mostra solo idea-3, `socket.assigns` filtri mantengono "Weekend".
**GREEN**: il `reload_ideas/1` esistente già usa gli assigns filtri (verifica). Se il branch `{:ok, _}` di Step 5 chiamava già `reload_ideas/1` (sì), il test passa senza modifiche di codice. Se la verifica scopre che `reload_ideas/1` non era usato, sostituisci la chiamata in Step 5/6 con la versione corretta — modifica chirurgica.
**REFACTOR**: nessuno.
**Files**: `index.ex` (eventuale aggiustamento), `index_test.exs`
**Commit**: `Preserve active filters on idea delete`

### Step 8: Validation venue manuale (V1, V1b)

**Complexity**: trivial
**RED**: nessun test automatizzato.
**GREEN**: avvia `mix phx.server`, apri DevTools mobile viewport (iPhone 13), esegue:
  - 2 screenshot → `docs/screenshots/slice-12/`: (1) modal aperta su un'idea con titolo, (2) lista dopo delete (oppure empty state se delete dell'unica idea).
  - Manual keyboard walkthrough di V1b (5 step) — verifica diretta in browser, niente file di handoff (KISS hobby project).
**REFACTOR**: nessuno.
**Files**: `docs/screenshots/slice-12/*`
**Commit**: `Add slice-12 manual validation screenshots`

## Complexity Classification

Tutti gli step sono `standard` salvo `Step 8` che è `trivial`. Nessun step è `complex` — l'unica scelta architetturale (cascade vs soft-delete) è fissata in A1-A2 e non comporta nuove astrazioni.

## Pre-PR Quality Gate

- [ ] Tutti i test passano (`mix test`)
- [ ] `mix compile --warnings-as-errors` pulito
- [ ] `mix format --check-formatted` pulito
- [ ] `mix credo` pulito
- [ ] `mix deps.audit` pulito
- [ ] `/code-review` passa
- [ ] V1 evidence committata in `docs/screenshots/slice-12/`
- [ ] `docs/conventions.md` aggiornata (verifica via `docs_test.exs`)
- [ ] `bd close` per le issue corrispondenti

## Risks & Open Questions

- **R1 — `phx-window-keydown` payload propagation**: chiuso in iter-1. Decisione: handler legge `socket.assigns.deletion.id`, non params. Step 4 implementa già così.
- **R2 — Backdrop click vs dialog click**: chiuso in iter-1. Backdrop e dialog **fratelli** nel DOM (no nesting). Step 3 RED include un test esplicito "click intra-dialog NON chiude la modal" come pinning anti-regressione.
- **R3 — Atomicità `Repo.get + Repo.delete`**: chiuso in iter-1 con `try/rescue Ecto.StaleEntryError → {:error, :not_found}` (vedi A3). F12 lo verifica.
- **R4 — Focus trap assente**: accettato per slice 12 — non blocker. Riapri come slice futura se la app introduce più modali.

## Plan Review Summary

**Iter-1 reviewers**: Acceptance Test Critic (qa-engineer), Design & Architecture Critic (architect), UX Critic (ui-ux-designer), Strategic Critic (product-manager).

### Blockers risolti (6)

1. **QA — flash `role="alert"` non asserito su F9**: aggiunto in Step 6 RED + AC F9.
2. **QA — `phx-disable-with="Eliminazione…"` non asserito**: promosso a F13 + assertion esplicita in Step 3 RED.
3. **QA — payload key mismatch (`%{to:}` vs `%{target:}`)**: spec corretta, A7 documenta `%{to: ...}` allineato a `index.ex:106`.
4. **Architect — `focus_target_after_delete/2` con `Enum.split_while` errato**: riscritto con `Enum.find_index` + `Enum.at`. Test "delete last card focuses previous" copre il fix.
5. **Architect — `phx-window-keydown` non propaga `phx-value-*`**: A6 fissa il pattern → handler legge `assigns.deletion.id`.
6. **UX — race path senza focus push**: A7 e Step 6 ora pushano focus a `#add-idea-button` come target sicuro.
7. **UX — apostrofo curly vs straight**: standardizzata su ASCII straight. Spec body modal aggiornata.
8. **PM — Step 10 (Lighthouse JSON, NVDA log) sproporzionato**: Step 8 ridotto a 2 screenshot + walkthrough verbale.

### Warning / nit incorporati

- Architect W1 (`Ecto.StaleEntryError` race) → A3 + F12.
- Architect W2 (`create_idea_fun` precedent) → verificato (`index.ex:644-648`) e citato esplicitamente in A8.
- QA W2 (Step 5 cascade duplicato di F4) → rimosso da Step 5; F4 unica fonte di cascade verification.
- UX W4 (icon-only button) → A13 aggiunge `<span class="sr-only">Elimina</span>`.
- UX W5 (`danger` class contrasto) → A14 specifica `bg-red-700 hover:bg-red-800 text-white` (≥4.5:1) con verifica V1a-style spostata a sanity check oculato.
- UX W7 ("Non potrai annullare" anxiety-inducing) → copy aggiornata in `L'idea sarà rimossa definitivamente.` (sia spec che plan).
- UX OBS (`aria-describedby`) → aggiunto al markup modal in Step 3.
- PM W2 (Steps 5+6+7+8 separati) → consolidati: ex-Step 6 e ex-Step 7 fusi nel nuovo Step 6 (race + DB failure, stessa case expression). Ex-Step 9 (docs_test) fuso in Step 2/3 (UI copy aggiunta nello stesso commit che la introduce). Ex-Step 8 → Step 7. Ex-Step 10 → Step 8. Totale: 10 step → 8 step.
- PM W3 (OQ1, OQ2 non gating) → rimossi dalla sezione Risks, demoted a code comments quando rilevanti.
- QA nit (V1b documentato come trap parziale) → V1b accorciato a 5 step keyboard manuali, niente file handoff.

### Warning non risolti (decisione esplicita)

- **Architect W3 (LV 1103 LOC + modal inline → considerare function component)**: respinto per ora. KISS per una sola modal; se in futuro la app introduce N modali, refactor singolo. Documentato in A5.
- **PM (Steps 7 dedicato a filtri)**: tenuto separato perché il test sui filtri richiede un setup `live(conn, "/?required=Weekend")` non riutilizzabile dagli step precedenti.

**Verdict iter-1**: tutti i blocker risolti. Pronto per re-review parziale (qa-engineer + architect + ui-ux-designer) o per approvazione utente diretta.
