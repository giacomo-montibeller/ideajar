# Spec: Distance filter on ideas

> Slice 7b. Adds a distance filter (HTML5 range slider, indices 0-6 mapped
> to km) above the ideas list. Reference point set via geolocation OR
> text search (Nominatim). Builds on slice 7a `lat`/`lng` schema. Pre-
> feature refactor: extract `LocationSearchInput` shared component reused
> by slice 7a form. Domain: new `Ideajar.Ideas.Distance.km/4` (Haversine)
> + `Ideajar.Ideas.Filter.apply_post/2` (in-memory post-query filter).

## Intent Description

Slice 7b introduce un **filtro distanza** sopra la lista delle idee.
L'utente fissa un **punto di riferimento** (`@user_lat`/`@user_lng`/
`@user_location_name`) e poi sposta uno slider per limitare le idee a
quelle entro un raggio fisso dal punto.

**Slider HTML5 `<input type="range">`** con 7 step indices, mappati a km:
- 0 = off (filtro inattivo, NULL-pass implicit)
- 1 = 5 km
- 2 = 25 km
- 3 = 50 km
- 4 = 200 km
- 5 = 500 km
- 6 = oltre 1000 km (= no upper cap, idee con coords mostrate, NULL escluse)

Slider sempre visible. Default index 0. **Disabled** (HTML attr +
`opacity-50` + helper text `Imposta un punto di riferimento per usare il
filtro distanza`) finché `@user_lat == nil`. ARIA
`aria-valuemin/max/now/valuetext`. Event `phx-change="update_max_distance"
phx-debounce="200"` per evitare haversine spam su drag.

**Punto di riferimento — DUE alternative input**:
1. **Geolocation**: bottone `📍 Usa la mia posizione` → JS hook
   `Geolocation` (~20 LOC) → `navigator.geolocation.getCurrentPosition`
   → `pushEvent("set_user_location", {lat, lng})` → server settta
   `@user_lat`/`@user_lng` + `@user_location_name = "La mia posizione"`.
   Permission denial: `pushEvent("user_location_denied", ...)` → flash
   error `"Permesso di geolocalizzazione negato"`. Bottone resta
   cliccabile per retry.
2. **Ricerca testuale**: text input + dropdown stile slice 7a (riusa
   componente). Min query 3 chars. Click result → assigns popolati con
   `display_name` da Nominatim.

**`LocationSearchInput` componente shared (pre-feature refactor)**: step 1
della slice estrae il pattern slice 7a (text input + dropdown + handler
gestiti via event-name parametrizzato) in
`IdeajarWeb.Components.LocationSearchInput`. Slice 7a form continua a
funzionare invariate post-refactor (riusa il nuovo componente). Slice 7b
filter è il secondo caller. Pattern parallelo a `ChipBase` extraction
slice 6 step 1.

**Reset matrix**:
- `Rimuovi punto di riferimento` (visible quando `@user_lat != nil`):
  reset 3 user_* assigns + slider a 0.
- `Rimuovi filtro distanza` (visible quando slider > 0): reset solo
  slider. Lascia ref point intoccato.
- `Mostra tutte` (slice 4 esteso): reset categoria + durata + budget +
  distanza + ref point. Tutto.
- Refresh / LV remount: reset di tutto (parallel `@filter_state` etc.).
- Save success: NESSUN reset per `@user_*` (filter state, non form). Lo
  slider NON viene resettato (filter persiste post-submit, parallel a
  slice 4 F11 + slice 5/6 invariants).

**Domain layer**:
- `Ideajar.Ideas.Distance.km/4` — Haversine puro Elixir (nuovo modulo).
  Test boundary: same point = 0, equator 1° E-W ≈ 111 km, pole-pole ≈
  20015 km, antipodi ≈ π × R.
- `Ideajar.Ideas.Filter.apply_post/2` — nuovo (parallel a `apply/2`).
  Opera su `[Idea.t()]` POST `Repo.all` + `Repo.preload`. Per la slice
  7b la sola clausola post-query è `apply_max_distance/2`. Razionale:
  SQLite non ha haversine native, custom SQL fragment con math
  functions richiede SQLite ≥ 3.35 + complessità. In-memory filter su
  scala 2-user (~100 idee) è istantaneo.
- `Ideajar.Ideas.list_ideas/1` aggiunge 3 nuove opts coordinate:
  `max_distance_km :: integer | nil`, `ref_lat :: float | nil`,
  `ref_lng :: float | nil`. Pipeline:
  ```
  base_query
  |> Filter.apply(opts)
  |> Repo.all()
  |> Repo.preload(...)
  |> Filter.apply_post(opts)
  ```

**NULL-exclude uniforme**: idee con `lat: nil` o `lng: nil` (state a
tutti-nil + state b name-only di slice 7a) escluse quando slider index
1-6. Helper text sotto sub-block: `Le idee senza posizione sono
nascoste quando un filtro è attivo.`

