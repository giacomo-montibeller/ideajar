# Plan: Slice 7a — Location data on ideas

**Created**: 2026-04-30
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/location-on-ideas.md`

## Build conventions (carried from slice 1-6)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Ogni commit** attraverso la skill `commit-message`. In `/build` uso option 1 default per ridurre interactivity.
- Pre-step gate locale: `mix compile --warnings-as-errors`, `mix format --check-formatted` (verify exit code), `mix credo`, `mix deps.audit`, `mix test --include migration`.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy IT canonica appesa a `docs/conventions.md` nello step 10 commit.
- Trunk-based su `main`, no feature branches; ogni step lascia il codebase in stato green committable.

## Goal

Slice 7a introduce 3 campi opzionali correlati su `ideas` (`location_name :: string`, `lat :: float`, `lng :: float`) con form fieldset `Posizione` (text input + map picker dialog modal HTML5 con Leaflet), reverse geocoding **server-side** via Nominatim+Req, e badge `📍 <name>` sulla card idea. **Vincolo strong utente: minimize JS** — l'unico hook custom è `LeafletMap` (init mappa + click → pushEvent). Modal mechanics native HTML5 + LV `JS.exec`. Reverse geocoding 100% server-side via `Ideajar.Geocoding` (thin defdelegate wrapper su `Ideajar.Geocoding.NominatimClient`, Req-based, Req.Test-stubbable).

3 stati validi (a) tutti nil, (b) name only, (c) name+coords. Stato invalido coords-senza-name → `"Posizione incompleta"`. lat/lng "entrambi o nessuno" enforced via cross-field validator.

Fuori scope: distance filter (slice 7b), geolocation hook (7b), Haversine (7b), mini-map sulla card, multi-location, edit di idea esistente, forward geocoding.

## Decisioni architetturali pre-build

- **CC1 — `Req` come HTTP client**: idiomatic Phoenix 1.7+, lighter di HTTPoison, built-in test mode (`Req.Test`). Aggiunto a `mix.exs` deps in step 1. Confermato.
- **CC2 — `Ideajar.Geocoding` modulo singolo (no Behaviour, no StubClient)** *(rivisto iter 2 post-Acceptance B1 + Design B1)*: `Geocoding.reverse_lookup/2` chiama `NominatimClient.reverse_lookup/2`. Nessun Behaviour, nessun dispatch via Application.get_env, nessun StubClient. Razionale: `StubClient` con Process dictionary NON funziona attraverso il process boundary di LiveViewTest (LV process diverso dal test process). Soluzione: stubbing avviene a livello HTTP via `Req.Test`, che ha shared name table cross-process. Production code path = test code path 1:1.
- **CC3 — `Req.Test` come unico stubbing mechanism**: per tutti i test (unit + LV integration). Setup pattern:
  - `config/test.exs`: `config :req, plug: {Req.Test, IdeajarStub}` o equivalente, OPPURE `config :ideajar, Ideajar.Geocoding.NominatimClient, req_options: [plug: {Req.Test, IdeajarStub}]`.
  - Test setup: `Req.Test.stub(IdeajarStub, fn conn -> Plug.Conn.send_resp(conn, 200, response_body) end)`.
  - Cross-process: `Req.Test.allow(IdeajarStub, self(), lv_pid)` se necessario per LV process.
- **CC4 — Asset bundling: vendoring**: progetto usa `assets/vendor/` pattern (daisyui, topbar, heroicons via Hex). Vendoring leaflet: download `leaflet.js` UMD bundle + `leaflet.css` in `assets/vendor/`. Import in `assets/js/app.js` (relative path) + `assets/css/app.css` (CSS import). NO `package.json` creato (preserva pattern esistente).
- **CC5 — Schema 3 campi nullable + cross-field validator**: `location_name :: string`, `lat :: float`, `lng :: float`. Cross-field validator `validate_location_consistency/1` enforce 3-state validity. Errore canonico: `"Posizione incompleta"` su `:location_name` field (centralizzato).
- **CC6 — Dual-path error per lat/lng** (parallelo slice 5/6 AA22, BB2): cast failure (`"abc"`) → override a `"Posizione non valida"`. Range failure (lat=91) → validate_number error con stesso message. Single canonical error message da entrambi i path. 2 helper privati: `override_lat_error/1` + `override_lng_error/1` OR un unico `override_coordinate_errors/1`. Decisione: helper unico per riduzione boilerplate.
- **CC7 — HTML5 `<dialog>` modal mechanics native**: `JS.exec("showModal", to: "#location-map-dialog")` open. `JS.exec("close", ...)` close. Backdrop, focus trap, Esc-to-close native HTML5 (Chrome 37+, Safari 15.4+, Firefox 98+ — sufficiente per 2026 mobile). Niente custom modal JS.
- **CC8 — Dialog close from server post-handler via push_event + global listener**: opzione C1 della critique. Aggiunto in `assets/js/app.js`:
  ```js
  window.addEventListener("phx:close-dialog", e => {
    const dialog = document.getElementById(e.detail.id)
    if (dialog && dialog.close) dialog.close()
  })
  ```
  3 righe, riusabile per future dialog. Server emit `push_event(socket, "phx:close-dialog", %{id: "location-map-dialog"})` dal handler `set_location` post-success.
- **CC9 — `LeafletMap` JS hook minimale**: ~30 righe. Init Leaflet con default center (Italia 42.5N 12.5E) + zoom 5 + OSM tile layer + click handler → `pushEvent("set_location", {lat, lng})`. `destroyed()` callback per `map.remove()`. Niente state mgmt, niente reverse geocoding fetch (server-side).
- **CC10 — `set_location` parse defensive (manual)**: handler riceve params, NON Ecto changeset. Cast manuale: lat/lng devono essere float o cast da string→float. Range check `lat ∈ [-90, 90]`, `lng ∈ [-180, 180]`. Hostile (non-numeric, out-of-range, missing keys) → no-op via catchall.
- **CC11 — Reset helpers separati** (slice 5 + 6 pattern): `reset_duration/1`, `reset_budget/1`, `reset_location/1` (NEW). Chiamati da mount + `toggle_form` open + `close_form` + save success. Single-source helper unico è premature consolidation; tenere separati per chiarezza.
- **CC12 — Bottone "Apri mappa" position vertical stack**: sotto il text input, full-width. Mobile 360px: pulsante full-width sotto è cleaner di inline a destra (cut-off risk). Pattern parallelo a chip family (vertical stack flex-wrap).
- **CC13 — Bottone "Rimuovi posizione" visible quando**: `@selected_location_name != nil OR @selected_lat != nil`. Logically `OR` — visibile se qualunque campo location è set. Reset porta tutto a nil → bottone scompare.
- **CC14 — Map default center Italia (lat=42.5, lng=12.5), zoom 5**: country-level view. Configurabile via `data-default-center='[42.5, 12.5]'` e `data-default-zoom='5'` attributes sul `<div phx-hook="LeafletMap">`. Hook legge attribute, fallback a defaults se assenti.
- **CC15 — Step ordering**: refactor-prerequisite first (Geocoding wrapper + Nominatim client = step 1+2). Schema/changeset = step 3. Form text input + handler + persistence (no map yet) = step 4. Badge = step 5. Map dialog + Leaflet hook + asset bundling = step 6. set_location handler + reverse geocoding flow + dialog close = step 7. Integration tests = step 8. Hostile uniform list = step 9. Docs sync = step 10. **Step 6 introduce il dialog SHELL senza set_location wiring**; step 7 wire-up il flow completo. Razionale: separazione UI (step 6) da logic (step 7) per ridurre blast radius.
- **CC16 — Stubbing tutto via `Req.Test`** *(rivisto iter 2)*: vedi CC2/CC3 sopra. `StubClient` rimosso dal design. `Req.Test` stub gestisce success/no-match/5xx/network-error/timeout/JSON-parse-error tutti i 6 path.
- **CC18 *(nuovo iter 2 — UX W7 fix)* — Dialog backdrop click**: HTML5 `showModal()` NON chiude il dialog su backdrop click di default. **Decisione**: NON aggiungere backdrop click handler. Razionale: full-screen mobile (100vw × 100vh) NON espone backdrop visibile (95% utenti mobile). Su desktop (5%) il backdrop è visibile ma il close button esplicito è large + accessible. Aggiungere backdrop click richiederebbe `onclick="event.stopPropagation()"` inline JS sul content (viola "minimize JS"). Esc-to-close native HTML5 mantiene il dismiss path da tastiera. Documentare la decisione in dialog UI copy: il close button è il single dismiss path (oltre a Esc).
- **CC19 *(nuovo iter 2 — UX W4 fix)* — Coord drift inline hint**: quando `@selected_lat != nil`, mostrare sotto il text input l'hint `📍 Coordinate impostate` (text-xs muted color). Visibile sia (a) post-pin successful, (b) post-pin con name vuoto (no_match), (c) durante edit text dopo pin. Comunica all'utente che le coords sono active indipendentemente dal text. Non richiede assigns aggiuntivi (deriva da `@selected_lat`).
- **CC20 *(nuovo iter 2 — UX W13 fix)* — Leaflet `tap: false` opzione iOS**: nel hook `LeafletMap`, `L.map(this.el, { tap: false })`. Documented Leaflet flag per disabilitare il tap emulation che può causare delay/imprecisione su iOS Safari. Per pin precision questo è importante.
- **CC21 *(nuovo iter 2 — UX W2 fix)* — Default map center + zoom**: `data-default-center='[43.5, 12.5]'` (centroid Italia peninsulare, no isole), `data-default-zoom='6'` (regional level, vs 5 country level). Cambia da CC14 originale.
- **CC22 *(nuovo iter 2 — UX W9 fix)* — Placeholder text input**: `placeholder="es. Casa di nonna"` sul text input `Luogo`. Comunica optionality + state (b) name-only è valido.
- **CC23 *(nuovo iter 2 — Design B1 spec sync)* — Spec asset section update**: il spec `docs/specs/location-on-ideas.md` riga 51-53 e 375 menzionano `npm install leaflet --prefix assets`. Va corretto a vendoring (`assets/vendor/leaflet.js`). Step 10 docs sync include questo update.
- **CC17 — Migration test data preservation (BB16 pattern)**: pre-rollback insert idea con location_name + coords. Down → row preserved (only columns dropped). Up → 3 columns reset to NULL. Pattern parallelo a slice 5/6 step 2/3 RED.

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/location-on-ideas.md`.

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest + Req.Test stub).
- [ ] **F2** — Schema `Idea.changeset/2` accetta `location_name`, `lat`, `lng` come attrs. NULL ammessi su tutti e 3.
- [ ] **F3** — Submit senza location → 3 campi nil.
- [ ] **F4** — Submit con solo `location_name` → name set, coords nil.
- [ ] **F5** — Submit con tutti e 3 i campi → idea persistita correttamente.
- [ ] **F6** — Submit con coords-without-name → `"Posizione incompleta"`.
- [ ] **F7** — Submit con lat-without-lng (o viceversa) → `"Posizione incompleta"`.
- [ ] **F8** — Submit con lat fuori range [-90, 90] → `"Posizione non valida"`.
- [ ] **F9** — Submit con lng fuori range [-180, 180] → `"Posizione non valida"`.
- [ ] **F10** — Submit con `location_name` > 200 chars → `"Il nome del luogo non può superare i 200 caratteri"`.
- [ ] **F11** — `set_location` event success path → reverse geocoding → 3 assigns set + push_event close dialog.
- [ ] **F12** — `set_location` con `:service_unavailable` → coords set, name unchanged, flash error.
- [ ] **F13** — `set_location` con `:no_match` → coords set, name unchanged, dialog closed.
- [ ] **F14** — `remove_location` → 3 assigns reset. Bottone non più visibile.
- [ ] **F15** — `update_location_name` → solo `@selected_location_name` cambia, lat/lng invariati.
- [ ] **F16** — Idea card location badge renderizzato solo se `not is_nil(idea.location_name)`.
- [ ] **F17** — Reset `@selected_location_name`, `@selected_lat`, `@selected_lng` su mount, toggle_form open, close_form, save success.

