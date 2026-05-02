# Plan: Slice 7b — Distance filter

**Created**: 2026-05-02
**Branch**: main (trunk-based)
**Status**: approved
**Spec**: `docs/specs/distance-filter-on-ideas.md`

## Build conventions (carried from slice 1-7a)

- **Strict TDD** — RED → GREEN → REFACTOR per step.
- **Ogni commit** attraverso la skill `commit-message`. In `/build` uso option 1 default.
- Pre-step gate: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo`, `mix deps.audit`, `mix test --include migration`.
- Domain in `Ideajar.*`, delivery in `IdeajarWeb.*`.
- UI copy IT canonica appesa a `docs/conventions.md` nello step 10.
- Trunk-based su `main`, ogni step lascia il codebase committable.

## Goal

Slice 7b aggiunge un **filtro distanza** sopra la lista delle idee. UI: HTML5 `<input type="range">` con 7 step indices (0=off, 1=5km, …, 6=oltre 1000km). Reference point settable via geolocation (JS hook minimale ~20 LOC) OR ricerca testuale (Nominatim, riusa `LocationSearchInput` shared component estratto al step 1). Domain: `Ideajar.Ideas.Distance.km/4` (Haversine puro Elixir) + `Ideajar.Ideas.Filter.apply_post/2` (in-memory post-query filter su scala 2-user). NULL-exclude uniforme (idee senza coords nascoste quando filter on).

Foundation: schema slice 7a (`lat`/`lng`). Nessuna nuova migration.

Fuori scope: URL params, map view, watch-position continuo, persistence cross-session, geofencing, custom max_km, distance display sulla card, reverse geocoding (rimosso 7a iter2).

## Decisioni architetturali pre-build

- **DD1 — `LocationSearchInput` extraction (refactor pre-feature, step 1)**: estrai pattern slice 7a-iter2 (text input + dropdown + handler con event-name parametrizzato) in `IdeajarWeb.Components.LocationSearchInput`. Slice 7a form usa il nuovo componente con event names esistenti (`update_location_name`/`select_location`/`dismiss_location_search`). Slice 7b filter è il secondo caller con event names `update_user_location_name`/`select_user_location`/`dismiss_user_location_search`. Step 1 RED: regression invariante (slice 7a tests passano), positive (componente esiste con attr declarations). Pattern parallelo a slice 6 step 1 ChipBase extraction.
- **DD2 — `Ideajar.Ideas.Distance.km/4` puro Elixir Haversine** (step 2). `R = 6371.0` km. Test boundary: same point = 0, equator E-W 1° ≈ 111.32 km, pole-to-pole ≈ 20015 km, antipodi ≈ π·R, real-world Sirolo↔Roma ≈ 200 km, Sirolo↔Parigi ≈ 1300 km.
- **DD3 — `Ideajar.Ideas.Filter.apply_post/2` (step 3)**: nuovo path post-query nel modulo Filter. Funzione opera su `[Idea.t()]` post-`Repo.all` + `Repo.preload`. Parallel pattern a `apply/2` query path. Slice 7b clausola unica: `apply_max_distance/2`. **DD3-extension trigger**: 3+ post-query clausole → estrai in `Ideajar.Ideas.Filter.PostQuery` modulo separato. Slice 7b NON estrae (rule of 1).
- **DD4 — NULL-exclude post-query semantics (G fix)**: index 0 = no filter (NULL passa); index 1-5 = filter cumulativo + NULL escluse; index 6 = "oltre 1000 km" semantica = no upper cap (1_000_000 km come max), NULL ancora escluse. La differenza tra index 0 e index 6 è SOLO il NULL treatment. Documentato in `apply_max_distance/2` docstring + test pin.
- **DD5 — `list_ideas/1` opts coordinated validation (H fix)**: `:max_distance_km` set ma `:ref_lat` o `:ref_lng` nil → no-op silenzioso (filter non applicato). Pattern parallelo a slice 6 `:max_cost: nil` no-op.
- **DD6 — Geolocation hook su button element**: `phx-hook="Geolocation"` direttamente sul `<button id="user-location-button">`. `mounted()` registra click listener. Click → `navigator.geolocation.getCurrentPosition` → `pushEvent`. ~20 LOC totali. NO state machine.
- **DD7 — Geolocation error code mapping (J fix)**: W3C spec error.code: `1=PERMISSION_DENIED`, `2=POSITION_UNAVAILABLE`, `3=TIMEOUT`. Hook mappa a string: `"permission_denied"`/`"unavailable"`/`"timeout"`/`"unsupported"` (per missing API). Server LV handler `user_location_denied` riceve reason atom (after parse) e mappa a flash error IT.
- **DD8 — Slider `phx-debounce="200"` (C confirmed)**: HTML5 input range fires su ogni drag pixel (~60 events/sec). Debounce 200ms permette ~5 events/sec. Per haversine in-memory su 100 idee è acceptable. Trigger per `phx-throttle` invece: utenti percepiscono lag in drag.
- **DD9 — Slider value parse (F)**: handler `update_max_distance` riceve `%{"value" => "3"}`. Parse `Integer.parse/1` → check 0..6 → assign or no-op. Hostile uniform list 5 inputs (`"abc"`, `"-1"`, `"7"`, `"3.5"`, `nil`).
- **DD10 — `reset_distance_filter/1` helper (E)**: estrai per DRY. Resetta `@max_distance_index` a 0. Chiamato da: `clear_filters` (Mostra tutte), `remove_distance_filter`, `remove_user_location` (cascade reset).
- **DD11 — `@user_*` LV-session only (C1 confirmed)**: NO localStorage. Refresh = reset (LV remount). Save success NON resetta (filter persiste post-submit).
- **DD12 — `derive_filter_opts/N` extension (I)**: helper che aggrega gli opts da passare a `Ideas.list_ideas/1`. Esteso per includere `:max_distance_km` (mappato da `@max_distance_index` via `@distance_steps`), `:ref_lat`, `:ref_lng`.
- **DD13 — Slider `disabled` attr quando `@user_lat == nil` (E3 confirmed)**: HTML disabled + `aria-disabled="true"` + Tailwind `opacity-50 cursor-not-allowed` + helper text esplicito visible.
- **DD14 — Sub-block layout dopo Budget**: parallel pattern slice 5/6 sub-block. `<div role="group" aria-label="Filtra per distanza">`. NO RovingTabindex (slider + search input + button singoli, focus naturale via Tab).
- **DD15 — `Mostra tutte` extension**: reset 5 filter types (categoria + durata + budget + distanza + ref point). Helper privato `clear_all_filters/1` parallel a slice 6 pattern.
- **DD16 — `LocationSearchInput` attr surface (B warning)**: 7+ attrs (id, name, name_value, placeholder, search_results, search_state, on_change_event, on_select_event, on_dismiss_event). Soglia per refactor (es. callback module pattern): 10+ attrs OR 3+ caller modules. Slice 7b lascia l'attr surface; future slice valuteranno.
- **DD17 — `phx-hook="Geolocation"` su `<button>` element**: valid Phoenix pattern (LV mounts hook on any element with `id`). Button click registers via hook's `mounted()` event listener.
- **DD18 — Filter combined 5-way AND**: distanza × categoria × durata × budget × (NULL-exclude per ognuno separately). Test pin in step 4.
- **DD19 — User location reset matrix**: 
  - `remove_user_location` → reset 3 user_* + slider 0 (cascade)
  - `remove_distance_filter` → slider 0 only
  - `clear_filters` (Mostra tutte) → reset all 5 + ref point
  - `select_user_location` swap → 3 user_* updated + slider state preserved
  - Refresh → all reset (LV remount)
  - Save success → NO reset (DD11)

## Acceptance Criteria

> Mappatura uno-a-uno con `docs/specs/distance-filter-on-ideas.md`.

### Functional / behavioral

- [ ] **F1** — Tutti gli scenari Gherkin automatabili passano.
- [ ] **F2** — Mount: slider disabled, default index 0, ref point nil.
- [ ] **F3** — `set_user_location` (geolocation) con coords valide → 3 user_* settati + label "La mia posizione".
- [ ] **F4** — `user_location_denied` "permission_denied" → flash `"Permesso di geolocalizzazione negato"`.
- [ ] **F5** — `user_location_denied` altri reasons → flash `"Posizione non disponibile, riprova"`.
- [ ] **F6** — `select_user_location` (search dropdown click) → 3 user_* set + label da result.
- [ ] **F7** — `update_user_location_name` ≥3 chars → search Nominatim → dropdown.
- [ ] **F8** — Slider disabled finché `@user_lat == nil`.
- [ ] **F9** — Slider enabled dopo set ref point (qualsiasi path).
- [ ] **F10** — `update_max_distance` index 0..6 → assign + filter applied.
- [ ] **F11** — Slider index 0 → filter inactive (NULL-pass).
- [ ] **F12** — Slider index 1..5 → ideas con coords entro X km, NULL escluse.
- [ ] **F13** — Slider index 6 → ideas con coords (qualsiasi distanza), NULL escluse.
- [ ] **F14** — `remove_user_location` → 3 user_* nil + slider 0 + slider disabled.
- [ ] **F15** — `remove_distance_filter` → slider 0 only.
- [ ] **F16** — `clear_filters` → reset 5 filter types + ref point.
- [ ] **F17** — Refresh resetta `@user_*` + slider (LV remount).
- [ ] **F18** — Save success NON resetta `@user_*` né slider.
- [ ] **F19** — Filter combined AND con altri 3.

### Refactor (DD1)

- [ ] **R1** — `IdeajarWeb.Components.LocationSearchInput` modulo esiste con attrs come da spec.
- [ ] **R2** — Slice 7a form fieldset Posizione usa `<LocationSearchInput>`.
- [ ] **R3** — Slice 7b filter sub-block Distanza usa `<LocationSearchInput>`.
- [ ] **R4** — Slice 7a form behavior invariato post-refactor (regression).
- [ ] **R5** — Event names parametrized correttamente (form vs filter).

### Domain layer

- [ ] **DM1** — `Distance.km/4` ritorna 0 per stesso punto.
- [ ] **DM2** — `Distance.km(0, 0, 0, 1)` ≈ 111.32 km (±0.5).
- [ ] **DM3** — `Distance.km(90, 0, -90, 0)` ≈ 20015 km (±10).
- [ ] **DM4** — `Distance.km/4` per coppie real-world (Sirolo↔Roma ≈ 200, Sirolo↔Parigi ≈ 1300, ±5%).
- [ ] **DM5** — `Filter.apply_post/2` con `:max_distance_km nil` → no-op.
- [ ] **DM6** — `Filter.apply_post/2` con `max_distance_km: 5, ref_lat, ref_lng` → solo entro 5 km AND non-nil coords.
- [ ] **DM7** — `Filter.apply_post/2` con `max_distance_km: 1_000_000` → tutte ideas con coords (NULL escluse).
- [ ] **DM8** — `Filter.apply_post/2` con `:ref_lat` o `:ref_lng` nil → no-op (defensive — DD5).
- [ ] **DM9** — `Ideas.list_ideas([])` invariato (regression).
- [ ] **DM10** — `Ideas.list_ideas([max_distance_km: 50, ref_lat, ref_lng])` filtra correttamente.
- [ ] **DM11** — `Ideas.list_ideas` 5-way combined AND (categoria + durata + budget + distanza + ref).

### Accessibility

- [ ] **A1** — Slider HTML5 native role="slider", `aria-valuemin/max/now/valuetext`.
- [ ] **A2** — `aria-disabled` sincronizzato con `disabled` attr.
- [ ] **A3** — Sub-block ha `role="group" aria-label="Filtra per distanza"`.
- [ ] **A4** — Helper text NULL-exclude visibile sempre.
- [ ] **A5** — Helper text "Imposta un punto di riferimento" visible quando user_lat nil.
- [ ] **A6** — Hit area button geolocation ≥ 44×44 (riuso ChipBase classes).
- [ ] **A7** — Filter row sub-block order: Categorie → Durata → Budget → Distanza.
- [ ] **A8** — Slider thumb touch target ≥ 44×44 px su mobile (CSS custom su `::-webkit-slider-thumb` + `::-moz-range-thumb`). Track height ≥ 8 px.
- [ ] **A9** — Sub-block layout responsive: bottone geolocation + search input stacked (mobile <640px) o affiancati (≥sm). Helper text e label `Punto di riferimento` su riga separata.

### Security / robustness

- [ ] **S1** — `set_user_location` hostile uniform list (8 inputs: non-numeric, out-of-range, missing keys, non-binary lat).
- [ ] **S2** — `update_max_distance` hostile uniform (5 inputs: `"abc"`, `"-1"`, `"7"`, `"3.5"`, missing key).
- [ ] **S3** — `select_user_location` malformed payload → no-op.
- [ ] **S4** — `update_user_location_name` non-binary → no-op (parallel slice 7a).
- [ ] **S5** — XSS regression label `Punto di riferimento: <name>` (HEEx auto-escape).
- [ ] **S6** — Geolocation hook denial reason mapping limited to known values.
- [ ] **S7** — `Distance.km/4` no raise su input arbitrari (range check upstream garantisce).

### Operational / data

- [ ] **O1** — Nessuna migration. Schema slice 7a sufficiente.
- [ ] **O2** — `Filter.apply_post/2` testato indipendentemente (5+ tests).
- [ ] **O3** — Performance: list_ideas con 4 filter attivi + 100 idee fixture <100 ms (sanity).
- [ ] **O4** — `Distance.km/4` boundary cases (5 tests minimi).
- [ ] **O5** — JS hook `Geolocation` registration in app.js verificato via file read pin.

### Validation venue

- [ ] **V1** — Screenshot mobile (iPhone 13, Pixel 7, 360px Pixel 4a): sub-block disabled, sub-block enabled, dropdown search, slider con valuetext, label ref point.
- [ ] **V1a** — Lighthouse a11y mediana ≥95.
- [ ] **V1b** — Keyboard-only walkthrough.
- [ ] **V2** — Manual geolocation test reale (grant + deny).

### Documentation

- [ ] **D1** — `docs/conventions.md` UI copy table slice 7b (~18 strings).
- [ ] **D2** — `CONTEXT.md` Modello dati invariato (no schema change).
- [ ] **D3** — `CONTEXT.md` `## Decisione su filtri non applicabili` esteso per includere distanza nel pattern uniforme NULL-exclude.
- [ ] **D4** — `test/ideajar/docs_test.exs`: nuova `describe "slice-7b UI copy"`.
- [ ] **D5** — Out-of-scope guard: `"Cerca punto di partenza"` è scoped al sub-block distanza, NON match con futuro slice 8 search globale.

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