**Roving tabindex**: NIENTE sul sub-block distanza. Slider è singolo
elemento (focus naturale), search input è single input, geolocation
button singolo. RovingTabindex serve quando ci sono 5+ chip da navigare
con frecce. Qui non si applica.

**Combined filter**: distanza componibile in AND con categoria + durata
+ budget. Tutte clausole AND tra tipi.

**Out of scope**:
- URL params / deep-link distance state
- Map view dei risultati
- Watch-position (continuous tracking)
- Persistenza last-known-position cross-session (localStorage)
- Geofencing / inverse filtering
- Custom max_km value oltre i 6 step canonici
- Distanza renderizzata sulla card idea (es. "a 12 km")
- Reverse geocoding (slice 7a iter2 lo ha rimosso)

## User-Facing Behavior

```gherkin
Feature: Filter ideas by distance from a reference point

  Background:
    Given my browser holds a valid signed session cookie
    And the workspace has these ideas (with coords from Sirolo, AN baseline):
      | title             | location_name | lat   | lng   |
      | Sirolo            | Sirolo, AN    | 43.5  | 13.6  |
      | Ancona            | Ancona, AN    | 43.6  | 13.5  |
      | Roma colosseo     | Roma          | 41.9  | 12.5  |
      | Parigi            | Parigi        | 48.85 | 2.35  |
      | Bagno improvviso  | Casa di nonna |       |       |
      | Senza posizione   |               |       |       |

  # ── Initial state ───────────────────────────────────────────────
  Scenario: Visiting / shows the distance sub-block disabled
    When I visit "/"
    Then I see a sub-group with aria-label "Filtra per distanza"
    And the slider has the disabled attribute
    And it has aria-disabled="true"
    And the helper text "Imposta un punto di riferimento per usare il filtro distanza" is visible
    And the helper text "Le idee senza posizione sono nascoste quando un filtro è attivo." is visible
    And there is a "📍 Usa la mia posizione" button
    And there is a search input "Cerca punto di partenza"
    And there is no "Rimuovi punto di riferimento" button (no ref point set)
    And there is no "Rimuovi filtro distanza" button (slider at 0)

  # ── Geolocation reference point ─────────────────────────────────
  Scenario: Geolocation permission granted sets the reference point
    Given the JS Geolocation hook is mounted
    When the hook dispatches set_user_location with {lat: 43.6, lng: 13.5}
    Then @user_lat == 43.6
    And @user_lng == 13.5
    And @user_location_name == "La mia posizione"
    And the slider no longer has the disabled attribute
    And the label "Punto di riferimento: La mia posizione" is visible
    And the "Rimuovi punto di riferimento" button is rendered

  Scenario: Geolocation permission denied surfaces a flash error
    When the hook dispatches user_location_denied with {reason: "permission_denied"}
    Then a flash error appears with text "Permesso di geolocalizzazione negato"
    And @user_lat remains nil
    And the slider remains disabled
    And the "📍 Usa la mia posizione" button remains clickable

  Scenario: Geolocation timeout / generic error surfaces flash error
    When the hook dispatches user_location_denied with {reason: "timeout"}
    Then a flash error appears with text "Posizione non disponibile, riprova"
    And @user_lat remains nil

  # ── Text search reference point ─────────────────────────────────
  Scenario: Searching a place sets the reference point
    Given the Geocoding service returns [%{display_name: "Roma, RM", lat: 41.9, lng: 12.5}]
    When I type "roma" into the filter search input
    And I click the result "Roma, RM"
    Then @user_lat == 41.9
    And @user_lng == 12.5
    And @user_location_name == "Roma, RM"
    And the slider is no longer disabled
    And the label "Punto di riferimento: Roma, RM" is visible

  Scenario: Filter search dropdown follows slice 7a UX (min 3 chars, click-away dismiss)
    Given the filter search input is focused
    When I type "ro" (< 3 chars)
    Then no dropdown appears
    When I type "roma"
    Then a dropdown with up to 5 results appears
    When I click outside the dropdown
    Then the dropdown closes
    And @user_lat remains nil (no result selected)

  Scenario: Filter search dropdown service unavailable
    Given the Geocoding service returns {:error, :service_unavailable}
    When I type "roma" (≥ 3 chars)
    Then a flash error "Ricerca non disponibile, riprova" appears
    And the dropdown does NOT render

  Scenario: Selecting a new search result swaps reference but preserves slider
    Given the reference point is "Sirolo, AN" + slider at index 3 (50 km)
    When I search "roma" and click "Roma, RM"
    Then @user_lat == 41.9
    And @user_lng == 12.5
    And @user_location_name == "Roma, RM"
    And @max_distance_index remains 3
    And the slider remains enabled at value 3

  # ── Slider behavior ─────────────────────────────────────────────
  Scenario: Slider at index 0 means filter inactive
    Given the reference point is set to Sirolo
    When the slider is at index 0
    Then no distance filter is applied
    And all ideas (with and without coords) are visible

  Scenario: Slider at index 1 (5 km) filters within 5 km, NULL excluded
    Given the reference point is Sirolo (43.5, 13.6)
    When I move the slider to index 1
    Then I see "Sirolo" (distance 0 km) and "Ancona" (~14 km — out, wait, recompute)
    # Actually Ancona is ~16 km from Sirolo, so out of 5 km
    And I do not see "Roma" (~250 km, out)
    And I do not see "Parigi" (~1300 km, out)
    And I do not see "Bagno improvviso" (lat NULL, NULL-exclude)
    And I do not see "Senza posizione" (lat NULL, NULL-exclude)

  Scenario: Slider at index 2 (25 km) filters within 25 km
    Given reference Sirolo
    When the slider is at index 2
    Then I see Sirolo and Ancona (both within 25 km)
    And I do not see Roma, Parigi (out of range or NULL)

  Scenario: Slider at index 6 (oltre 1000 km) shows all priced ideas
    Given reference Sirolo
    When the slider is at index 6
    Then I see Sirolo, Ancona, Roma, Parigi (all priced ideas)
    And I do not see Bagno improvviso, Senza posizione (NULL excluded)

  Scenario: Slider exposes the full ARIA contract on mount
    When I visit "/"
    Then the slider has aria-valuemin="0"
    And aria-valuemax="6"
    And aria-valuenow="0"
    And aria-valuetext="Disattivo"

  Scenario: Slider value updates aria-valuetext to the canonical IT label
    When the slider is at index 3
    Then aria-valuenow="3"
    And aria-valuetext="fino a 50 km"
    When the slider is at index 6
    Then aria-valuetext="oltre 1000 km"

  Scenario: Slider phx-change is debounced 200ms
    When I drag the slider rapidly through 5 positions in 100ms
    Then only one server update_max_distance event is dispatched (after 200ms idle)

  # ── NULL-exclude uniform ────────────────────────────────────────
  Scenario: Ideas without coords hidden when slider index ≥ 1
    Given reference set, slider index 4 (200 km)
    Then no idea with lat=NULL or lng=NULL is rendered

  Scenario: Ideas without coords visible when slider index 0
    Given reference set, slider index 0
    Then all ideas (including NULL-coord ones) are visible

  # ── Combined filters ────────────────────────────────────────────
  Scenario: Distance combines with category as AND
    Given category "mare" required + reference Sirolo + slider 50 km
    Then result is ideas with mare AND distance ≤ 50 km AND coords set

  Scenario: All four filter types compose as AND
    Given category mare required + duration weekend + budget 500 + reference Sirolo + slider 50 km
    Then result is the intersection of all 4

  Scenario: Distance filter without reference point is no-op (slider already disabled)
    Given no reference point + slider somehow at index 3 (devtools)
    When the LV processes update_max_distance
    Then the filter is not applied (server-side guard: ref_lat nil → no-op)

  # ── Reset behaviors ─────────────────────────────────────────────
  Scenario: "Rimuovi punto di riferimento" clears 3 user_* + resets slider
    Given a reference point set + slider at index 3
    When I click "Rimuovi punto di riferimento"
    Then @user_lat == nil
    And @user_lng == nil
    And @user_location_name == nil
    And @max_distance_index == 0
    And the slider is disabled again
    And the "Rimuovi punto di riferimento" button is hidden
    And the "Rimuovi filtro distanza" button is hidden

  Scenario: "Rimuovi filtro distanza" resets only slider
    Given a reference point set + slider at index 3
    When I click "Rimuovi filtro distanza"
    Then @max_distance_index == 0
    And @user_lat is unchanged
    And @user_lng is unchanged
    And @user_location_name is unchanged
    And the slider remains enabled

  Scenario: "Mostra tutte" resets all 4 filter types + reference point
    Given category mare required + duration weekend + budget 100 + reference Sirolo + slider 50 km
    When I click "Mostra tutte"
    Then category, duration, budget, distance all reset
    And @user_lat, @user_lng, @user_location_name all nil
    And @max_distance_index == 0

  # ── User location persistence ───────────────────────────────────
  Scenario: Refresh resets the reference point (LV-session only)
    Given a reference point set
    When I reload "/"
    Then @user_lat, @user_lng, @user_location_name all nil
    And the slider is disabled

  Scenario: Form submission does NOT reset the reference point
    Given a reference point set
    And the form is opened
    And a valid idea is submitted
    Then after save success: reference point unchanged
    And the slider value unchanged
    And the new idea is in the list (filtered if it doesn't match the active distance)

  Scenario: Filter survives form submission (parallel slice 4 F11)
    Given a reference point set + slider 50 km
    When a valid idea (without coords) is submitted
    Then the idea is created in DB
    But it does NOT appear in the rendered list (NULL-excluded by active filter)

  # ── Hostile inputs ──────────────────────────────────────────────
  Scenario: set_user_location with non-numeric coords is no-op
    When the hook dispatches set_user_location with {lat: "abc", lng: 13.6}
    Then no @user_* assign changes
    And the LV process stays alive

  Scenario: set_user_location with out-of-range coords is no-op
    When dispatched with lat=91 (or -91, or lng=181, etc.)
    Then no-op

  Scenario: update_max_distance with index out of [0, 6] is no-op
    When server receives update_max_distance with %{value: "7"} (or "-1")
    Then @max_distance_index unchanged

  Scenario: update_max_distance with non-numeric value is no-op
    When server receives update_max_distance with %{value: "abc"}
    Then no-op

  Scenario: select_user_location with malformed payload is no-op
    When dispatched with missing keys or non-binary lat
    Then no-op

  # ── XSS regression ──────────────────────────────────────────────
  Scenario: Malicious user_location_name from search is HTML-escaped on render
    Given Geocoding returns a result with display_name "<script>alert(1)</script>"
    When the user clicks the result
    Then @user_location_name == "<script>alert(1)</script>" (raw atom value)
    And the rendered "Punto di riferimento: <name>" label is HTML-escaped
    And the rendered HTML does not contain executable <script>

  # ── LocationSearchInput refactor pin ────────────────────────────
  Scenario: Slice 7a form and slice 7b filter share LocationSearchInput
    When I inspect the codebase
    Then IdeajarWeb.Components.LocationSearchInput module exists
    And it is invoked from index.html.heex form fieldset Posizione (slice 7a)
    And it is invoked from index.html.heex filter sub-block Distanza (slice 7b)
    And its event names are caller-parametrized (not hardcoded)

  Scenario: Slice 7a form behavior unchanged after the refactor (regression pin)
    When I run the slice 7a form-fieldset tests
    Then they pass invariati post-refactor

  # ── Domain layer pins ───────────────────────────────────────────
  Scenario: Distance.km/4 returns 0 for the same point
    Then Ideajar.Ideas.Distance.km(43.5, 13.6, 43.5, 13.6) == 0.0

  Scenario: Distance.km/4 ≈ 111 km for 1 degree at the equator
    Then Ideajar.Ideas.Distance.km(0, 0, 0, 1) is approximately 111.32 (±0.5)

  Scenario: Distance.km/4 ≈ 20015 km for pole-to-pole
    Then Ideajar.Ideas.Distance.km(90, 0, -90, 0) is approximately 20015 (±10)

  Scenario: Filter.apply_post/2 with :max_distance_km filters in-memory
    Given a list of 5 ideas with coords + 1 with NULL coords
    When I call Filter.apply_post(list, max_distance_km: 5, ref_lat: 43.5, ref_lng: 13.6)
    Then the result includes only ideas within 5 km AND with non-nil lat/lng

  Scenario: Filter.apply_post/2 with nil :max_distance_km is no-op
    When I call Filter.apply_post(list, max_distance_km: nil)
    Then the full list is returned unchanged

  Scenario: Filter.apply_post/2 with index 6 mapping (oltre 1000 km) excludes NULL but includes all priced
    When I call Filter.apply_post(list, max_distance_km: 1_000_000, ref_lat: ..., ref_lng: ...)
    Then all ideas with non-nil coords are included (within 1M km is everything)
    And ideas with nil lat/lng are excluded

  Scenario: list_ideas/1 with all 5 filter types compose AND
    When I call list_ideas([required: [...], durations: [...], max_cost: 500, max_distance_km: 50, ref_lat: 43.5, ref_lng: 13.6])
    Then the result is the AND across all clauses

  Scenario: list_ideas/1 with no filters returns all ideas (regression)
    When I call list_ideas([])
    Then every idea is returned ordered by inserted_at DESC, id DESC

  # ── Out-of-scope guard ──────────────────────────────────────────
  Scenario: Slice 7b does not introduce text search filter UI
    When I visit "/"
    Then no element matches the text "Cerca" outside the distance reference search input
    # Slice 8 will add a global text search; slice 7b keeps "Cerca punto di partenza"
    # scoped to the distance sub-block.
```