### Form/Map UI

- [ ] **U1** — `<dialog id="location-map-dialog">` esiste nel DOM (closed di default). `JS.exec("showModal")` apre, `JS.exec("close")` chiude.
- [ ] **U2** — Dialog contiene `<div phx-hook="LeafletMap" id="form-map-picker">`, close button, OSM attribution link.
- [ ] **U3** — Bottone `📍 Apri mappa` triggera `JS.exec("showModal", to: "#location-map-dialog")`.
- [ ] **U4** — Bottone `Rimuovi posizione` reso solo quando `@selected_location_name != nil OR @selected_lat != nil`.
- [ ] **U5** — Text input `Luogo` ha `phx-change="update_location_name"`, `value={@selected_location_name}`.
- [ ] **U6** — `LeafletMap` hook registrato in `assets/js/app.js`. Verifica via file read.
- [ ] **U7** — `phx:close-dialog` listener in `assets/js/app.js` (3 righe). Verifica via file read.

### Accessibility

- [ ] **A1** — Fieldset legend `Posizione` (no asterisco).
- [ ] **A2** — `<label>Luogo</label>` associato al text input.
- [ ] **A3** — Bottone `📍 Apri mappa` ha `aria-haspopup="dialog"`.
- [ ] **A4** — Dialog ha `aria-labelledby` puntato a `<h2 id="location-map-title">Scegli posizione</h2>`.
- [ ] **A5** — Close button ha `aria-label="Chiudi"`.
- [ ] **A6** — HTML5 `<dialog>` native focus trap + backdrop + Esc-to-close.
- [ ] **A7** — Bottone hit area ≥ 44×44 CSS px (riuso pattern ChipBase).
- [ ] **A8** — Badge implicit aria via text content `📍 <name>`.

### Security / robustness

- [ ] **S1** — `set_location` con coords non-numeric / out-of-range / missing keys / non-binary → no-op silenzioso (test enumerated).
- [ ] **S2** — `location_name` malicious `<script>` → HEEx auto-escape sul badge + text input value.
- [ ] **S3** — Nominatim response malicious → trattato come stringa opaca, escaped sul render.
- [ ] **S4** — `Geocoding.reverse_lookup/2` su input invalido → no raise (returns `{:error, _}`).
- [ ] **S5** — Nominatim service raise (network error) → caught, `{:error, :service_unavailable}`. Handler emit flash, lascia coords set, process alive.
- [ ] **S6** — Hardcoded User-Agent header `ideajar/1.0` (Nominatim policy).
- [ ] **S7** — Cast failure su `lat`/`lng` → canonical error `"Posizione non valida"` (override).
- [ ] **S8** — Range failure su `lat`/`lng` → stesso canonical error.

### Operational / data