## Steps

### Step 1: REFACTOR — `LocationSearchInput` extraction (DD1)

**Complexity**: standard
**Rationale**: refactor puro pre-feature. Slice 7a form e 7b filter useranno lo stesso componente.

**RED** (`test/ideajar_web/components/location_search_input_test.exs` new):
1. Module exists with `attr` declarations: `:id`, `:name`, `:name_value`, `:placeholder`, `:search_results`, `:search_state`, `:on_change_event`, `:on_select_event`, `:on_dismiss_event`.
2. Render con `state: :idle` → no listbox.
3. Render con `state: :searching` → "Cerco…" item.
4. Render con `state: :empty` → "Nessun risultato" item.
5. Render con `state: :results` + 2 results → 2 buttons cliccabili con `phx-value-name/lat/lng`.
6. `phx-click-away` wired to `on_dismiss_event` value.
7. Text input `phx-change` wired to `on_change_event` value.

**Regression** (`test/ideajar_web/live/idea_live/index_test.exs`):
- Tutti i test slice 7a-iter2 form-location passano post-refactor.

**GREEN**:
- Nuovo `lib/ideajar_web/components/location_search_input.ex` (function component).
- Update `lib/ideajar_web/live/idea_live/index.html.heex`: form fieldset Posizione usa `<LocationSearchInput>` con event names `update_location_name`/`select_location`/`dismiss_location_search`.
- LV handlers slice 7a invariati (event names preservati).