## Architecture Specification

### Components

| Componente | Tipo | Responsabilità |
|---|---|---|
| `Ideajar.Ideas.Distance` (nuovo) | Modulo puro | `km/4 :: (lat1, lng1, lat2, lng2) -> float`. Haversine in pure Elixir. R = 6371 km. Test boundary cases pinned. |
| `Ideajar.Ideas.Filter` (esteso) | Modulo | `apply/2` invariato (Ecto.Query → Ecto.Query). NEW `apply_post/2 :: (list, opts) -> list` per filter post-query. NEW helper privato `apply_max_distance/2`. |
| `Ideajar.Ideas.list_ideas/1` (esteso) | Context fn | Nuove opts `:max_distance_km, :ref_lat, :ref_lng`. Pipeline: `Filter.apply(query, opts) \|> Repo.all() \|> Repo.preload(...) \|> Filter.apply_post(opts)`. |
| `IdeajarWeb.Components.LocationSearchInput` (nuovo, refactor pre-feature step 1) | Function component shared | Estrazione del pattern slice 7a (text input + dropdown + handler/event-name parametrizzato). Riusato sia da slice 7a form (caller per `@selected_location_*`) sia da slice 7b filter (caller per `@user_location_*`). Attrs: `id`, `name_value`, `search_results`, `search_state`, `on_change_event`, `on_select_event`, `on_dismiss_event`, `placeholder`. |
| `IdeajarWeb.IdeaLive.Index` (esteso) | LiveView | Nuovi assigns: `@user_lat`, `@user_lng`, `@user_location_name`, `@max_distance_index :: 0..6`, `@user_location_search_results`, `@user_location_search_state`. Nuovi handlers (vedi sotto). `clear_filters` esteso per resettare anche i 4 nuovi state. |
| `IdeajarWeb.Hooks.Geolocation` (nuovo, JS) | Hook | ~20 LOC. Mounted on the geolocation button. Click handler chiama `navigator.geolocation.getCurrentPosition(success, error)`. success → `pushEvent("set_user_location", {lat, lng})`. error → `pushEvent("user_location_denied", {reason})`. |
| Template `index.html.heex` (esteso) | HEEx | Nuovo sub-block `<div role="group" aria-label="Filtra per distanza">` dopo Budget. Sub-block contiene: bottone geolocation, `<LocationSearchInput>`, label `Punto di riferimento` (when set), bottone `Rimuovi punto di riferimento` (conditional), slider HTML5, valuetext label, bottone `Rimuovi filtro distanza` (conditional), 2 helper text. Slice 7a form fieldset Posizione viene aggiornato a usare `<LocationSearchInput>` con event names slice-7a (no behavior change). |