- [ ] **O1** — Migration `AddLocationToIdeas` reversibile loss-free pre-popolamento. SQLite `ALTER TABLE x3` (1 statement per col, single migration). Test roundtrip + data preservation across rollback (CC17 pattern).
- [ ] **O2** — Schema introspection: `Idea.__schema__(:type, :location_name) == :string`, `:lat == :float`, `:lng == :float`.
- [ ] **O3** — `Ideajar.Geocoding.reverse_lookup/2` defdelegate to `NominatimClient.reverse_lookup/2`. Test stubbing 100% via `Req.Test.stub` + `Req.Test.allow` per cross-process LV.
- [ ] **O4** — Performance: `create_idea/1` con location_name + coords + reverse_lookup mocked <50ms (sanity).
- [ ] **O5** — `Ideajar.Geocoding.NominatimClient.reverse_lookup/2` testato con `Req.Test.stub/2` (success + 4xx + 5xx + timeout + JSON parse error).

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13, Pixel 7, 360px Pixel 4a): form Posizione fieldset, dialog map picker aperto, idea card location badge, validation error.
- [ ] **V1a** — Lighthouse a11y mediana ≥95.
- [ ] **V1b** — Keyboard-only walkthrough: Tab nel fieldset, Enter apre dialog, Esc chiude, focus restituito al bottone apri.
- [ ] **V2** — Map picker manual test: click sul map → pin renders → reverse geocode autofills → dialog closes.
- [ ] **V2a** — Manual Nominatim service unavailable (turn off network) → flash error appears.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 7a.
- [ ] **D2** — `CONTEXT.md` Modello dati aggiornato (schema include `location_name`, `lat`, `lng`; "Slice future" → slice 7b distance filter).
- [ ] **D3** — `test/ideajar_web/live/idea_live/index_test.exs`: out-of-scope guard mantiene `Distanza|Cerca` (no change), aggiunge positiva `Posizione` nel form.
- [ ] **D4** — `test/ideajar/docs_test.exs`: nuova `describe "slice-7a UI copy"`.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Label fieldset posizione | `Posizione` (no asterisco) |
| Label text input | `Luogo` |
| Bottone apri map picker | `📍 Apri mappa` |
| Bottone rimuovi posizione | `Rimuovi posizione` |
| Titolo dialog | `Scegli posizione` |
| Close button aria-label | `Chiudi` |
| OSM attribution | `© OpenStreetMap` |
| Errore posizione incompleta | `Posizione incompleta` |
| Errore posizione non valida | `Posizione non valida` |
| Errore nome luogo lungo | `Il nome del luogo non può superare i 200 caratteri` |
| Flash geocoding service down | `Geocodifica non disponibile, inserisci il nome manualmente` |
| Badge sulla card | `📍 <location_name>` |
| Badge data-testid | `idea-location-badge` |

## Steps

### Step 1: Add `req` Hex dep + `Ideajar.Geocoding` thin wrapper + Req.Test setup

**Complexity**: standard
**Rationale** *(rivisto iter 2)*: foundational. Drop Behaviour/StubClient (Acceptance B1 + Design B1 fix). `Geocoding` è wrapper modulo, `NominatimClient` (skeleton in step 1, real in step 2) è il single dispatch path. Test stubbing 100% via `Req.Test` plug.

**RED** (`test/ideajar/geocoding_test.exs` new + `test/ideajar/geocoding/nominatim_client_test.exs` skeleton):
1. `Ideajar.Geocoding.reverse_lookup/2` exists with arity 2 (`function_exported?`).
2. `Ideajar.Geocoding.NominatimClient.reverse_lookup/2` exists with arity 2.
3. With `Req.Test.stub(IdeajarStub, fn conn -> Plug.Conn.send_resp(conn, 200, ~s({"display_name": "Test"})) end)`: `Geocoding.reverse_lookup(43.5, 13.6)` returns `{:ok, "Test"}` (delegates correctly to NominatimClient + Req.Test plug works).
4. Without Req.Test stub set in test mode: NominatimClient raises a friendly error (e.g., `Req.TransportError` or our own message). Pin via `assert_raise`.

**GREEN**:
- Add `{:req, "~> 0.5"}` to `deps/0` in `mix.exs`. Run `mix deps.get`.
- New `lib/ideajar/geocoding.ex`:
  ```elixir
  defmodule Ideajar.Geocoding do
    @moduledoc """
    Slice 7a — server-side reverse geocoding wrapper.

    Single dispatch path: delegates to `Ideajar.Geocoding.NominatimClient`.
    Test stubbing happens at the HTTP boundary via `Req.Test` (cross-process
    shared name table; works correctly with LiveViewTest's separate LV
    process).
    """

    @spec reverse_lookup(float, float) ::
            {:ok, String.t()} | {:error, :no_match | :service_unavailable}
    defdelegate reverse_lookup(lat, lng), to: Ideajar.Geocoding.NominatimClient
  end
  ```
- New `lib/ideajar/geocoding/nominatim_client.ex` (skeleton, real impl in step 2):
  ```elixir
  defmodule Ideajar.Geocoding.NominatimClient do
    @moduledoc "Real implementation in step 2 — placeholder skeleton."
    @spec reverse_lookup(float, float) :: ...
    def reverse_lookup(_lat, _lng) do
      # Step 2 will replace with Req.get(...) implementation
      raise "Ideajar.Geocoding.NominatimClient not yet implemented"
    end
  end
  ```
- `config/test.exs`: aggiunge `config :ideajar, Ideajar.Geocoding.NominatimClient, req_options: [plug: {Req.Test, IdeajarStub}]` (set when step 2 wires real Req.get with `:plug` option).

**REFACTOR**: Module docstring di `Geocoding` spiega test stubbing strategy via Req.Test. Aggiungi commento in `nominatim_client.ex` che step 2 implementa.

**Files**: `mix.exs`, `mix.lock`, `lib/ideajar/geocoding.ex` (new), `lib/ideajar/geocoding/nominatim_client.ex` (new skeleton), `config/test.exs` (extend), `test/ideajar/geocoding_test.exs` (new), `test/ideajar/geocoding/nominatim_client_test.exs` (new skeleton).
**Spec mapping**: O3, CC2, CC3, CC16.

### Step 2: `Ideajar.Geocoding.NominatimClient` real HTTP via Req + Req.Test stubbing

**Complexity**: complex
**Rationale**: real network code, error handling, JSON parse, Req.Test stub patterns.

**RED** (`test/ideajar/geocoding/nominatim_client_test.exs` new — uses `Req.Test`):

Setup: `setup` block configura `Req.Test.set_req_test_to_shared/0` o equivalente per test isolation.

1. **Success**: stub Nominatim response 200 OK + body `{"display_name": "Sirolo, AN"}` → `NominatimClient.reverse_lookup(43.5, 13.6)` returns `{:ok, "Sirolo, AN"}`.
2. **Empty result (no_match)**: stub 200 OK + body `{}` (no `display_name`) or 404 → `{:error, :no_match}`.
3. **5xx error**: stub 500 → `{:error, :service_unavailable}`.
4. **Network timeout**: stub `Req.Test.transport_error/2` con `:timeout` → `{:error, :service_unavailable}`.
5. **Connect refused**: stub transport error `:econnrefused` → `{:error, :service_unavailable}`.
6. **Invalid JSON response**: stub 200 OK + body `not json` → `{:error, :service_unavailable}` (or `:no_match`, decisione: `:service_unavailable` perché è bug del server, non miss).
7. **User-Agent header**: stub asserts request had `User-Agent: ideajar/1.0`.
8. **URL params**: stub asserts request URL contains `lat=43.5&lon=13.6&format=json` (Nominatim API requires `lon` not `lng`).
9. **Configurable endpoint**: change `Application.put_env(:ideajar, Ideajar.Geocoding.NominatimClient, base_url: "http://example.test")` → request sent to that URL.