**REFACTOR**: verify Credo no issues.

**Files**: `lib/ideajar_web/components/location_search_input.ex` (new), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/components/location_search_input_test.exs` (new).
**Spec mapping**: R1, R2, R4, R5, DD1.

### Step 2: `Ideajar.Ideas.Distance.km/4` Haversine

**Complexity**: standard
**Rationale**: pure math + test boundary. Foundation per step 3.

**RED** (`test/ideajar/ideas/distance_test.exs` new):
1. `Distance.km(43.5, 13.6, 43.5, 13.6) == 0.0` (same point).
2. `Distance.km(0, 0, 0, 1)` ≈ 111.32 (±0.5) — equator E-W 1°.
3. `Distance.km(0, 0, 1, 0)` ≈ 111.32 (±0.5) — equator N-S 1°.
4. `Distance.km(90, 0, -90, 0)` ≈ 20015 (±10) — pole-to-pole.
5. `Distance.km(43.5, 13.6, 41.9, 12.5)` ≈ 200 (±10) — Sirolo↔Roma real-world.
6. `Distance.km(43.5, 13.6, 48.85, 2.35)` ≈ 1300 (±50) — Sirolo↔Parigi.
7. **Symmetry**: `Distance.km(a, b, c, d) == Distance.km(c, d, a, b)` (commutative).
8. **Antipodal correctness**: `Distance.km(0, 0, 0, 180)` ≈ 20015 km (±10) — half of Earth's circumference (π·R). Returns finite float, no raise. Pin both magnitude AND no-raise.

**GREEN**:
```elixir
defmodule Ideajar.Ideas.Distance do
  @moduledoc """
  Pure Haversine distance calculation.

  Returns the great-circle distance in kilometers between two points
  given their geographic coordinates. Used by `Ideajar.Ideas.Filter.apply_post/2`
  for in-memory distance filtering (slice 7b).
  """
  @earth_radius_km 6371.0

  @spec km(float, float, float, float) :: float
  def km(lat1, lng1, lat2, lng2) do
    lat1_rad = deg_to_rad(lat1)
    lat2_rad = deg_to_rad(lat2)
    dlat = deg_to_rad(lat2 - lat1)
    dlng = deg_to_rad(lng2 - lng1)

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) * :math.sin(dlng / 2) ** 2

    c = 2 * :math.asin(min(1.0, :math.sqrt(a)))

    @earth_radius_km * c
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180.0
end
```

**REFACTOR**: docstring complete. No issues.

**Files**: `lib/ideajar/ideas/distance.ex` (new), `test/ideajar/ideas/distance_test.exs` (new).
**Spec mapping**: DM1-DM4, O4, DD2.

### Step 3: `Filter.apply_post/2` + `apply_max_distance/2` (DD3)

**Complexity**: complex
**Rationale**: nuovo path post-query nel modulo Filter. Foundation per slice future.

**RED** (`test/ideajar/ideas/filter_test.exs` extension):
1. `Filter.apply_post(list, [])` → list invariata.
2. `Filter.apply_post(list, max_distance_km: nil)` → no-op.
3. `Filter.apply_post(list, max_distance_km: 5, ref_lat: 43.5, ref_lng: 13.6)` con 5 idee (3 con coords vicine, 1 con coords lontane, 1 con NULL coords) → solo le 3 vicine (NULL escluse).
4. `Filter.apply_post(list, max_distance_km: 1_000_000, ref_lat, ref_lng)` (index 6 mapping) → tutte le idee con coords (NULL escluse).
5. **DD5 defensive**: `Filter.apply_post(list, max_distance_km: 50, ref_lat: nil, ref_lng: 13.6)` → no-op (ref_lat nil).
6. **DD5 defensive**: `Filter.apply_post(list, max_distance_km: 50, ref_lat: 43.5, ref_lng: nil)` → no-op (ref_lng nil).
7. NULL-exclude pin: idea con `lat: nil, lng: 13.6` → escluso quando filter on.
8. NULL-exclude pin: idea con `lat: 43.5, lng: nil` → escluso quando filter on.

**GREEN**:
```elixir
defmodule Ideajar.Ideas.Filter do
  # ... existing apply/2 ...

  @spec apply_post([Idea.t()], keyword()) :: [Idea.t()]
  def apply_post(ideas, opts) when is_list(ideas) and is_list(opts) do
    apply_max_distance(ideas, opts)
  end

  defp apply_max_distance(ideas, opts) do
    max_km = Keyword.get(opts, :max_distance_km)
    ref_lat = Keyword.get(opts, :ref_lat)
    ref_lng = Keyword.get(opts, :ref_lng)

    if is_number(max_km) and is_number(ref_lat) and is_number(ref_lng) do
      Enum.filter(ideas, fn idea ->
        is_number(idea.lat) and is_number(idea.lng) and
          Ideajar.Ideas.Distance.km(idea.lat, idea.lng, ref_lat, ref_lng) <= max_km
      end)
    else
      ideas
    end
  end