### Slider mapping

```elixir
# Mapping index → max km. Index 0 = filter off (NULL-pass).
# Index 6 = "oltre 1000 km" semantica = no upper cap (NULL-exclude only).
@distance_steps %{
  0 => nil,        # off, no filter applied
  1 => 5,
  2 => 25,
  3 => 50,
  4 => 200,
  5 => 500,
  6 => 1_000_000   # treated as "no upper cap" (NULL still excluded)
}

@distance_labels %{
  0 => "Disattivo",
  1 => "fino a 5 km",
  2 => "fino a 25 km",
  3 => "fino a 50 km",
  4 => "fino a 200 km",
  5 => "fino a 500 km",
  6 => "oltre 1000 km"
}
```

`@distance_labels` is the source of `aria-valuetext`. Visible label sotto
slider: `Distanza: <label>`.

### Interfaces

**Domain API:**
```elixir
defmodule Ideajar.Ideas.Distance do
  @moduledoc "Pure Haversine distance calculation."
  @earth_radius_km 6371.0

  @spec km(float, float, float, float) :: float
  def km(lat1, lng1, lat2, lng2) do
    # Haversine: 2R · asin(√(sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)))
  end
end

defmodule Ideajar.Ideas.Filter do
  # Existing query-only filter (slice 4-7a). Unchanged.
  @spec apply(Ecto.Query.t(), keyword()) :: Ecto.Query.t()

  # NEW slice 7b — post-query filter (operates on Idea structs in memory).
  @spec apply_post([Idea.t()], keyword()) :: [Idea.t()]
end

# list_ideas/1 opts (extended):
#   required: [integer]
#   optional: [integer]
#   durations: [atom]
#   max_cost: integer | nil
#   max_distance_km: integer | nil  # NEW
#   ref_lat: float | nil  # NEW
#   ref_lng: float | nil  # NEW
```

