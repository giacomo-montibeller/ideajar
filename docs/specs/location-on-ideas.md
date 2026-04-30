# Spec: Location on ideas

> Slice 7a of the ideajar project. Adds three optional correlated fields
> (`location_name`, `lat`, `lng`) to ideas, plus a form fieldset with text
> input + on-demand map picker via Leaflet inside an HTML5 `<dialog>`
> modal. Reverse geocoding is server-side (Nominatim via Req). Idea cards
> render a location badge. **Distance filter, geolocation hook, and
> Haversine are out of scope — slice 7b.**

## Intent Description

Slice 7a introduce il concetto **posizione** sulle idee come 3 campi
opzionali correlati. Il design segue 4 vincoli forti:

1. **Mobile-first**: 95% utenti mobile. Map picker UX deve essere
   modale full-screen, non inline (perdita di context del form).
2. **Minimize JS**: solo l'hook `LeafletMap` (init Leaflet + tile layer
   + click handler → `pushEvent`). Zero logica custom JS oltre questo.
   Reverse geocoding, validation, state mgmt → server-side. Modal
   open/close via `JS.exec("showModal"/"close")` LV native (HTML5
   `<dialog>`).
3. **Server-side reverse geocoding**: nuovo modulo `Ideajar.Geocoding`
   con `reverse_lookup/2` che chiama Nominatim via `Req`. Mock-testabile
   via `Req.Test` test stub.
4. **3 stati validi, 1 stato invalido**: l'idea può avere (a) nessuna
   posizione (3 campi nil), (b) solo `location_name` (utente scrive
   "Casa di nonna" senza pin), (c) `location_name` + `lat` + `lng`
   (full posizione). Lo stato (d) `lat`/`lng` senza `location_name` è
   **invalido**: il submit produce error `"Posizione incompleta"`.
   Anche lat-senza-lng e lng-senza-lat sono invalidi (cross-field
   validator).

**Form add-idea**: nuovo fieldset `Posizione` sotto `Budget`, contiene:
- text input `location_name` (`Luogo`, max 200 chars, opzionale)
- bottone `📍 Apri mappa` accanto al text input → `JS.exec("showModal", to: "#location-map-dialog")` apre l'`<dialog>` HTML5
- dialog full-screen mobile contiene `<div phx-hook="LeafletMap" id="form-map-picker">` + bottone chiudi + OSM attribution
- click sulla mappa → hook fa `pushEvent("set_location", %{"lat" => 43.5, "lng" => 13.6})` → LV handler chiama `Geocoding.reverse_lookup(lat, lng)` → assign `@selected_location_name`, `@selected_lat`, `@selected_lng` → close dialog via `push_event("phx:close-dialog", ...)` o JS.exec
- bottone `Rimuovi posizione` (visibile solo quando ≥1 campo set) → reset 3 assigns a nil
- text input edit → `phx-change` event `update_location_name` → assign solo `@selected_location_name`, lat/lng invariati

**Reverse geocoding**:
- `Ideajar.Geocoding.reverse_lookup(lat, lng)` → `{:ok, name}` | `{:error, :no_match}` | `{:error, :service_unavailable}`
- Su `:no_match`: `@selected_location_name = nil`, lat/lng set, submit produce `"Posizione incompleta"` (D1)
- Su `:service_unavailable`: lat/lng set, location_name unchanged, flash error `"Geocodifica non disponibile, inserisci il nome manualmente"`. Utente può digitare nel text input o rimuovere posizione.
- Public Nominatim endpoint `https://nominatim.openstreetmap.org/reverse` con User-Agent `ideajar/1.0` (policy compliance). Endpoint configurabile via `Application.get_env(:ideajar, Ideajar.Geocoding)`.

**Card display**: nuovo `<.location_badge>` accanto a duration + budget badge. Renderizza `📍 <location_name>` solo se `location_name` non-nil. Coords NON mostrate (slice 7b le userà).