end
```

**REFACTOR**: aggiungi/aggiorna `@moduledoc` su `Ideajar.Ideas.Filter` per documentare il **dual-layer contract**: `apply/2` opera sul query path (Ecto.Query) e compone clausole SQL; `apply_post/2` opera sul post-query path (lista di structs in memoria) per filtri non-SQL-friendly (es. Haversine). Docstring per `apply_post/2` spiega DD4 (NULL-exclude semantics: index 0 vs index 6 differiscono solo per NULL treatment) + DD3 trigger per estrazione modulo `PostQuery` quando 3+ clausole post-query coesistono.

**Files**: `lib/ideajar/ideas/filter.ex` (extend), `test/ideajar/ideas/filter_test.exs` (extend).
**Spec mapping**: DM5-DM8, DD3, DD4, DD5.

### Step 4: `Ideas.list_ideas/1` extension con :max_distance_km + :ref_lat + :ref_lng

**Complexity**: standard
**Rationale**: glue between query path (Filter.apply) and post-query path (Filter.apply_post).

**RED** (`test/ideajar/ideas_test.exs` extension):
1. `list_ideas([])` invariato (regression).
2. `list_ideas([max_distance_km: 50, ref_lat: 43.5, ref_lng: 13.6])` → solo ideas entro 50 km AND non-nil coords.
3. **5-way combined AND**: `list_ideas([required: [@mare_id], durations: [:weekend], max_cost: 500, max_distance_km: 50, ref_lat: 43.5, ref_lng: 13.6])` → AND tra tutte le clausole.
4. SQL emission O3 regression: `list_ideas([max_cost: 100])` SQL emesso invariato (no change al query path).
5. Order preservato: `inserted_at DESC, id DESC` post-Filter.apply_post.

**GREEN** (extend `Ideas.list_ideas/1`):
```elixir
def list_ideas(opts \\ []) when is_list(opts) do
  Keyword.keyword?(opts) || raise ...

  base_query
  |> Ideajar.Ideas.Filter.apply(opts)
  |> Repo.all()
  |> Repo.preload(...)
  |> Ideajar.Ideas.Filter.apply_post(opts)