**LiveView assigns (estesi):**
- `@user_lat :: float | nil`
- `@user_lng :: float | nil`
- `@user_location_name :: String.t() | nil`
- `@max_distance_index :: 0..6` (default 0)
- `@user_location_search_results :: list` (default `[]`)
- `@user_location_search_state :: :idle | :searching | :empty | :results` (default `:idle`)

**LiveView events:**
- `set_user_location` con `%{"lat" => float, "lng" => float}` — from Geolocation hook. Validate range. On success: assign 3 user_* fields.
- `user_location_denied` con `%{"reason" => string}` — from Geolocation hook. Flash error. No assigns change.
- `update_user_location_name` con form-shape OR direct-shape — from filter LocationSearchInput. Same logic as slice 7a `update_location_name` but assigns `@user_location_name` and triggers Geocoding.search.
- `select_user_location` con `%{"name", "lat", "lng"}` — from filter dropdown click. Defensive parse + range check. Assign 3 user_* fields. Reset search state.
- `dismiss_user_location_search` — click-away. Reset search state.
- `remove_user_location` — button click. Reset 3 user_* assigns + slider to 0.
- `update_max_distance` con `%{"value" => string}` — slider phx-change. Defensive parse to integer 0..6. Assign `@max_distance_index`.
- `remove_distance_filter` — button click. Reset slider to 0 only.
- `clear_filters` (slice 4 esteso) — reset categoria + durata + budget + distanza + ref point. Tutto.