**GREEN**:
```elixir
defmodule Ideajar.Geocoding.NominatimClient do
  @user_agent "ideajar/1.0"
  @default_base_url "https://nominatim.openstreetmap.org"

  @spec reverse_lookup(float, float) ::
          {:ok, String.t()} | {:error, :no_match | :service_unavailable}
  def reverse_lookup(lat, lng) do
    base_url = Application.get_env(:ideajar, __MODULE__, [])[:base_url] || @default_base_url
    url = "#{base_url}/reverse?lat=#{lat}&lon=#{lng}&format=json"

    case Req.get(url, headers: [{"user-agent", @user_agent}], plug: req_plug()) do
      {:ok, %{status: 200, body: %{"display_name" => name}}} when is_binary(name) ->
        {:ok, name}
      {:ok, %{status: 200, body: _}} ->
        {:error, :no_match}
      {:ok, %{status: 404}} ->
        {:error, :no_match}
      {:ok, %{status: status}} when status >= 500 ->
        {:error, :service_unavailable}
      {:error, _exception} ->
        {:error, :service_unavailable}
    end
  end

  defp req_plug, do: Application.get_env(:ideajar, __MODULE__, [])[:plug]
end
```

`config/test.exs`: `config :ideajar, Ideajar.Geocoding.NominatimClient, req_options: [plug: {Req.Test, IdeajarStub}]` per Req.Test integration. Test impostano stub via `Req.Test.stub(IdeajarStub, fn conn -> ... end)` (canonical stub name `IdeajarStub` in tutta la slice).

**REFACTOR**: extract status code mapping in private helper if multi-clause becomes unwieldy.

**Files**: `lib/ideajar/geocoding/nominatim_client.ex` (new), `config/test.exs` (extend), `test/ideajar/geocoding/nominatim_client_test.exs` (new).
**Spec mapping**: O5, S5, S6, CC1, CC3.

### Step 3: Schema migration + 3 fields + cross-field validator + dual-path error

**Complexity**: complex
**Rationale**: 3 fields, cross-field validator, dual-path error override (parallel slice 5/6 pattern but with new `validate_location_consistency/1`).

**RED**:

a. **`test/ideajar/migrations_test.exs`** extension (4 symmetric updates):
1. Add `@add_location_migration`, `@add_location_version 20_260_430_000_001`, path block, Code.require_file guard.
2. Setup `delete_versions/0` + on_exit restoration (run new migration LAST after add_estimated_cost).
3. **New test "add_location migration is reversible and adds 3 nullable columns"**: PRAGMA `location_name` row with `type=TEXT`, `notnull=0`. Same for `lat`/`lng` with `type=REAL`, `notnull=0`.
4. **Insert/select roundtrip**: insert with all 3 set → SELECT returns same. Insert with all 3 NULL → SELECT returns NULL.
5. **CC17 data preservation across rollback**: pre-rollback insert 2 rows (all 3 set, all 3 NULL). Down → COUNT==2 + title intact. Up → all 3 cols NULL on both rows.