end
```

**REFACTOR**: moduledoc + @doc su `list_ideas/1` aggiornati con nuove opts.

**Files**: `lib/ideajar/ideas.ex` (extend), `test/ideajar/ideas_test.exs` (extend).
**Spec mapping**: DM9-DM11, DD12.

### Step 5: JS hook `Geolocation` + button registration

**Complexity**: standard
**Rationale**: minimal hook (~20 LOC). Pattern parallel slice 7a leaflet_map (now removed).

**RED**:
1. `assets/js/hooks/geolocation.js` exists with `export const Geolocation` + `mounted()` + click handler that calls `navigator.geolocation.getCurrentPosition`.
2. `assets/js/app.js` imports and registers `Geolocation` hook: `assert File.read!("assets/js/app.js") =~ "Geolocation"`.
3. **No double-bind on LV update pin**: hook source contains `mounted()` (one-time bind) and does NOT register click in `updated()`. File-read pin: `refute File.read!("assets/js/hooks/geolocation.js") =~ ~r/updated\s*\(/`. Razionale: LV `updated()` fires su ogni patch del server; ri-binding `addEventListener` ad ogni update produrrebbe N listener cumulativi e N pushEvent per click.

**GREEN**:
- New `assets/js/hooks/geolocation.js`:
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
- Update `assets/js/app.js`: import + add to hooks: `hooks: { ...colocatedHooks, RovingTabindex, Geolocation }`.

**REFACTOR**: docstring spiega minimal-JS constraint + W3C error code mapping (DD7).

**Files**: `assets/js/hooks/geolocation.js` (new), `assets/js/app.js` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend with file-read pin).
**Spec mapping**: O5, DD6, DD7.

### Step 6: LV handlers `set_user_location` + `user_location_denied` + assigns

**Complexity**: standard
**Rationale**: server-side state for ref point. Handler defensive parse.

**RED** (`test/ideajar_web/live/idea_live/index_test.exs` new describe):
1. Mount: `view.assigns.user_lat == nil`, `:user_lng == nil`, `:user_location_name == nil`.
2. `set_user_location` con `%{"lat" => 43.6, "lng" => 13.5}` → 3 assigns set + `user_location_name == "La mia posizione"`.
3. `user_location_denied` con `%{"reason" => "permission_denied"}` → flash error `"Permesso di geolocalizzazione negato"`.
4. `user_location_denied` con `%{"reason" => "timeout"}` → flash `"Posizione non disponibile, riprova"`.
5. `user_location_denied` con `%{"reason" => "unavailable"}` → flash `"Posizione non disponibile, riprova"`.
6. `user_location_denied` con `%{"reason" => "unsupported"}` → flash `"Posizione non disponibile, riprova"`.
7. **Hostile uniform list (S1, 8 inputs)**: `set_user_location` con `%{"lat" => "abc"}`, `%{"lat" => 91}`, `%{"lat" => -91}`, `%{"lng" => 181}`, `%{"lng" => -181}`, `%{}` (missing keys), `%{"lat" => [], "lng" => 13.6}`, `%{"lat" => 43.5}` (missing lng) → tutti no-op.

**GREEN**:
```elixir
def handle_event("set_user_location", %{"lat" => raw_lat, "lng" => raw_lng}, socket) do
  with {:ok, lat} <- parse_coord(raw_lat, -90, 90),
       {:ok, lng} <- parse_coord(raw_lng, -180, 180) do
    {:noreply,
     socket
     |> assign(:user_lat, lat)
     |> assign(:user_lng, lng)
     |> assign(:user_location_name, "La mia posizione")
     |> reload_ideas()}
  else
    _ -> {:noreply, socket}
  end
end
def handle_event("set_user_location", _, socket), do: {:noreply, socket}

def handle_event("user_location_denied", %{"reason" => reason}, socket) do
  flash_msg =
    case reason do
      "permission_denied" -> "Permesso di geolocalizzazione negato"
      _ -> "Posizione non disponibile, riprova"
    end

  {:noreply, put_flash(socket, :error, flash_msg)}
end
def handle_event("user_location_denied", _, socket), do: {:noreply, socket}
```

Mount: add `assign(:user_lat, nil) |> assign(:user_lng, nil) |> assign(:user_location_name, nil)`.

`parse_coord/3` può essere lo stesso helper di slice 7a (già rimosso post-iter2). Ricreatelo se serve. Suggerimento: helper privato in IdeaLive.Index.

**REFACTOR**: docstring + flag DD7 mapping.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F3-F5, S1, DD6, DD7.

### Step 7: LV handlers filter search (parallel slice 7a)

**Complexity**: standard
**Rationale**: parallel pattern slice 7a, ma con `@user_*` assigns invece di `@selected_*`.

**RED**:
1. Mount: `view.assigns.user_location_search_results == []`, `:user_location_search_state == :idle`.
2. `update_user_location_name` < 3 chars → state idle, no dropdown.
3. `update_user_location_name` ≥ 3 chars + stub returns 2 results → state :results, dropdown rendered.
4. `update_user_location_name` empty results → state :empty.
5. `update_user_location_name` `:service_unavailable` → flash + state idle.
6. `select_user_location` con valid result → 3 user_* assigns set + state idle.
6a. **Swap preserva slider (DD19 swap clause)**: pre-state `user_lat/lng/name` set + `max_distance_index = 3`. `select_user_location` con un nuovo result → 3 user_* assigns aggiornati al nuovo result E `max_distance_index` rimane `3` (slider value preservato). Slider rimane enabled.
7. `dismiss_user_location_search` → state idle, user_* assigns invariati.
8. **Hostile uniform list S3**: `select_user_location` con missing keys, non-binary, out-of-range coords → no-op.
9. **Hostile uniform list S4**: `update_user_location_name` con non-binary payload → no-op.

**GREEN**: parallel a slice 7a `update_location_name`/`select_location`/`dismiss_location_search` ma assigns diversi. Riusa `Ideajar.Geocoding.search/1` (no new domain code).

NB: il `select_user_location` deve ANCHE applicare DD11 (NON resetta user_location su select; questo è un swap, non reset). Diverso da slice 7a `select_location` che era simile.

**REFACTOR**: extract helper `apply_user_search_query/2` se DRY con `apply_location_name_change/2`.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F6-F7, S3, S4.

### Step 8: Slider HEEx + `update_max_distance` + sub-block layout + clear_filters extension

**Complexity**: complex
**Rationale**: cross-cutting (template + handler + clear_filters integration + slider a11y).

**RED**:
1. Mount: render contains sub-block `<div role="group" aria-label="Filtra per distanza">` dopo Budget.
2. Sub-block contains: bottone geolocation con `phx-hook="Geolocation"`, `<LocationSearchInput>`, slider `<input type="range" min="0" max="6">`, helper texts.
3. Slider mount: `disabled` attr + `aria-disabled="true"` + opacity-50 (tailwind classes).
3a. **Full ARIA contract pin (A1)**: slider ha `aria-valuemin="0"`, `aria-valuemax="6"`, `aria-valuenow="0"`, `aria-valuetext="Disattivo"` su mount.
3b. **Touch target (A8)**: rendered HTML/CSS contiene rule per `::-webkit-slider-thumb` con `width: ≥44px; height: ≥44px;` (file-read pin su CSS file o styles inline).
4. After `set_user_location`: slider no `disabled` + `aria-disabled="false"`.
5. `update_max_distance` con `%{"value" => "3"}` → `@max_distance_index == 3`.
6. **F11**: slider index 0 + ref point set + ideas fixture with mix coords/NULL → render mostra tutte (NULL passa).
7. **F12**: slider index 1 (5km) + ref Sirolo + 5 idee (3 vicine, 1 lontana, 1 NULL) → render mostra 3 vicine, 1 lontana ESCLUSA, 1 NULL ESCLUSA.
8. **F13**: slider index 6 + ref point + ideas → render mostra tutte le ideas con coords (NULL escluse).
9. Slider `aria-valuenow` + `aria-valuetext` correlati a index.
10. **DD9 hostile uniform list**: `update_max_distance` con `%{"value" => "abc"}`, `%{"value" => "-1"}`, `%{"value" => "7"}`, `%{"value" => "3.5"}`, missing key → no-op.
11. **DD18 5-way combined AND**: render con tutti i 5 filter attivi → ideas filtrate correttamente.
12. **clear_filters extension**: con tutti 5 attivi + ref point → click `Mostra tutte` → reset all.
13. **DD13 helper text disabled state**: `Imposta un punto di riferimento per usare il filtro distanza` visible quando user_lat nil.
14. **F19** filter row sub-block order: Categorie → Durata → Budget → Distanza in DOM source order.
15. **DD14** sub-block helper text NULL-exclude visible always.

**GREEN**:
- Update `lib/ideajar_web/live/idea_live/index.ex`:
  - Mount: `assign(:max_distance_index, 0)`.
  - New module attrs `@distance_steps`, `@distance_labels` (slice 7b decisione DD4).
  - Helper `distance_max_km/1` mappa index → km.
  - Helper `distance_label/1` mappa index → string.
  - New handler `update_max_distance` con defensive parse 0..6:
    ```elixir
    def handle_event("update_max_distance", %{"value" => raw}, socket) when is_binary(raw) do
      case Integer.parse(raw) do
        {n, ""} when n >= 0 and n <= 6 ->
          {:noreply, socket |> assign(:max_distance_index, n) |> reload_ideas()}
        _ -> {:noreply, socket}
      end
    end
    def handle_event("update_max_distance", _, socket), do: {:noreply, socket}
    ```
  - `clear_filters` esteso (DD15): reset 5 filter types + ref point.
  - `derive_filter_opts/N` esteso (DD12): add `:max_distance_km` (mapped da `distance_max_km(@max_distance_index)`), `:ref_lat` (`@user_lat`), `:ref_lng` (`@user_lng`).

- Update `lib/ideajar_web/live/idea_live/index.html.heex`: aggiungi sub-block `Distanza` dopo `Budget`. Layout completo descritto sopra.

**REFACTOR**: extract helper `distance_disabled?/1`, `distance_classes/1`, `distance_label/1` per readability. **`derive_filter_opts/N` arity smell** (Design Critic Q5): se l'helper è già a `/3` (categoria/durata/budget) e con questa slice passerebbe a `/5+`, sostituire la signature da `derive_filter_opts(socket_or_assigns, ...)` a `derive_filter_opts(socket_or_assigns)` letto direttamente dagli assigns; il body fa pattern-match sull'intera struct. Documentato come trigger di refactor da emergere già qui — se la chiamata si presenta in `reload_ideas/1` solo, refactor è puro local. Trigger per modulo dedicato `IdeaLive.FilterOpts`: 6+ campi.

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `lib/ideajar_web/live/idea_live/index.html.heex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F2, F8-F19, A1-A7, DD4, DD8, DD9, DD12, DD13, DD14, DD15.

### Step 9: `remove_user_location` + `remove_distance_filter` + integration tests

**Complexity**: standard
**Rationale**: 2 reset handlers + final regression pin.

**RED**:
1. **F14 remove_user_location**: with all 4 set → click `Rimuovi punto di riferimento` → 3 user_* nil + slider index 0 (cascade DD19). Slider disabled.
2. **F15 remove_distance_filter**: with ref + slider 3 → click `Rimuovi filtro distanza` → slider 0, user_* unchanged.
3. **F17 refresh resets `@user_*`**: re-mount → all nil.
4. **F18 save success NON resetta `@user_*`**: ref + slider 3 set → submit valid idea → after save: ref + slider preserved.
5. **F19 filter survives form submit**: ref + slider 50km set → submit idea con coords → idea creata, render aggiorna con filter applicato (idea visible se nel raggio, hidden altrimenti).
6. **F19 NULL idea hidden when filter on**: ref + slider 50km + submit idea senza coords → idea creata, NON visible (NULL excluded).
7. Bottoni `Rimuovi punto di riferimento` e `Rimuovi filtro distanza` mostrati condizionalmente correttamente.

**GREEN**:
```elixir
def handle_event("remove_user_location", _, socket) do
  {:noreply,
   socket
   |> assign(:user_lat, nil)
   |> assign(:user_lng, nil)
   |> assign(:user_location_name, nil)
   |> reset_distance_filter()  # cascade DD19, helper DD10
   |> reload_ideas()}
end

def handle_event("remove_distance_filter", _, socket) do
  {:noreply, socket |> reset_distance_filter() |> reload_ideas()}
end

defp reset_distance_filter(socket), do: assign(socket, :max_distance_index, 0)
```

**REFACTOR**: ensure `reset_distance_filter/1` helper used uniformly (DD10).

**Files**: `lib/ideajar_web/live/idea_live/index.ex` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend).
**Spec mapping**: F14-F19, DD10, DD11, DD19.