**Componente `LocationSearchInput`:**
```elixir
attr :id, :string, required: true
attr :name, :string, required: true  # form name attr
attr :name_value, :string  # current value of text input
attr :placeholder, :string, default: ""
attr :search_results, :list, required: true
attr :search_state, :atom, required: true, values: [:idle, :searching, :empty, :results]
attr :on_change_event, :string, required: true
attr :on_select_event, :string, required: true
attr :on_dismiss_event, :string, required: true
```

**JS Hook `Geolocation`:**
```js
export const Geolocation = {
  mounted() {
    this.el.addEventListener("click", () => {
      if (!navigator.geolocation) {
        this.pushEvent("user_location_denied", { reason: "unsupported" })
        return
      }
      navigator.geolocation.getCurrentPosition(
        (pos) => this.pushEvent("set_user_location", {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude
        }),
        (err) => {
          // W3C PositionError: 1=PERMISSION_DENIED, 2=POSITION_UNAVAILABLE, 3=TIMEOUT
          const reason =
            err.code === 1 ? "permission_denied" :
            err.code === 2 ? "unavailable" :
            err.code === 3 ? "timeout" : "unsupported"
          this.pushEvent("user_location_denied", { reason })
        }
      )
    })
  }
}
```

### Constraints

- **Slider HTML5 `<input type="range" min="0" max="6" step="1">`**, `disabled` attr quando `@user_lat == nil` (CSS opacity-50 + cursor-not-allowed). `phx-change="update_max_distance" phx-debounce="200"`. ARIA `aria-valuemin="0"`, `aria-valuemax="6"`, `aria-valuenow={@max_distance_index}`, `aria-valuetext={@distance_labels[@max_distance_index]}`. `aria-disabled={if @user_lat == nil, do: "true", else: "false"}`.
- **`@user_lat`/`@user_lng` server-side validation**: `lat ∈ [-90, 90]`, `lng ∈ [-180, 180]`. Range check su tutti gli input handlers. Out-of-range → no-op silenzioso.
- **`@max_distance_index` server-side validation**: `0..6`. Out-of-range → no-op.
- **NULL-exclude in `apply_max_distance/2`**: idee con `lat: nil` o `lng: nil` filtrate via `Enum.filter` quando `:max_distance_km` opt è non-nil.
- **In-memory haversine**: `Filter.apply_post/2` chiama `Distance.km/4` per ogni idea. Per scala 2-user (~100 idee) è O(N) acceptable. Trigger per spatial index: ≥ 1000 idee.
- **`LocationSearchInput` extraction (step 1 pre-feature)**: refactor puro slice 7a, no behavior change. Slice 7a tests pass invariati. Step 2+ usa il componente.
- **Geolocation hook minimal**: `~20 LOC`. NO state machine, NO retry logic, NO permission persistence. Fail-fast: error → flash + retry button cliccabile.
- **Hostile inputs uniform list**: applicato a `set_user_location`, `update_user_location_name`, `select_user_location`, `update_max_distance`. 5-8 cases per handler (parallel slice 6/7a patterns).
- **NULL-exclude pattern uniforme** con slice 5 durata + slice 6 budget. Documentato in `CONTEXT.md` `## Decisione su filtri non applicabili`.
- **`@user_*` LV-session only**: no localStorage, no DB. Refresh = reset.
- **`@user_*` NOT reset on save success** (filter state, NOT form state).
- **`Mostra tutte` esteso**: 5 reset (categoria + durata + budget + distanza + ref point).
- **Combined filter AND**: distanza × categoria × durata × budget tutto AND.
- **HEEx auto-escape** sul rendering `Punto di riferimento: <name>` label.

### Dependencies

Nessuna nuova dep Hex. Geolocation hook è ~20 LOC custom JS.

### Out of scope

- URL params / deep-link distance state
- Map view dei risultati
- Watch-position (continuous tracking)
- Persistenza last-known-position cross-session (localStorage)
- Geofencing
- Custom max_km value oltre i 6 step canonici
- Distanza renderizzata sulla card idea (es. "a 12 km da te")
- Reverse geocoding (slice 7a iter2 lo ha rimosso)