**Asset pipeline**:
- Vendoring: `assets/vendor/leaflet.js` (UMD bundle) + `assets/vendor/leaflet.css` — segue il pattern progetto (no `package.json`, parallel a daisyui/topbar/heroicons). Caricato via `<script src="...">` in `root.html.heex` PRIMA di `app.js`. Hook usa `window.L` per evitare problemi esbuild con UMD detection.
- Leaflet CSS imported in `assets/css/app.css` o equivalent
- Bundled via esbuild Phoenix default
- Hook in `assets/js/hooks/leaflet_map.js`, registered in `app.js`

**Out of scope**:
- Distance filter UI + geolocation hook + Haversine (slice 7b)
- Mini-map sulla card (deferred, perf concern mobile)
- Multi-location idea (1 location per idea)
- Edit location di idea esistente (no edit mode in app)
- Custom tile style / dark mode tile
- Forward geocoding (search by name → coords) — solo reverse
- Map picker pre-position (always opens at default center)

## User-Facing Behavior

```gherkin
Feature: Add a location to ideas

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has the canonical 8 seeded categories

  # ── Form: text input only (state b — name-only) ────────────────
  Scenario: Submitting form with location_name only persists name without coords
    Given the form is open with title "Picnic" and one category selected
    When I type "Casa di nonna" into the location text input
    And I click "Salva"
    Then a new idea is saved with location_name "Casa di nonna" and lat/lng NULL

  Scenario: Submitting form without location persists all 3 fields NULL
    Given the form is open with title "X" and one category, no location input
    When I click "Salva"
    Then a new idea is saved with location_name, lat, lng all NULL

  # ── Map picker dialog ──────────────────────────────────────────
  Scenario: Clicking the map picker button opens the dialog
    Given the form is open
    When I click "📍 Apri mappa"
    Then a <dialog> element with id "location-map-dialog" has the open attribute set
    And it contains a <div phx-hook="LeafletMap" id="form-map-picker">
    And it contains an OSM attribution link

  Scenario: Closing the map picker dialog without setting a location
    Given the map picker dialog is open
    When I click the dialog close button
    Then the dialog is closed (open attribute removed)
    And no @selected_* assign changes

  Scenario: Pressing Escape closes the dialog (HTML5 native behavior)
    Given the map picker dialog is open
    When I press Escape
    Then the dialog is closed
    And no @selected_* assign changes

  # ── Map click triggers reverse geocoding ───────────────────────
  Scenario: Clicking on the map sets coords and reverse-geocodes location_name
    Given the map picker dialog is open
    And the Geocoding service returns {:ok, "Sirolo, AN"} for lat=43.5 lng=13.6
    When the LeafletMap hook dispatches set_location with {lat: 43.5, lng: 13.6}
    Then @selected_lat == 43.5
    And @selected_lng == 13.6
    And @selected_location_name == "Sirolo, AN"
    And the form text input shows "Sirolo, AN"
    And the dialog is closed

  Scenario: Map click with reverse geocoding service unavailable
    Given the map picker dialog is open
    And the Geocoding service returns {:error, :service_unavailable}
    When the hook dispatches set_location with {lat: 43.5, lng: 13.6}
    Then @selected_lat == 43.5
    And @selected_lng == 13.6
    And @selected_location_name remains its previous value
    And a flash error appears with text "Geocodifica non disponibile, inserisci il nome manualmente"
    And the dialog is closed

  Scenario: Map click in unmapped area returns no_match
    Given the map picker dialog is open
    And the Geocoding service returns {:error, :no_match} for lat=0 lng=0
    When the hook dispatches set_location with {lat: 0, lng: 0}
    Then @selected_lat == 0 and @selected_lng == 0
    And @selected_location_name remains its previous value (nil if never set)
    And the dialog is closed

  # ── Edit text after pin (E1) ───────────────────────────────────
  Scenario: Editing the text input after a pin keeps lat/lng unchanged
    Given coords lat=43.5 lng=13.6 and location_name "Sirolo, AN" are set
    When I edit the text input to "Casa di nonna a Sirolo"
    Then @selected_location_name == "Casa di nonna a Sirolo"
    And @selected_lat == 43.5 (unchanged)
    And @selected_lng == 13.6 (unchanged)
    When I click "Salva"
    Then the new idea has name "Casa di nonna a Sirolo" + coords (43.5, 13.6)

  # ── Remove location ────────────────────────────────────────────
  Scenario: Clicking "Rimuovi posizione" clears all 3 fields
    Given lat, lng, and location_name are all set
    When I click "Rimuovi posizione"
    Then @selected_location_name, @selected_lat, @selected_lng are all nil
    And the text input is empty
    And the "Rimuovi posizione" button is no longer rendered

  Scenario: "Rimuovi posizione" button is hidden when no location is set
    Given the form is open with no location set
    When I look at the form
    Then the "Rimuovi posizione" button is NOT rendered

  # ── Validation: 3 valid states, invalid combinations ───────────
  Scenario: Submitting with lat without lng is rejected (D1 — coords incomplete)
    When I dispatch save with attrs %{lat: 43.5, lng: nil, location_name: "X"}
    Then the form re-renders with error "Posizione incompleta"
    And the idea is not persisted

  Scenario: Submitting with lng without lat is rejected
    When I dispatch save with attrs %{lat: nil, lng: 13.6, location_name: "X"}
    Then the form re-renders with error "Posizione incompleta"

  Scenario: Submitting with coords without location_name is rejected (D1)
    When I dispatch save with attrs %{lat: 43.5, lng: 13.6, location_name: nil}
    Then the form re-renders with error "Posizione incompleta"
    And the idea is not persisted

  Scenario: Submitting with empty-string location_name + coords is rejected
    When I dispatch save with attrs %{lat: 43.5, lng: 13.6, location_name: ""}
    Then the form re-renders with error "Posizione incompleta"
    # location_name is trimmed; "" → nil → state D invalid

  # ── Range validation ───────────────────────────────────────────
  Scenario: Submitting lat out of range [-90, 90] is rejected
    When I dispatch save with lat: 91, lng: 13.6, location_name: "X"
    Then the form re-renders with error "Posizione non valida"

  Scenario: Submitting lng out of range [-180, 180] is rejected
    When I dispatch save with lat: 43.5, lng: 181, location_name: "X"
    Then the form re-renders with error "Posizione non valida"

  Scenario: Submitting non-numeric lat/lng is rejected
    When I dispatch save with attrs %{lat: "abc", lng: "xyz", location_name: "X"}
    Then the form re-renders with error "Posizione non valida"

  # ── Length validation ──────────────────────────────────────────
  Scenario: Submitting location_name longer than 200 chars is rejected
    When I dispatch save with location_name = (a string of 201 chars)
    Then the form re-renders with error "Il nome del luogo non può superare i 200 caratteri"

  # ── Idea card location badge ──────────────────────────────────
  Scenario: Idea cards show a location badge when location_name is set
    Given an idea "Sirolo" with location_name "Sirolo, AN"
    When I visit "/"
    Then the "Sirolo" card shows a badge with text "📍 Sirolo, AN"
    And the badge has data-testid="idea-location-badge"

  Scenario: Idea cards show no location badge when location_name is NULL
    Given an idea "X" with location_name NULL
    When I visit "/"
    Then the "X" card has no element with data-testid="idea-location-badge"

  Scenario: Location badge is rendered for name-only idea (no coords)
    Given an idea "Y" with location_name "Casa di nonna" and lat/lng NULL
    When I visit "/"
    Then the "Y" card shows a badge "📍 Casa di nonna"
    # Coords absence does NOT hide the badge — name-only is a valid state.

  # ── Hostile inputs / set_location event ────────────────────────
  Scenario: set_location event with non-numeric coords is no-op
    When I dispatch set_location with %{"lat" => "abc", "lng" => "def"}
    Then no @selected_* assign changes
    And the LV process does not crash

  Scenario: set_location event with out-of-range coords is no-op
    When I dispatch set_location with %{"lat" => 91, "lng" => 13.6}
    Then no @selected_* assign changes

  Scenario: set_location with coords + Geocoding raise crashes the request, not the LV
    Given the Geocoding service raises an unexpected exception
    When the hook dispatches set_location
    Then the LV handler returns {:noreply, socket}
    And a flash error appears
    And the LV process remains alive

  # ── XSS regression ─────────────────────────────────────────────
  Scenario: A malicious location_name is HTML-escaped on render (badge)
    Given an idea with location_name "<script>alert(1)</script>"
    When I visit "/"
    Then the rendered HTML does not execute the injected script
    And the badge text appears as escaped "&lt;script&gt;alert(1)&lt;/script&gt;"

  Scenario: A malicious Nominatim response is HTML-escaped on autofill
    Given Geocoding returns {:ok, "<img src=x onerror=alert(1)>"}
    When set_location triggers
    Then @selected_location_name == "<img src=x onerror=alert(1)>" (raw atom value)
    And the form text input renders the value escaped (HTML-encoded characters)

  # ── Out-of-scope guard ─────────────────────────────────────────
  Scenario: There is no other filter UI in slice 7a
    When I visit "/"
    Then no element matches the texts "Distanza", "Cerca"
    # Distance filter remains slice 7b. Search remains slice 8.

  Scenario: Slice 7a does not introduce geolocation user-position
    When I visit "/"
    Then no element with text "Usa la mia posizione" exists
    # User-position-driven filtering is slice 7b.
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Idea` (esteso) | Schema Ecto | 3 campi nuovi: `location_name :: string` (max 200, trimmed), `lat :: float` (range [-90, 90]), `lng :: float` (range [-180, 180]). Cross-field validator `validate_location_consistency/1` enforces 3-state validity. |
| `Ideajar.Geocoding` (nuovo) | Thin wrapper | `defdelegate reverse_lookup(lat, lng), to: NominatimClient`. Public API surface domain-side per evitare che callers importino direttamente `NominatimClient`. Test stubbing avviene a livello HTTP via `Req.Test` (cross-process safe via `Req.Test.allow`). |
| `Ideajar.Geocoding.NominatimClient` (nuovo) | Modulo HTTP | Implementazione concreta via `Req`. User-Agent header `ideajar/1.0`. Base URL configurabile. Parse JSON response → `display_name` field. Network error → `:service_unavailable`. Empty response → `:no_match`. |
| `Ideajar.Ideas` (esteso) | Context | `create_idea/1` accetta `location_name`, `lat`, `lng` come attrs. Pipeline invariate. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Nuovi assigns: `@selected_location_name :: String.t() \| nil`, `@selected_lat :: float \| nil`, `@selected_lng :: float \| nil`. Reset on mount, open form, close form, save success. Nuovi handler: `set_location` (parse + reverse geocode + assigns + close dialog), `remove_location` (reset 3), `update_location_name` (text input phx-change). Inject 3 fields in save. |
| `IdeajarWeb.Hooks.LeafletMap` (nuovo, JS) | Hook | Init Leaflet on `mounted()` con tile layer OSM. Click handler → `this.pushEvent("set_location", {lat, lng})`. Default center configurabile via `data-default-center` attribute. **No** state mgmt, **no** geocoding. |
| `IdeajarWeb.Components.LocationBadge` (nuovo) | Function component | `<.location_badge name={...}>` renders `📍 <name>` con HEEx auto-escape. data-testid="idea-location-badge". |
| Template `index.html.heex` (esteso) | HEEx | Nuovo fieldset `Posizione` con text input + bottone `📍 Apri mappa` + bottone condizionale `Rimuovi posizione`. Nuovo `<dialog id="location-map-dialog">` con map picker. Card list aggiunge location badge. |
| `assets/js/hooks/leaflet_map.js` (nuovo) | JS | Minimal hook (~30 LOC). Init + click handler. |