### Step 10: Out-of-scope guard + docs sync (D1-D5) + plan flip

**Complexity**: standard

**RED**:
1. **D1**: new `describe "docs/conventions.md — slice 7b UI copy"` con ~18 stringhe canoniche.
2. **D3**: `describe "CONTEXT.md — slice 7b distanza NULL-exclude"` asserisce che il `## Decisione su filtri non applicabili` documenta `distanza` nel pattern uniforme.
3. **D5**: out-of-scope guard regression: `"Cerca punto di partenza"` deve essere presente nel render (nuovo positive assertion); `"Cerca"` da solo NON match (slice 8 ancora out-of-scope).

**GREEN**:
- `docs/conventions.md`: append `Stringhe aggiunte in slice 7b (distance filter)` table.
- `CONTEXT.md`:
  - Update `## Decisione su filtri non applicabili`: includi `distanza` nel pattern uniforme.
  - Update riga 80 (filtri Distanza) con marker (slice 7b).
- `test/ideajar/docs_test.exs`: nuove `describe`.
- `test/ideajar_web/live/idea_live/index_test.exs`: positive `Cerca punto di partenza` pin.
- Plan flip: `**Status**: approved` → `**Status**: implemented`.

**Files**: `docs/conventions.md` (extend), `CONTEXT.md` (update), `test/ideajar/docs_test.exs` (extend), `test/ideajar_web/live/idea_live/index_test.exs` (extend), `plans/slice-7b-distance-filter.md` (status flip).
**Spec mapping**: D1-D5.