b. **`test/ideajar/ideas_test.exs`** new `describe "location fields (slice 7a)"`:
1. Valid changeset all 3 nil → no errors.
2. Valid with `location_name: "Casa di nonna"`, lat/lng nil → state (b) valid.
3. Valid with all 3 set → state (c) valid.
4. **Invalid: lat-without-lng**: `%{lat: 43.5, lng: nil, location_name: "X"}` → `errors[:location_name] == {"Posizione incompleta", _}`.
5. **Invalid: lng-without-lat**: idem inverso.
6. **Invalid: coords-without-name** (D1): `%{lat: 43.5, lng: 13.6, location_name: nil}` → `"Posizione incompleta"`.
7. **Invalid: empty-string name + coords (post-trim)**: `%{lat: 43.5, lng: 13.6, location_name: ""}` → `"Posizione incompleta"` (trim → nil → state D).
8. **Range: lat=91**: `errors[:lat] == {"Posizione non valida", _}`.
9. **Range: lat=-91**: idem.
10. **Range: lng=181**: `errors[:lng] == {"Posizione non valida", _}`.
11. **Range: lng=-181**: idem.
12. **Cast failure: lat="abc"**: `errors[:lat] == {"Posizione non valida", _}` (override).
13. **Cast failure: lng="<script>"**: `errors[:lng] == {"Posizione non valida", _}`.
14. **`location_name` 201 chars**: `errors[:location_name] == {"Il nome del luogo non può superare i 200 caratteri", _}`.
15. **Trim: " Sirolo  "** → `changes[:location_name] == "Sirolo"`.
16. **Schema introspection**: `Idea.__schema__(:type, :location_name) == :string`, etc.
17. **Valid boundary lat=90.0** *(nuovo iter 2 post-Acceptance #7 fix)*: `%{location_name: "X", lat: 90.0, lng: 0.0}` → no errors.
18. **Valid boundary lat=-90.0**: idem → no errors.
19. **Valid boundary lng=180.0**: idem.
20. **Valid boundary lng=-180.0**: idem.

**GREEN**:

a. New migration `priv/repo/migrations/20260430000001_add_location_to_ideas.exs`:
```elixir
defmodule Ideajar.Repo.Migrations.AddLocationToIdeas do
  use Ecto.Migration
  def change do
    alter table(:ideas) do
      add :location_name, :string, null: true
      add :lat, :float, null: true
      add :lng, :float, null: true
    end
  end
end
```

b. Update `lib/ideajar/ideas/idea.ex`:
- Add 3 fields to schema.
- Add `:location_name`, `:lat`, `:lng` to `@castable_fields`.
- Add `@location_incomplete "Posizione incompleta"`, `@location_invalid "Posizione non valida"`, `@location_name_too_long "Il nome del luogo non può superare i 200 caratteri"`.
- Pipeline *(rivisto iter 2 post-Design B fix — preserve existing order, only append new steps)*: take the existing pipeline of `idea.ex` line 89 verbatim, then APPEND the new validators in the natural place:
  - After `cast` and the existing `override_duration_error` + `override_estimated_cost_error`: ADD `override_coordinate_errors/1` (slice 7a override per `:lat`/`:lng` cast failure).
  - After `trim_text(:url)`: ADD `trim_text(:location_name)`.
  - After existing `validate_length(:url, ...)`: ADD `validate_length(:location_name, max: 200, message: @location_name_too_long)`.
  - After existing `validate_inclusion(:estimated_cost, ...)`: ADD `validate_number(:lat, ...)` and `validate_number(:lng, ...)` con message `@location_invalid`.
  - LAST validator (after `validate_at_least_one_category()`): ADD `validate_location_consistency/1` (cross-field).
  
  **NB**: do NOT rewrite or reorder slice 1-6 validators. Only append.
- `override_coordinate_errors/1`: pattern match su `Keyword.get(errors, :lat)` e `:lng`. Per ognuno, se `{"is invalid", opts}` → rewrite a `{@location_invalid, opts}`.
- `validate_location_consistency/1`: legge `get_field(changeset, :location_name)`, `:lat`, `:lng`. Determina state. Se invalid (lat-only, lng-only, coords-no-name) → `add_error(changeset, :location_name, @location_incomplete)`.

**REFACTOR**: pinare l'ordering dei validators (override deve venire DOPO cast, validate_number DOPO override per evitare chain invariato). Verifica Credo no issues.

**Files**: `priv/repo/migrations/20260430000001_add_location_to_ideas.exs` (new), `lib/ideajar/ideas/idea.ex` (extend), `test/ideajar/migrations_test.exs` (extend), `test/ideajar/ideas_test.exs` (extend), `test/ideajar/ideas/idea_test.exs` (schema fields list extension).
**Spec mapping**: F2-F10, S7, S8, O1, O2, CC5, CC6, CC17.

### Step 4: Form fieldset Posizione + text input + LV handlers + persistence (no map yet)

**Complexity**: standard
**Rationale**: pure form/LV layer. Map picker dialog wired in step 6.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` new `describe "form location field (slice 7a step 4)"`):
1. Mount: `view.assigns.selected_location_name == nil`, `:selected_lat == nil`, `:selected_lng == nil`.
2. Open form: render contains `<fieldset>` con `<legend>Posizione</legend>` (no asterisk) + `<label>Luogo</label>` + `<input phx-change="update_location_name" name="...">`.
3. Render contains bottone `📍 Apri mappa` con `aria-haspopup="dialog"`.
4. Render does NOT contain `Rimuovi posizione` button (no location set).
5. **Update text input**: `render_change(view, "update_location_name", %{"name" => "Casa di nonna"})` → `view.assigns.selected_location_name == "Casa di nonna"`. Lat/lng invariati.
6. **Rimuovi posizione visible**: with `selected_location_name` set → render contains bottone `Rimuovi posizione`.
7. **`remove_location` event**: `render_click(view, "remove_location")` → `selected_location_name == nil`, `:selected_lat == nil`, `:selected_lng == nil`. Bottone scompare.
8. **Save success state (b) name only**: with `@selected_location_name == "Casa di nonna"`, valid title + 1 cat → submit → idea persistita con `location_name: "Casa di nonna"`, `lat: nil`, `lng: nil`. Reset assigns post-save.
9. **Save success state (a) all nil**: no location input → idea persistita con tutti e 3 nil.
10. **`close_form` reset**: open, type name, click close → assigns reset.
11. **Hostile `update_location_name`**: missing `"name"` key, non-binary → no-op.
12. **`set_location` event placeholder**: doesn't exist yet (step 7 adds it). For step 4 RED: handler exists ma è no-op stub. Or skip until step 7.

**GREEN**:
- `lib/ideajar_web/live/idea_live/index.ex`:
  - Mount: `assign(:selected_location_name, nil) |> assign(:selected_lat, nil) |> assign(:selected_lng, nil)`.
  - Toggle_form open / close_form / save success: extend with `reset_location/1` (CC11). Helper privato:
    ```elixir
    defp reset_location(socket) do
      socket
      |> assign(:selected_location_name, nil)
      |> assign(:selected_lat, nil)
      |> assign(:selected_lng, nil)
    end
    ```
  - New handler:
    ```elixir
    def handle_event("update_location_name", %{"name" => name}, socket) when is_binary(name) do
      {:noreply, assign(socket, :selected_location_name, name)}
    end
    def handle_event("update_location_name", _, socket), do: {:noreply, socket}
    ```
  - New handler:
    ```elixir
    def handle_event("remove_location", _, socket) do
      {:noreply, reset_location(socket)}
    end
    ```
  - Save handler: inject `location_name`, `lat`, `lng` into `attrs_with_categories`. Pattern:
    ```elixir
    attrs
    |> maybe_put("location_name", socket.assigns.selected_location_name)
    |> maybe_put("lat", socket.assigns.selected_lat)
    |> maybe_put("lng", socket.assigns.selected_lng)
    ```

- `lib/ideajar_web/live/idea_live/index.html.heex`: nuovo fieldset `Posizione` after `Budget` *(rivisto iter 2: CC19 hint, CC22 placeholder)*:
  ```heex
  <fieldset class="fieldset">
    <legend class="label mb-1">Posizione</legend>
    <label for="idea-location-name" class="label">Luogo</label>
    <input
      type="text"
      id="idea-location-name"
      name="idea[location_name]"
      value={@selected_location_name || ""}
      placeholder="es. Casa di nonna"
      phx-change="update_location_name"
      phx-debounce="300"
      maxlength="200"
      class="input ..."
    />
    <p
      :if={not is_nil(@selected_lat)}
      class="text-xs text-base-content/70"
    >
      📍 Coordinate impostate
    </p>
    <button
      type="button"
      aria-haspopup="dialog"
      class="btn ..."
      disabled
    >
      📍 Apri mappa
    </button>
    <!-- Step 6 wires phx-click to JS.exec("showModal", ...) -->
    <button
      :if={not is_nil(@selected_location_name) or not is_nil(@selected_lat)}
      type="button"
      phx-click="remove_location"
      class="btn ..."
    >
      Rimuovi posizione
    </button>
  </fieldset>
  ```
  Note: bottone `Apri mappa` inizialmente `disabled` (step 6 lo abilita con JS.exec wiring).

**REFACTOR**: verify Credo no issues.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F3, F4, F14, F15, F17, U4, U5, A1, A2, A3, CC11, CC13.

### Step 5: Idea card location badge + XSS regression

**Complexity**: trivial
**Rationale**: rendering condizionale puro.

**RED**:

a. **`test/ideajar_web/components/location_badge_test.exs`** new:
1. `location_badge/1` with `name: "Sirolo, AN"` → `<span data-testid="idea-location-badge">📍 Sirolo, AN</span>`.
2. **AA14 structural XSS pin**: source contains `{@name}` (HEEx auto-escape), refute `raw(`, refute `Phoenix.HTML.raw`.
3. attr `:name, :string, required: true`.

b. **LV test `index_test.exs`** new `describe "idea card location badge (slice 7a step 5)"`:
1. **F16 conditional render — present**: insert idea con `location_name: "Sirolo"` → render contains badge `📍 Sirolo`.
2. **F16 absent**: insert idea con `location_name: nil` → no badge for that card.
3. **Name-only state (b)**: insert idea con name + lat/lng nil → badge shown.
4. **XSS regression**: insert idea con `location_name: "<script>alert(1)</script>"` → render contains escaped `&lt;script&gt;...`, NOT raw `<script>`.
5. **Position pin**: badge appare AFTER `<.budget_badge>` in DOM source order.

**GREEN**:

New `lib/ideajar_web/components/location_badge.ex`:
```elixir
defmodule IdeajarWeb.Components.LocationBadge do
  @moduledoc "Slice 7a — read-only badge for idea.location_name. Renders 📍 <name>."
  use Phoenix.Component

  attr :name, :string, required: true

  def location_badge(assigns) do
    ~H"""
    <span
      data-testid="idea-location-badge"
      class="inline-flex items-center gap-1 px-2 py-1 rounded-full border border-base-300 text-xs text-base-content/80 bg-base-200"
    >
      📍 {@name}
    </span>
    """
  end
end
```

Update template `index.html.heex`: inside `<li :for={idea}>`, AFTER `<BudgetChip.budget_badge ...>`, add:
```heex
<LocationBadge.location_badge :if={not is_nil(idea.location_name)} name={idea.location_name} />
```

`alias IdeajarWeb.Components.LocationBadge` in LV.

**REFACTOR**: None.

**Files**: `lib/ideajar_web/components/location_badge.ex` (new), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `lib/ideajar_web/live/idea_live/index.ex` (alias), `test/ideajar_web/components/location_badge_test.exs` (new), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F16, S2, S3.

### Step 6: HTML5 `<dialog>` + Leaflet hook + asset bundling (vendoring)

**Complexity**: complex
**Rationale**: cross-cutting JS + asset pipeline + LV native JS commands. No `set_location` wiring yet.

**RED** (test pin DOM structure + JS asset registration):

a. **Hook + asset registration tests** (`test/ideajar_web/live/idea_live/index_test.exs` new tests):
1. `assets/js/app.js` contains `LeafletMap` import + registration in hooks: `assert File.read!("assets/js/app.js") =~ "LeafletMap"`.
2. `assets/js/app.js` contains `phx:close-dialog` listener: `assert File.read!("assets/js/app.js") =~ "phx:close-dialog"`.
3. `assets/vendor/leaflet.js` exists.
4. `assets/vendor/leaflet.css` exists.
5. `assets/css/app.css` imports leaflet css (or app.js side imports).
6. `assets/js/hooks/leaflet_map.js` exists with `export const LeafletMap` and `mounted() { ... }` and `pushEvent("set_location", ...)` and `destroyed() { map.remove() }`.

b. **Template DOM structure tests**:
1. Mount: render contains `<dialog id="location-map-dialog"` (closed, no `open` attr).
2. Dialog contains `<h2 id="location-map-title">Scegli posizione</h2>`.
3. Dialog has `aria-labelledby="location-map-title"`.
4. Dialog contains `<div phx-hook="LeafletMap" id="form-map-picker" data-default-center="[43.5, 12.5]" data-default-zoom="6">` *(CC21 fix: zoom 6 + center 43.5)*.
5. Dialog contains close button with `aria-label="Chiudi"` AND `phx-click={JS.exec("close", to: "#location-map-dialog")}`.
6. Dialog contains OSM attribution link to `https://www.openstreetmap.org/copyright`.
7. Bottone `📍 Apri mappa` ora ENABLED (no `disabled`) AND `phx-click={JS.exec("showModal", to: "#location-map-dialog")}`.
8. **Dialog close button click no-op test** *(nuovo iter 2 post-Acceptance #scenario coverage gap)*: `JS.exec("close", ...)` triggered → dialog closes (open attr removed). Note: this is JS-only behavior; we cannot directly test JS execution in LiveViewTest. Pin via DOM presence of `phx-click` attr value containing `JS.exec("close"`.
9. **Backdrop click NOT closes dialog** *(CC18 explicit)*: dialog HEEx does NOT have `phx-click` directly on the `<dialog>` element. Pin via regex: `<dialog id="location-map-dialog"[^>]*>` should NOT contain `phx-click`.

**GREEN**:
- Download Leaflet 1.9.4 (latest LTS) UMD bundle + CSS into `assets/vendor/leaflet.js` + `assets/vendor/leaflet.css`. (Use curl in plan note; manual step in build.)
- New `assets/js/hooks/leaflet_map.js` *(rivisto iter 2: CC20 `tap: false`, CC21 default center/zoom)*:
  ```js
  // Leaflet UMD vendoring: prefer global window.L (loaded via <script> tag in
  // root.html.heex) over ES import. Esbuild may not handle UMD's module
  // detection correctly; using window.L is the documented fallback path
  // (R7a-5).
  const L = window.L

  export const LeafletMap = {
    mounted() {
      const center = JSON.parse(this.el.dataset.defaultCenter || '[43.5, 12.5]')
      const zoom = parseInt(this.el.dataset.defaultZoom || '6')
      this.map = L.map(this.el, { tap: false }).setView(center, zoom)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap'
      }).addTo(this.map)
      this.map.on('click', (e) => {
        this.pushEvent('set_location', { lat: e.latlng.lat, lng: e.latlng.lng })
      })
    },
    destroyed() {
      if (this.map) this.map.remove()
    }
  }
  ```
  
  **Important — UMD bundling fallback path (R7a-5)**: invece di `import L from ...`, il hook usa `window.L`. Leaflet UMD bundle in `assets/vendor/leaflet.js` viene caricato come `<script src="/assets/vendor/leaflet.js">` in `root.html.heex` PRIMA di `app.js`. Questo evita problemi esbuild UMD detection. Vendor file deve essere copiato in `priv/static/assets/` per essere servito (Phoenix asset pipeline gestisce questo via `Plug.Static` config).
- Update `assets/js/app.js`:
  - `import { LeafletMap } from "./hooks/leaflet_map.js"`
  - Add to hooks: `hooks: { ...colocatedHooks, RovingTabindex, LeafletMap }`
  - Add global listener:
    ```js
    window.addEventListener("phx:close-dialog", e => {
      const dialog = document.getElementById(e.detail.id)
      if (dialog && dialog.close) dialog.close()
    })
    ```
- Update `assets/css/app.css`: `@import "../vendor/leaflet.css";` near top.
- Update template `index.html.heex`:
  - Bottone `📍 Apri mappa` rimuove `disabled`, aggiunge `phx-click={JS.exec("showModal", to: "#location-map-dialog")}` + `aria-haspopup="dialog"`.
  - New `<dialog id="location-map-dialog" aria-labelledby="location-map-title">` block AFTER the `</.form>`. Contains:
    ```heex
    <div class="...">
      <h2 id="location-map-title">Scegli posizione</h2>
      <button
        type="button"
        aria-label="Chiudi"
        phx-click={JS.exec("close", to: "#location-map-dialog")}
        class="btn btn-ghost btn-sm"
      >
        ✕
      </button>
      <div
        id="form-map-picker"
        phx-hook="LeafletMap"
        data-default-center="[42.5, 12.5]"
        data-default-zoom="5"
        class="h-96 w-full"
      ></div>
      <p class="text-xs">
        © <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a>
      </p>
    </div>
    ```
- CSS for full-screen mobile: add to `assets/css/app.css` o inline:
  ```css
  @media (max-width: 640px) {
    dialog#location-map-dialog {
      width: 100vw;
      height: 100vh;
      max-width: 100vw;
      max-height: 100vh;
      margin: 0;
    }
  }
  ```

**REFACTOR**: verify hook docstring spiega WAI-ARIA APG dialog pattern + minimal-JS constraint.

**Files**: `assets/vendor/leaflet.js` (new, ~145KB), `assets/vendor/leaflet.css` (new, ~14KB), `assets/js/hooks/leaflet_map.js` (new), `assets/js/app.js` (extend), `assets/css/app.css` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: U1, U2, U3, U6, U7, A3, A4, A5, A6, CC4, CC7, CC8, CC9, CC14.

### Step 7: `set_location` LV handler + reverse geocoding flow + dialog close

**Complexity**: complex
**Rationale**: network handler + close event coordination + dual-path error flow.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` new `describe "set_location handler (slice 7a step 7)"`):

Setup *(rivisto iter 2 post-Acceptance B1 fix)*: `Req.Test.stub(IdeajarStub, fn conn -> ... end)` PER TEST, mockando Nominatim HTTP response. Cross-process: ogni test che usa `live_isolated` deve chiamare `Req.Test.allow(IdeajarStub, self(), view.pid)` se necessario (per LV process separato dal test process). NO `Application.put_env` per impl (rimosso). NO StubClient.

1. **Success path (F11)**: stub returns `{:ok, "Sirolo, AN"}`. `render_hook(view, "set_location", %{"lat" => 43.5, "lng" => 13.6})` → `view.assigns.selected_lat == 43.5`, `:selected_lng == 13.6`, `:selected_location_name == "Sirolo, AN"`. Form text input now shows `"Sirolo, AN"`.
2. **Success: dialog close push_event**: same setup → `assert_push_event view, "phx:close-dialog", %{id: "location-map-dialog"}`.
3. **Service unavailable (F12)**: stub returns `{:error, :service_unavailable}`. Pre-existing `@selected_location_name = "Casa di nonna"`. Trigger set_location. → `:selected_lat == 43.5`, `:selected_lng == 13.6`, `:selected_location_name == "Casa di nonna"` (unchanged). Flash error: `"Geocodifica non disponibile, inserisci il nome manualmente"`. Push close-dialog.
4. **No match (F13)**: stub `{:error, :no_match}`. Pre-existing name nil. Trigger. → coords set, name remains nil. Push close-dialog. No flash.
5. **Out-of-range lat=91**: render_hook with `%{"lat" => 91, "lng" => 13.6}` → no assigns change. No push_event.
6. **Out-of-range lng=-181**: idem.
7. **Non-numeric lat**: `%{"lat" => "abc", "lng" => 13.6}` → no-op.
8. **Missing lat key**: `%{"lng" => 13.6}` → no-op.
9. **Geocoding raise**: stub raises arbitrary exception. Handler catches → flash error, process alive. Coords set (since validation passed before geocoding). Push close-dialog.
10. **Persistence end-to-end**: success → submit form → idea persistita con tutti e 3 i campi.
11. **S3 malicious Nominatim response** *(nuovo iter 2 — Acceptance scenario coverage gap)*: stub returns `{:ok, "<img src=x onerror=alert(1)>"}` (or `<script>` payload). After set_location: render contains escaped `&lt;img...` (HEEx auto-escape on text input value). Render does NOT contain executable raw `<script>` or `<img onerror>`.

**GREEN**:

```elixir
def handle_event("set_location", %{"lat" => raw_lat, "lng" => raw_lng}, socket) do
  with {:ok, lat} <- parse_coord(raw_lat, -90, 90),
       {:ok, lng} <- parse_coord(raw_lng, -180, 180) do
    handle_geocoding(lat, lng, socket)
  else
    :error -> {:noreply, socket}
  end
end

def handle_event("set_location", _, socket), do: {:noreply, socket}

defp parse_coord(value, min, max) when is_number(value) do
  if value >= min and value <= max, do: {:ok, value * 1.0}, else: :error
end
defp parse_coord(value, min, max) when is_binary(value) do
  case Float.parse(value) do
    {f, ""} -> parse_coord(f, min, max)
    _ -> :error
  end
end
defp parse_coord(_, _, _), do: :error

defp handle_geocoding(lat, lng, socket) do
  result =
    try do
      Ideajar.Geocoding.reverse_lookup(lat, lng)
    rescue
      _ -> {:error, :service_unavailable}
    end

  socket =
    socket
    |> assign(:selected_lat, lat)
    |> assign(:selected_lng, lng)
    |> apply_geocoding_result(result)
    |> push_event("phx:close-dialog", %{id: "location-map-dialog"})

  {:noreply, socket}
end

defp apply_geocoding_result(socket, {:ok, name}) do
  assign(socket, :selected_location_name, name)
end

defp apply_geocoding_result(socket, {:error, :no_match}), do: socket

defp apply_geocoding_result(socket, {:error, :service_unavailable}) do
  put_flash(socket, :error, "Geocodifica non disponibile, inserisci il nome manualmente")
end
```

**REFACTOR**: helper `parse_coord/3` is reusable. Document in comments.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `test/test_helper.exs` (eventual Geocoding stub setup).
**Spec mapping**: F11, F12, F13, S4, S5, S7, U7, CC8, CC10.

### Step 8: Form/badge integration + edit-text-after-pin invariant (E1)

**Complexity**: standard
**Rationale**: regression pin di invariant architetturali.

**RED**:
1. **E1 invariant**: setup with coords + name set. Render_change `update_location_name` con stringa diversa → `selected_location_name` cambia, lat/lng INVARIATI.
2. **Persistence end-to-end state (c)**: trigger `set_location` (success), then save → idea con name + coords.
3. **Empty-string trim invariant**: render_change name="" (empty after trim) + coords pre-set → submit → `"Posizione incompleta"` (state D invalid).
4. **`remove_location` resets all 3 + button hide**: post-set_location success, click remove → 3 nil + button gone.
5. **Card badge integration**: persisted idea (state b) → render lista mostra badge.
6. **Card badge XSS**: persisted idea con name `<script>` → escaped in DOM.
7. **Reset on save success**: post-save → 3 assigns nil.

**GREEN**: nessun nuovo codice. Test pin existing architecture.

**REFACTOR**: None.

**Files**: `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F5, F15, F17, S2, CC11.

### Step 9: Hostile inputs uniform + cross-field validation regression

**Complexity**: standard
**Rationale**: parallel slice 5/6 hostile uniform list.

**RED**:

a. **Cross-field validation tests (changeset-level)**:
1-6. As in step 3 RED b items 4-7 (lat-only, lng-only, coords-no-name, empty-name+coords) + range failures.

b. **Handler-level hostile inputs uniform list**:
- `update_location_name`: 5 hostile (`%{}`, `%{"name" => 42}`, `%{"name" => []}`, missing key, non-binary `%{"name" => %{}}`) → no-op.
- `set_location`: 8 hostile uniform list:
  - `%{"lat" => "abc", "lng" => 13.6}` → no-op (cast fail)
  - `%{"lat" => "<script>", "lng" => 13.6}` → no-op
  - `%{"lat" => 91, "lng" => 13.6}` → no-op (range)
  - `%{"lat" => -91, "lng" => 13.6}` → no-op
  - `%{"lat" => 43.5, "lng" => 181}` → no-op
  - `%{"lat" => 43.5, "lng" => -181}` → no-op
  - `%{"lng" => 13.6}` → no-op (missing lat)
  - `%{"lat" => 43.5, "lng" => nil}` → no-op (nil lng)
- `remove_location`: idempotent (calling on empty state → no-op).

c. **Geocoding service raise**: stub raises arbitrary → caught by handler, flash, process alive.

**GREEN**: tests pin existing architecture (set_location handler + override_coordinate_errors + validate_location_consistency already implemented). Eventuali edge cases scoperti → fix.

**REFACTOR**: None.

**Files**: `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: S1, S4, S5, S7, S8.

### Step 10: Out-of-scope guard + docs sync (D1, D2, D3, D4) + plan flip

**Complexity**: standard

**RED**:
1. **D1 conventions.md slice-7a UI copy**: new `describe "docs/conventions.md — slice 7a UI copy"` con stringhe canoniche.
2. **D2 CONTEXT.md modello dati**: `describe "CONTEXT.md — slice 7a schema"` asserisce `location_name`, `lat`, `lng` documentati nello schema block.
3. **D3 out-of-scope guard**: `index_test.exs` regex stays `Distanza|Cerca` (no change). NEW positive assertion: `Posizione` appears as fieldset legend in form-open render.
4. Docs_test.exs new describe già covered da D1.

**GREEN**:
- `docs/conventions.md`: append section `Stringhe aggiunte in slice 7a (location on ideas)` con table 13 stringhe.
- `CONTEXT.md`:
  - Update Modello dati schema block: add `location_name string opzionale`, `lat float opzionale`, `lng float opzionale` (slice 7a).
  - Update "Slice future" sentence: "Slice 7b estenderà con filter distanza Haversine."
- `index_test.exs`: aggiunge positive assertion `Posizione` in form-open render.
- `docs_test.exs`: nuove `describe`.
- Plan flip status `approved` → `implemented`.

**REFACTOR**: None.

**Files**: `docs/conventions.md` (extend), `CONTEXT.md` (update), `test/ideajar/docs_test.exs` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `plans/slice-7a-location-on-ideas.md` (status flip).
**Spec mapping**: D1, D2, D3, D4.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Geocoding wrapper + Req.Test setup |
| 2 | **complex** | Real HTTP via Req + Req.Test + error mapping + 9 RED cases |
| 3 | **complex** | 3 fields + cross-field validator + dual-path error + 16 RED cases |
| 4 | standard | Form + handlers; pattern slice 5/6 |
| 5 | trivial | Conditional render + XSS structural pin |
| 6 | **complex** | Cross-cutting JS + asset bundling + LV JS.exec + dialog DOM |
| 7 | **complex** | Network handler + dialog close coordination + 10 RED cases |
| 8 | standard | Pure regression pin |
| 9 | standard | Hostile uniform list + cross-field validation regression |
| 10 | standard | Docs sync; nessun cambio strutturale |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` passa (verifica explicita exit code).
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin ha almeno un test.
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-7a/`.
- [ ] **V1a**: Lighthouse a11y mediana ≥95.
- [ ] **V1b**: keyboard-only walkthrough.
- [ ] **V2**: map picker manual test (con network) — geocoding success.
- [ ] **V2a**: map picker manual test (network off) — flash error.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R7a-1 — Leaflet vendoring vs CDN trade-off**: vendoring (current decision CC4) preserva pattern progetto + offline-friendly. CDN più semplice update ma fragile (CDN down = app rotta). Trigger per cambio: bug recurrenti in vendor leaflet 1.9.4.
- **R7a-2 — `<dialog>` browser support**: Chrome 37+, Safari 15.4+ (2022), Firefox 98+ (2022). Per 2026 mobile → universale. Polyfill non necessario.
- **R7a-3 — Nominatim rate limit (1 req/sec policy)**: per app 2-user è impossibile sforare. Non implementiamo client-side throttle.
- **R7a-4 — Test stubbing strategy**: `Req.Test` è il single stubbing path (decisione iter 2 finale). `Req.Test.allow(IdeajarStub, self(), view.pid)` per cross-process LV tests. Production code path === test code path 1:1. StubClient eliminato dal design. Behaviour eliminata dal design. Vedi CC2/CC3/CC16.
- **R7a-5 — Esbuild bundling Leaflet UMD**: Leaflet UMD usa `(function(global) { ... })(this)` pattern. Esbuild dovrebbe gestire UMD nativamente. Verifica empirica in step 6.
- **R7a-6 — `JS.exec("showModal")` server-side rendering**: HEEx attribute `phx-click={JS.exec("showModal", to: "#...")}` viene serializzato nell'HTML. Browser execute on click. Compat verified (Phoenix LV 1.0+).
- **R7a-7 — Map picker on iOS Safari**: HTML5 `<dialog>` showModal su iOS Safari 15.4+ è full-screen by default. Test V2 conferma.
- **R7a-8 — `validate_location_consistency/1` ordering in pipeline**: deve venire DOPO `validate_required(:title)` e altri per non sovrascrivere errori. Pinato in step 3 GREEN.
- **R7a-9 — Multi-form-field state isolation**: `@selected_duration`, `@selected_cost`, `@selected_location_name`/`lat`/`lng`. Reset coordinato in 4 hook (mount, open, close, save). Trigger per refactor (`reset_form_state/1` unico): 4° fieldset state group (slice 8 search? Probabilmente search non ha form chip state).
- **R7a-10 — Field naming `lng` vs `lon` vs `long`**: Nominatim usa `lon`. Convenzione Elixir/Postgres `lng` è più comune (3 chars, no SQL keyword conflict). Mantengo `lng` lato schema, convert a `lon` solo nella URL Nominatim.
- **R7a-11 — Edit text + coord drift (E1)**: utente edita name dopo pin, coords restano. Distance filter slice 7b userà coords. UX trade-off: utente sa di aver overridden, accept.
- **R7a-12 — gettext deferral (slice 4 R6 carry-over)**: slice 7a aggiunge ~13 stringhe. Cumulative ~70 strings. Trigger residuo (utente non-IT) non scattato.

## Plan Review Summary

> Verdetti iter 1: acceptance **needs-revision** (2 blocker), design **needs-revision** (4 blocker), UX **needs-revision** (2 blocker), strategic **approve** (2 flag).
> Iter 2: acceptance **approve**, design **needs-revision** (3 blocker — narrative drift), UX **approve**, strategic skipped (already approve).
> Iter 3: design **approve**.
> Convergenza raggiunta a iter 3.

### Iter 2 fixes

**Acceptance (2 blocker chiusi):**
- B1 stubbing inconsistency: drop `StubClient` entirely, use `Req.Test` direct everywhere. CC2/CC3/CC16 rewritten.
- Boundary tests added: lat=90.0, -90.0, lng=180.0, -180.0 → no errors (Step 3 RED #17-20).

**Design (4 blocker iter 1 chiusi):**
- B1 same as Acceptance.
- Pipeline ordering preserved: Step 3 GREEN explicit "append, don't reorder".
- Spec/plan vendoring contradiction fixed: spec rewritten to vendoring (no npm). CC23.
- Esbuild UMD fallback: hook uses `window.L` global (loaded via `<script>` tag), not `import L from "..."`. CC9 + CC20.

**UX (2 blocker chiusi):**
- W7 backdrop click: explicit decision NOT to close on backdrop (CC18). Mobile full-screen has no visible backdrop; close button + Esc are the dismiss paths.
- W4 coord drift hint: inline `📍 Coordinate impostate` whenever `@selected_lat != nil` (CC19, Step 4 GREEN template).

Plus 4 minor improvements applied:
- W2 default zoom 6 + center [43.5, 12.5] (CC21).
- W9 placeholder `es. Casa di nonna` (CC22).
- W13 Leaflet `tap: false` for iOS (CC20).
- W12 validation error placement (errors on `:location_name` → renders adjacent to text input).

### Iter 3 fixes (Design narrative drift)

- Spec L262/L302-317/L370 architecture section rewritten to defdelegate wrapper + Req.Test stubbing example.
- Plan L19/L121/L230/L761/L793 rewritten to drop Behaviour/StubClient narrative.
- Plan L230 Step 2 GREEN code: removed `@behaviour` and `@impl true` annotations.
- Stub naming unified to `IdeajarStub` across plan + spec.

### Warnings residual (tracked, not blocking)

- **R7a-1** Leaflet vendoring vs CDN trade-off — vendoring chosen, trigger documented.
- **R7a-2** `<dialog>` browser support — universal by 2026.
- **R7a-3** Nominatim rate limit — 2-user app cannot exceed.
- **R7a-5** Esbuild UMD fallback — resolved via `window.L` (CC9 documented).
- **R7a-7** iOS Safari dialog full-screen — V2 manual test confirms.
- **R7a-9** Reset coordination 4 hook × 3 helpers — 12 calls. Refactor trigger near.
- **R7a-12** gettext deferral — slice 7a +13 strings, cumulative ~70. Trigger residuo (utente non-IT) non scattato.

### UX warnings residual (low-priority)

- W6 no_match flow smoother — autofocus text input + inline copy. Polish, not blocker. Tracked.
- W11 OSM attribution prominence — present, sized text-xs, sufficient for compliance.
- W3 form length 7 fieldsets — long mobile scroll. Acceptable given infrequent use.

### Net assessment

Plan è **implementation-ready** per `/build`. 9 blocker chiusi attraverso 3 iter. Le decisioni più strutturanti (CC2 drop Behaviour, CC8 dialog close push_event, CC9 window.L UMD fallback, CC18 backdrop no-handler) sono pinned con codice/test esplicito.

**Convergenza**: 3 iter (1 → 2 → 3). Drift narrativo iter 2 → 3 era inevitabile per un refactor ampio (drop di un'intero pattern Behaviour); iter 3 ha cleanato il doc trail.