### Interfaces

**Schema (esteso):**
```elixir
schema "ideas" do
  field :title, :string
  field :description, :string
  field :url, :string
  field :duration, Ecto.Enum, values: Duration.values()
  field :estimated_cost, :integer
  field :location_name, :string
  field :lat, :float
  field :lng, :float
  many_to_many :categories, Category, ...
  timestamps()
end
```

**Migration:**
```elixir
alter table(:ideas) do
  add :location_name, :string, null: true
  add :lat, :float, null: true
  add :lng, :float, null: true
end
# SQLite: location_name = TEXT, lat/lng = REAL. All nullable.
```

**Domain API:**
```elixir
defmodule Ideajar.Geocoding do
  @spec reverse_lookup(float, float) ::
          {:ok, String.t()} | {:error, :no_match | :service_unavailable}
  defdelegate reverse_lookup(lat, lng), to: Ideajar.Geocoding.NominatimClient
end

# Test stubbing happens at the HTTP boundary via Req.Test.
# config/test.exs: config :ideajar, Ideajar.Geocoding.NominatimClient,
#   req_options: [plug: {Req.Test, IdeajarStub}]
# In each test: Req.Test.stub(IdeajarStub, fn conn -> ... end)
# For LV tests crossing process boundary: Req.Test.allow(IdeajarStub, self(), view.pid)
```