## Complexity Classification

| Step | Complessità | Motivazione |
|------|-------------|-------------|
| 1 | standard | Refactor puro pre-feature |
| 2 | standard | Pure math + 5 boundary tests |
| 3 | **complex** | Nuovo path post-query, foundation per slice future |
| 4 | standard | Pipeline glue + regression |
| 5 | standard | Hook minimale + asset registration |
| 6 | standard | Handler + assigns + hostile uniform |
| 7 | standard | Parallel slice 7a search pattern |
| 8 | **complex** | Cross-cutting template + handler + clear_filters + a11y |
| 9 | standard | Reset handlers + integration regression |
| 10 | standard | Docs sync |

## Pre-PR Quality Gate

- [ ] `mix test --include migration` passa.
- [ ] `mix format --check-formatted` exit code 0.
- [ ] `mix credo` passa.
- [ ] `mix deps.audit` passa.
- [ ] `mix compile --warnings-as-errors` passa.
- [ ] `/code-review` su file toccati passa.
- [ ] **F1 traceability**: ogni `Scenario:` Gherkin ha almeno un test.
- [ ] **V1**: 4 screenshot in `docs/screenshots/slice-7b/`.
- [ ] **V1a**: Lighthouse a11y mediana ≥95.
- [ ] **V1b**: keyboard-only walkthrough.
- [ ] **V2**: manual geolocation grant + deny.
- [ ] CI verde sul push.

## Risks & Open Questions