## Acceptance Criteria

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano (DataCase + LiveViewTest).
- [ ] **F2** — Mount: slider disabled, default index 0, ref point nil.
- [ ] **F3** — `set_user_location` (geolocation hook) con coords valide → 3 user_* assigns settati. `@user_location_name = "La mia posizione"`.
- [ ] **F4** — `user_location_denied` reason "permission_denied" → flash error `"Permesso di geolocalizzazione negato"`. No assigns change.
- [ ] **F5** — `user_location_denied` altro reason → flash error `"Posizione non disponibile, riprova"`. No assigns change.
- [ ] **F6** — `select_user_location` (filter search dropdown click) con result valido → 3 user_* set. `@user_location_name = result.display_name`.
- [ ] **F7** — `update_user_location_name` ≥3 chars → search Nominatim → dropdown popolato.
- [ ] **F8** — Slider disabled finché `@user_lat == nil`.
- [ ] **F9** — Slider enabled dopo set ref point (qualsiasi path).
- [ ] **F10** — `update_max_distance` index 0..6 → assign `@max_distance_index`. Filter applied via `apply_post`.
- [ ] **F11** — `update_max_distance` index 0 → filter inactive (NULL-pass).
- [ ] **F12** — `update_max_distance` index 1..5 → ideas con coords entro X km. NULL escluse.
- [ ] **F13** — `update_max_distance` index 6 → ideas con coords (qualsiasi distanza). NULL escluse.
- [ ] **F14** — `remove_user_location` → 3 user_* nil + slider 0. Slider disabled.
- [ ] **F15** — `remove_distance_filter` → slider 0 only. Ref point unchanged.
- [ ] **F16** — `clear_filters` (Mostra tutte) → reset 5 filter types + ref point.
- [ ] **F17** — Refresh resetta `@user_*` + slider (LV remount).
- [ ] **F18** — Save success NON resetta `@user_*` né slider (filter survives submit).
- [ ] **F19** — Filter combined AND con altri 3 (categoria + durata + budget).

### LocationSearchInput refactor

- [ ] **R1** — `IdeajarWeb.Components.LocationSearchInput` modulo esiste con `attr` declarations come da spec.
- [ ] **R2** — Slice 7a form fieldset Posizione usa `<LocationSearchInput>` componente.
- [ ] **R3** — Slice 7b filter sub-block Distanza usa `<LocationSearchInput>` componente.
- [ ] **R4** — Slice 7a form behavior invariato post-refactor (tutti i test slice 7a passano).
- [ ] **R5** — Event names parametrized: form usa `update_location_name`/`select_location`/`dismiss_location_search`; filter usa `update_user_location_name`/`select_user_location`/`dismiss_user_location_search`.

### Domain layer

- [ ] **D1** — `Ideajar.Ideas.Distance.km/4` ritorna 0 per stesso punto.
- [ ] **D2** — `Distance.km(0, 0, 0, 1)` ≈ 111.32 km (±0.5).
- [ ] **D3** — `Distance.km(90, 0, -90, 0)` ≈ 20015 km (±10).
- [ ] **D4** — `Distance.km/4` per (43.5, 13.6, 41.9, 12.5) ≈ Sirolo→Roma (~200 km, ±5).
- [ ] **D5** — `Filter.apply_post/2` con `:max_distance_km` nil → no-op (passa la lista invariata).
- [ ] **D6** — `Filter.apply_post/2` con `:max_distance_km: 5, ref_lat: 43.5, ref_lng: 13.6` → solo ideas entro 5 km AND con non-nil coords.
- [ ] **D7** — `Filter.apply_post/2` con index 6 mapping (1_000_000 km) → tutte le ideas con coords (NULL escluse).
- [ ] **D8** — `Ideas.list_ideas([])` invariato (regression).
- [ ] **D9** — `Ideas.list_ideas([max_distance_km: 50, ref_lat: 43.5, ref_lng: 13.6])` filtra correttamente.
- [ ] **D10** — `Ideas.list_ideas([required: [...], durations: [...], max_cost: 500, max_distance_km: 50, ref_lat: ..., ref_lng: ...])` combina in AND tra clausole (query + post).

### Accessibility

- [ ] **A1** — Slider ha `role="slider"` (HTML5 native), `aria-valuemin="0"`, `aria-valuemax="6"`, `aria-valuenow={index}`, `aria-valuetext={label}`.
- [ ] **A2** — Slider `aria-disabled` correlato a `disabled` attr.
- [ ] **A3** — Sub-block ha `role="group" aria-label="Filtra per distanza"`.
- [ ] **A4** — Helper text NULL-exclude visibile sempre nel sub-block.
- [ ] **A5** — Helper text "Imposta un punto di riferimento per usare il filtro distanza" visibile quando `@user_lat == nil`.
- [ ] **A6** — Bottone geolocation hit area ≥ 44×44 (riuso ChipBase classes).
- [ ] **A7** — Filter row sub-block order: Categorie → Durata → Budget → Distanza in DOM source order.
- [ ] **A8** — Slider thumb touch target ≥ 44×44 px (mobile). Implementazione via CSS custom su `::-webkit-slider-thumb` + `::-moz-range-thumb`. Track height ≥ 8 px per visibilità.
- [ ] **A9** — Sub-block layout: bottone geolocation + search input stacked verticalmente su mobile (`< 640 px`), affiancati su `≥ sm` (≥640 px). Helper text e label `Punto di riferimento` su riga separata.

### Security / robustness