**LiveView assigns (estesi):**
- `@selected_location_name :: String.t() | nil`
- `@selected_lat :: float | nil`
- `@selected_lng :: float | nil`
- (Reset on mount, toggle_form open, close_form, save success — parallelo a `@selected_duration`, `@selected_cost`)

**LiveView events:**
- `set_location` con `%{"lat" => float, "lng" => float}` — parse + range check + reverse_lookup + assign + close dialog
- `remove_location` — reset 3 assigns
- `update_location_name` con `%{"name" => string}` — assign solo location_name (phx-change su text input)

**Componenti:**
```elixir
# LocationBadge
attr :name, :string, required: true
def location_badge(assigns) do
  ~H"""
  <span data-testid="idea-location-badge" class="...">📍 {@name}</span>
  """
end
```

**JS Hook:**
```js
export const LeafletMap = {
  mounted() {
    const center = JSON.parse(this.el.dataset.defaultCenter || '[41.9, 12.5]')
    this.map = L.map(this.el).setView(center, 5)
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

### Constraints

- **3-state validity**: 
  - (a) tutti nil → valid
  - (b) `location_name` only (lat=nil, lng=nil) → valid
  - (c) `location_name` + `lat` + `lng` (all set) → valid
  - (d) any other combination → invalid (`"Posizione incompleta"`)
- **Range validation**: `lat ∈ [-90, 90]`, `lng ∈ [-180, 180]`. Custom error `"Posizione non valida"` se fuori range o non-numeric.
- **`location_name` max 200 chars**, trimmed. Empty string after trim → nil. Error per > 200: `"Il nome del luogo non può superare i 200 caratteri"`.
- **Server-side reverse geocoding** via `Ideajar.Geocoding` defdelegate wrapper. HTTP stubbing test seam via `Req.Test` (cross-process safe). Network error → `:service_unavailable` flash. No-match → `:no_match` (location_name resta unchanged, coords set, submit fail con `"Posizione incompleta"` se name nil).
- **HEEx auto-escape**: badge rendering + text input value rendering. No `raw/1`.
- **Hostile `set_location` events**: non-numeric lat/lng, out-of-range, missing keys → no-op silenzioso (no crash, no assigns change).
- **HTML5 `<dialog>` modal**: `JS.exec("showModal", to: "#location-map-dialog")` per apertura, `JS.exec("close", to: ...)` per chiusura. Backdrop, focus trap, Esc-to-close sono native HTML5.
- **No custom JS oltre l'hook**: il modal mechanics sono HTML5 + LV native. Solo `LeafletMap` hook ha JS custom (~30 LOC, init + click).
- **Asset bundling**: vendoring `assets/vendor/leaflet.js` UMD + `assets/vendor/leaflet.css` (no `package.json` creato — preserva pattern progetto). CSS importato in `assets/css/app.css`. Leaflet UMD caricato via `<script>` tag in `root.html.heex` per evitare problemi esbuild UMD detection.
- **OSM attribution** visible inside the dialog (license requirement).
- **Backward compat**: idee esistenti con location_name/lat/lng nil dopo migration — comportamento invariato.

### Dependencies

- **NEW Hex**: `req` per HTTP client (Phoenix-idiomatic, lighter than HTTPoison). Aggiungere a `mix.exs`.
- **NEW vendor file**: `leaflet 1.9.4` UMD bundle + CSS in `assets/vendor/`. No npm package.json created.
- Nominatim public endpoint (no API key, policy: User-Agent + 1 req/sec rate limit).

### Out of scope

- Distance filter UI / Haversine (slice 7b)
- Geolocation hook (browser geolocation API + user position) (slice 7b)
- Mini-map sulla card idea (deferred)
- Multi-location idea (single-location for now)
- Edit location di idea esistente (no edit mode)
- Forward geocoding (search by name)
- Custom tile style / dark mode tile
- Map picker pre-position (default center always)
- Self-hosted Nominatim (public endpoint sufficiente per scala 2-user)
- Map picker zoom-to-fit on existing pin (always opens at default zoom)

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest + Req.Test stub).
- [ ] **F2** — Schema: `Idea.changeset/2` accetta `location_name`, `lat`, `lng` come attrs. NULL ammessi su tutti e 3.
- [ ] **F3** — Submit form senza alcun campo location → idea persistita con tutti e 3 nil.
- [ ] **F4** — Submit form con solo `location_name` → idea persistita con name + lat/lng nil.
- [ ] **F5** — Submit form con tutti e 3 i campi (post map click) → idea persistita correttamente.
- [ ] **F6** — Submit con coords-without-name → error `"Posizione incompleta"`, NOT persistita.
- [ ] **F7** — Submit con lat-without-lng (o viceversa) → error `"Posizione incompleta"`.
- [ ] **F8** — Submit con lat fuori range [-90, 90] → error `"Posizione non valida"`.
- [ ] **F9** — Submit con lng fuori range [-180, 180] → error `"Posizione non valida"`.
- [ ] **F10** — Submit con `location_name` > 200 chars → error `"Il nome del luogo non può superare i 200 caratteri"`.
- [ ] **F11** — `set_location` event success → reverse geocoding → 3 assigns set + dialog closed.
- [ ] **F12** — `set_location` event con `:service_unavailable` → coords set, name unchanged, flash error.
- [ ] **F13** — `set_location` event con `:no_match` → coords set, name unchanged, dialog closed.
- [ ] **F14** — `remove_location` event → 3 assigns reset a nil. Bottone non più visibile.
- [ ] **F15** — `update_location_name` event (text edit) → solo `@selected_location_name` cambia, lat/lng invariati.
- [ ] **F16** — Idea card location badge renderizzato solo se `location_name != nil` (with or without coords).
- [ ] **F17** — Reset `@selected_*` su mount, toggle_form open, close_form, save success.

### Form/Map UI

- [ ] **U1** — `<dialog id="location-map-dialog">` esiste nel DOM. `JS.exec("showModal", ...)` apre, `JS.exec("close", ...)` chiude.
- [ ] **U2** — Map dialog contains `<div phx-hook="LeafletMap" id="form-map-picker">` + close button + OSM attribution link.
- [ ] **U3** — Bottone `📍 Apri mappa` nel fieldset Posizione triggera `JS.exec("showModal")`.
- [ ] **U4** — Bottone `Rimuovi posizione` reso solo quando `@selected_location_name != nil OR @selected_lat != nil`.
- [ ] **U5** — Text input `location_name` ha `phx-change="update_location_name"` e mostra `value={@selected_location_name}`.

### Accessibility

- [ ] **A1** — Fieldset legend `Posizione` (no asterisco — opzionale).
- [ ] **A2** — Text input ha `<label>Luogo</label>` associato.
- [ ] **A3** — Bottone `📍 Apri mappa` ha `aria-haspopup="dialog"` (best practice WAI-ARIA APG).
- [ ] **A4** — Dialog ha `aria-labelledby` puntato al titolo del dialog (es. `<h2 id="location-map-title">Scegli posizione</h2>`).
- [ ] **A5** — Dialog ha bottone close con `aria-label="Chiudi"` (parallelo a slice 2 form close button).
- [ ] **A6** — HTML5 `<dialog>` provides native focus trap, backdrop, Esc-to-close (browser support: Chrome 37+, Safari 15.4+, Firefox 98+ — sufficiente per 2026 mobile).
- [ ] **A7** — Hit area chip-like buttons ≥ 44×44 CSS px (riuso `min-h-11 min-w-11` o ChipBase pattern).
- [ ] **A8** — Badge sulla card ha aria-label implicit dal text content ("📍 Sirolo, AN" letto literalmente).

### Security / robustness

- [ ] **S1** — `set_location` event con non-numeric o out-of-range coords → no-op silenzioso (test enumerated: `"abc"`, `91`, `-91`, `181`, `-181`, missing keys, non-string).
- [ ] **S2** — Submit con `location_name` malicious `<script>` → HEEx auto-escape sul render. Badge mostra escaped chars.
- [ ] **S3** — Reverse geocoding response malicious → trattato come stringa opaca, escaped sul render text input + badge.
- [ ] **S4** — `Geocoding.reverse_lookup/2` su input non valido → no raise (returns `{:error, _}`).
- [ ] **S5** — Nominatim service raise (network error) → caught dal client, returns `{:error, :service_unavailable}`. LV handler emit flash + lascia coords set. Process alive.
- [ ] **S6** — Hardcoded User-Agent header `ideajar/1.0` (Nominatim policy compliance).

### Operational / data

- [ ] **O1** — Migration `AddLocationToIdeas` reversibile loss-free pre-popolamento. SQLite ALTER TABLE x3 (1 statement per col, single migration). Test roundtrip + data preservation across rollback (BB16 pattern).
- [ ] **O2** — Schema introspection: `Idea.__schema__(:type, :location_name) == :string`, `:lat == :float`, `:lng == :float`.
- [ ] **O3** — `Ideajar.Geocoding.reverse_lookup/2` defdelegate to `NominatimClient`. Test stubbing tramite `Req.Test` (cross-process safe).
- [ ] **O4** — Performance: `create_idea/1` con location_name + coords + reverse_lookup mocked <50ms (sanity).

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13 + Pixel 7 + 360px Pixel 4a): form con fieldset Posizione, dialog map picker aperto full-screen, idea card con location badge, validation error `"Posizione incompleta"`.
- [ ] **V1a** — Lighthouse a11y mediana ≥95.
- [ ] **V1b** — Keyboard-only walkthrough: Tab nel fieldset Posizione, Enter apre dialog, Tab dentro dialog (close button + map non-focusable but click-only), Esc chiude dialog, focus restituito al bottone `📍 Apri mappa`.
- [ ] **V2** — Map picker manual test: click sul map → pin renders (Leaflet visual), reverse geocode autofills, dialog closes.
- [ ] **V2a** — Manual test Nominatim service unavailable (turn off network or stub) → flash error appears.

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 7a.
- [ ] **D2** — `CONTEXT.md` Modello dati aggiornato (slice 7a aggiunge `location_name`, `lat`, `lng`).
- [ ] **D3** — `test/ideajar_web/live/idea_live/index_test.exs`: out-of-scope guard regex aggiornato (rimuove riferimenti a "Distanza" — già out-of-scope; verifica positiva di `Posizione` nel form).
- [ ] **D4** — `test/ideajar/docs_test.exs`: nuova `describe "slice-7a UI copy"`.

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Label fieldset posizione (form) | `Posizione` (no asterisco — opzionale) |
| Label text input | `Luogo` |
| Bottone apri map picker | `📍 Apri mappa` |
| Bottone rimuovi posizione | `Rimuovi posizione` |
| Titolo dialog | `Scegli posizione` |
| Bottone chiudi dialog | aria-label `Chiudi` (visualizza `✕` come slice 2 form close) |
| OSM attribution (visibile) | `© OpenStreetMap` con link a `https://www.openstreetmap.org/copyright` |
| Errore posizione incompleta | `Posizione incompleta` |
| Errore posizione non valida (range/cast) | `Posizione non valida` |
| Errore nome luogo troppo lungo | `Il nome del luogo non può superare i 200 caratteri` |
| Flash error geocoding service down | `Geocodifica non disponibile, inserisci il nome manualmente` |
| Badge location card | `📍 <location_name>` |
| Badge data-testid | `idea-location-badge` |

## Consistency Gate

- [x] Intent unambiguo — 3-state validity + server-side geocoding + minimal-JS chiarissimi
- [x] Ogni behavior ha BDD scenario corrispondente (validation, dialog open/close, geocoding success/error/no-match, edit text after pin, hostile inputs, XSS regression)
- [x] Architecture constrains without over-engineering (defdelegate wrapper, Req.Test stubbing at HTTP boundary)
- [x] Termini consistenti (location, posizione, mappa, map picker, badge, dialog)
- [x] No contradictions — D1 (coords-without-name invalid) coerente con tutti i scenarios

**Verdict: PASS** — ready for `/plan`.