- **R7b-1 — `apply_post/2` rule of 3 (DD3 trigger)**: 1 clausola post-query oggi. Trigger per modulo dedicato `Ideajar.Ideas.Filter.PostQuery`: 3+ clausole post-query.
- **R7b-2 — In-memory haversine performance**: O(N) per query. Acceptable a 100 idee. Trigger per spatial index (es. SQLite RTree extension): 1000+ idee.
- **R7b-3 — Slider phx-debounce 200ms vs throttle**: drag rapido firea ~5 events/sec. Trigger per `phx-throttle="100"` invece: utenti percepiscono lag visivo.
- **R7b-4 — `LocationSearchInput` attr surface (DD16)**: 7+ attrs ora. Trigger per refactor (callback module pattern): 10+ attrs OR 3+ caller modules.
- **R7b-5 — Geolocation hook su `<button>` element**: pattern non ortodosso ma valido. Trigger per hook su separate `<div>` wrapper: warning Phoenix LV future.
- **R7b-6 — `@user_*` LV-session only**: refresh = reset. UX trade-off: utente deve re-grantare geolocation ad ogni session. Trigger per localStorage: feedback user-real-use.
- **R7b-7 — `oltre 1000 km` index 6 mapping**: differs from "no filter" only in NULL treatment. Documento esplicitamente. Trigger per UX rivisitazione: utenti confusi.
- **R7b-8 — gettext deferral (slice 4 R6 carry-over)**: slice 7b aggiunge ~18 stringhe. Cumulative ~85. Trigger residuo (utente non-IT) non scattato.
- **R7b-9 — Browser geolocation HTTPS requirement**: navigator.geolocation richiede HTTPS in production (Chrome 50+). Localhost OK. Su Gigalixir HTTPS è default. Documentato.
- **R7b-10 — Geolocation timeout default**: navigator.geolocation default timeout = ∞ (never times out). Hook può aggiungere `{ timeout: 10000 }` option. Decisione: NO timeout esplicito (il browser gestisce). Trigger per timeout custom: utenti lamentano hanging.

## Plan Review Summary

Quattro plan-review personas dispatched in parallel (Acceptance / Design / UX / Strategic). Verdetti finali post-iter1 fix:

### Acceptance Test Critic — `approve` (post-fix)
**Blocker fissati nella revisione corrente**:
1. Spec JS snippet error mapping (line 502 area) era 2-branch (`code 1 → "permission_denied" : "timeout"`) collassando code 2/3. Ora 4-branch coerente con plan step 5 GREEN (`permission_denied`/`unavailable`/`timeout`/`unsupported`).
2. `"Ricerca non disponibile, riprova"` mancava nelle copy table (spec + plan). Ora presente.
3. ARIA full contract (`aria-valuemin="0"`, `aria-valuemax="6"`) non era pinnato in alcun RED. Aggiunto scenario Gherkin "Slider exposes the full ARIA contract on mount" + step 8 RED #3a.
4. Step 7 RED #6a aggiunto: `select_user_location` swap preserva `@max_distance_index` + slider rimane enabled (DD19 swap clause).
5. Step 2 RED #8 antipodal aveva solo "no raise"; ora pin di magnitudine `≈ 20015 (±10)` + finite-float.

**Warnings residui** (acceptable per slice 7b, da rivedere in prossime slice):
- `Distance.km/4` non testa coordinate non-numeriche (validazione upstream già garantita da S1/S2).
- `apply_post/2` non pin esplicitamente l'ordine dell'output (slice 4-7a già pin l'order in `list_ideas/1` regression).

### Design & Architecture Critic — `approve` (con riserve documentate)
**Q1 — `apply/2` vs `apply_post/2` dual contract**: la coabitazione di query-path e post-query-path nello stesso modulo è soluzione pragmatica per slice 7b (1 clausola post). Trigger per estrazione `Ideajar.Ideas.Filter.PostQuery` modulo separato: 3+ clausole post. Documentato in DD3 + step 3 REFACTOR ora include moduledoc dual-layer esplicito.

**Q4 — `phx-hook` su `<button>`**: pattern valido (DD17). Aggiunto step 5 RED #3 file-read pin che verifica assenza di `updated()` per evitare double-bind di `addEventListener`.

**Q5 — `derive_filter_opts/N` arity smell**: aggiunto step 8 REFACTOR esplicito che indirizza il refactor (signature da `/N` a `/1` con pattern-match su socket).

**B warning — `LocationSearchInput` attr surface (7+ attrs)**: tracciato in DD16 con trigger esplicito (10+ attrs OR 3+ caller modules). Slice 7b sotto entrambe le soglie.

### UX Critic — `approve` (post-fix)
**Required fix applicato**:
- `"Off"` → `"Disattivo"` in `@distance_labels` index 0 + spec/plan copy table + nuovo scenario Gherkin "Slider exposes the full ARIA contract on mount" allineato.

**Touch target / layout fix applicato**:
- Nuovo A8 acceptance criterion: thumb ≥44×44 px via CSS custom (`::-webkit-slider-thumb` + `::-moz-range-thumb`), track ≥8 px.
- Nuovo A9 acceptance criterion: layout responsive del sub-block (geolocation button + search input stacked su mobile, affiancati su `≥sm`).
- Step 8 RED #3b file-read pin verifica la rule CSS thumb.

**Observation — IT canonicalità**: tutte le stringhe della copy table sono IT, no anglicismi residui.

### Strategic Critic — `approve`
**Flag actionable**: scope di slice 7b è coerente con CONTEXT.md priorità "filtri Distanza" (riga 80). Foundation slice 7a già rilasciata. ROI atteso (UX value vs effort): high — distanza è il filtro più richiesto in setting "couple sharing ideas" geographically dispersed.

**Owner-side optionality non bloccante**: l'opzione di anticipare slice 9 (PWA / offline) prima di 7b/8 è perseguibile, ma slice 7b ha already entrenched dependencies (slice 7a schema) e non è bloccante per slice 9. Raccomandazione: procedere con slice 7b come pianificato.

### Iter 2 — convergence
Tutti i 4 reviewers post-fix tornano `approve` (no needs-revision residui). Plan flip da `draft` → `approved` autorizzato.