- [ ] **S1** — `set_user_location` con cosa hostile → no-op (uniform list 8 inputs: stringhe non-numeric, out-of-range, missing keys, non-binary, lat=91, lng=-181, ecc.).
- [ ] **S2** — `update_max_distance` con index out-of-range (-1, 7, 999) o non-numeric → no-op.
- [ ] **S3** — `select_user_location` con payload malformato → no-op.
- [ ] **S4** — `update_user_location_name` con payload non-binary → no-op (parallel slice 7a hostile uniform list).
- [ ] **S5** — XSS regression sul label `Punto di riferimento: <name>` (HEEx auto-escape `{@user_location_name}`).
- [ ] **S6** — Geolocation hook denial reason mappings: `"permission_denied"`, `"timeout"`, `"unsupported"`. Generic fallback. NO arbitrary string passa al render.
- [ ] **S7** — `Distance.km/4` non lancia su input arbitrari (no NaN, no float overflow). Range check upstream.

### Operational / data

- [ ] **O1** — Nessuna migration. Schema slice 7a (lat/lng) sufficiente.
- [ ] **O2** — `Filter.apply_post/2` testato indipendentemente con unit test (ogni clausola post + composizione).
- [ ] **O3** — Performance: `list_ideas` con 4 filter attivi + 100 idee fixture <100 ms (sanity).
- [ ] **O4** — `Ideajar.Ideas.Distance.km/4` testato indipendentemente con boundary cases (5 test minimo).

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13, Pixel 7, 360px Pixel 4a): sub-block distanza disabled, sub-block enabled con ref point + slider, dropdown search filtro, label `Punto di riferimento` visible.
- [ ] **V1a** — Lighthouse a11y mediana ≥95 con tutti i filtri attivi.
- [ ] **V1b** — Keyboard-only walkthrough: Tab al sub-block distanza, Enter sul bottone geolocation (mock no-permission), Tab a search input, type + arrow keys + Enter su risultato (or click), Tab al slider, frecce per cambiare valore, Tab al `Rimuovi punto di riferimento`.
- [ ] **V2** — Manual test geolocation reale: grant permission → coords settati. Deny permission → flash error.

### Documentation

- [ ] **D1d** — `docs/conventions.md` UI copy table aggiornata con stringhe slice 7b.
- [ ] **D2d** — `CONTEXT.md` Modello dati invariato (no schema change). `Filtri` section già menziona "Distanza max da me — slider" (CONTEXT.md riga 80) — aggiornare se serve per documentare il fatto che è implementato.
- [ ] **D3d** — `CONTEXT.md` `## Decisione su filtri non applicabili` esteso per includere `distanza` nel pattern uniforme NULL-exclude.
- [ ] **D4d** — `test/ideajar/docs_test.exs`: nuova `describe "slice-7b UI copy"`.
- [ ] **D5d** — Nessun cambio out-of-scope guard regex (slice 8 search ancora out-of-scope; "Cerca punto di partenza" è scoped al sub-block distanza, deve essere chiarito nel guard test).

### UI copy aggiunta (canonical)

| Elemento | Testo IT |
|---|---|
| Sub-label filter Distanza (visivo) | `Distanza` |
| Aria-label sub-block (SR) | `Filtra per distanza` |
| Bottone geolocation | `📍 Usa la mia posizione` |
| Placeholder filter search input | `Cerca punto di partenza` |
| Label punto di riferimento | `Punto di riferimento: <name>` |
| `@user_location_name` per geolocation | `La mia posizione` |
| Bottone rimuovi ref point | `Rimuovi punto di riferimento` |
| Bottone rimuovi filtro distanza | `Rimuovi filtro distanza` |
| Slider valuetext idx 0 | `Disattivo` |
| Slider valuetext idx 1 | `fino a 5 km` |
| Slider valuetext idx 2 | `fino a 25 km` |
| Slider valuetext idx 3 | `fino a 50 km` |
| Slider valuetext idx 4 | `fino a 200 km` |
| Slider valuetext idx 5 | `fino a 500 km` |
| Slider valuetext idx 6 | `oltre 1000 km` |
| Helper text disabled state | `Imposta un punto di riferimento per usare il filtro distanza` |
| Helper text NULL-exclude | `Le idee senza posizione sono nascoste quando un filtro è attivo.` |
| Flash error permission denied | `Permesso di geolocalizzazione negato` |
| Flash error generico geolocation | `Posizione non disponibile, riprova` |
| Flash error ricerca punto di partenza non disponibile | `Ricerca non disponibile, riprova` |

## Consistency Gate

- [x] Intent unambiguo — slider + 2 alternative ref point + Haversine + post-query filter chiariti
- [x] Ogni behavior ha BDD scenario corrispondente (geolocation success/denied/timeout, search success/empty/error, slider 7 indices, reset matrix, hostile inputs, XSS regression, refactor pin, domain pins)
- [x] Architecture constrains without over-engineering (in-memory haversine giustificato dalla scala, refactor pre-feature giustificato dal use-case 2, no state machine inutili)
- [x] Termini consistenti (slider, indice, ref point, "punto di riferimento", NULL-exclude, fino a X)
- [x] No contradictions — `@user_*` LV-session vs save-success preservation chiarito; "oltre 1000 km" semantica documentata sia per UI label sia per filter logic

**Verdict: PASS** — ready for `/plan`.
