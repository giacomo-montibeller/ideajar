# ideajar — contesto di progetto

## Obiettivo
Webapp per raccogliere idee di attività nel tempo libero (passeggiata al lago, giornata al mare, museo, weekend all'estero, …) filtrabili in modo da aiutare persone con molte idee e scarsa capacità decisionale a ridurre lo scope delle opzioni disponibili.

## Utenti e modello d'uso
- Utenza: **una coppia** che condivide uno spazio comune di idee, ognuno dal proprio dispositivo.
- **Non** è un servizio pubblico.
- **Nessun login / account**: accesso tramite URL con slug segreto condiviso (pattern "shared workspace URL"), salvato come PWA sull'home screen.
- **Uso primario da telefono**.
- **Offline non richiesto** — l'app può richiedere connessione.
- Installabile come **PWA** sull'home screen (manifest + service worker minimo solo per installabilità, niente cache offline).

## Stack tecnologico
- **Phoenix 1.7+ con LiveView**
- **Postgres 16 via Ecto** (slice 11a — pre-launch migration da SQLite per supportare il deploy Gigalixir slice 11b. Local dev via `docker compose up -d`)
- **Leaflet.js + tile OpenStreetMap** per la mappa (gratuito, niente API key)
- **Tailwind CSS** (incluso in Phoenix)
- **PWA**: `manifest.json` + service worker minimo

## Hosting
- **Gigalixir free tier** (single-instance, limiti di RAM accettabili per questa scala).

## Modello dati

Stato attuale (slice 2-7a implementate):

```
ideas
  id
  title              string, required, max 200, trimmed
  description        text, optional, no length cap
  url                text, optional, max 2000, trimmed, http(s):// only
  duration           enum atom, optional (slice 5)
                     [poche_ore, mezza_giornata, giornata, weekend, piu_giorni]
  estimated_cost     integer, optional (slice 6)
                     bucket whitelist [0, 20, 50, 100, 200, 500, 1000]
  location_name      string, optional, max 200, trimmed (slice 7a)
  lat                float, optional, range [-90, 90] (slice 7a)
  lng                float, optional, range [-180, 180] (slice 7a)
  inserted_at, updated_at

categories            seed da codice, non CRUD
  id
  name               string, required, UNIQUE
  display_order      integer, required, UNIQUE (1..N)
  inserted_at, updated_at

idea_categories       many-to-many (composite PK)
  idea_id            FK ideas, ON DELETE CASCADE
  category_id        FK categories, ON DELETE RESTRICT
```

Slice 7a ha esteso `ideas` con `location_name, lat, lng`. Slice 7b aggiungerà il filtro distanza Haversine (geolocation hook + slider) sopra questi campi.

Nota: `created_by` **non** presente — irrilevante per due utenti che condividono lo spazio.

## Categorie (fisse, gestite via release)

Seed shipped in slice 3 (8 voci, ordinate per `display_order`):

| order | name        |
|-------|-------------|
| 1     | passeggiata |
| 2     | mare        |
| 3     | museo       |
| 4     | ristorante  |
| 5     | sport       |
| 6     | cultura     |
| 7     | cinema      |
| 8     | viaggio     |

Modificabili tramite seed/migration in fase di rilascio.

## Filtri (tutti opzionali e componibili)

1. **Categorie** — chip multi-select
2. **Durata** — chip: poche ore / mezza giornata / giornata / weekend / più giorni
3. **Budget max** — slider con step: 0, 20, 50, 100, 200, 500, 1000+ €
4. **Distanza max da me** (slice 7b — implementato) — slider HTML5 7 step (off / 5 / 25 / 50 / 200 / 500 / oltre 1000 km)
   - Punto di riferimento via geolocation (bottone "📍 Usa la mia posizione") OPPURE ricerca testuale (Nominatim)
   - LiveView hook `Geolocation` (~30 LOC) per inviare coordinate al server
   - Calcolo Haversine in Elixir nel modulo `Ideajar.Ideas.Distance.km/4` (con poche centinaia di idee è istantaneo)
   - Filtro implementato come post-query in `Ideajar.Ideas.Filter.apply_post/2` (SQLite no Haversine native senza estensioni math)
5. **Ricerca testuale** (slice 8 — implementato) — su `title` + `description`
   - SQLite `LIKE %q%` case-insensitive con `LOWER()` su entrambi i lati
   - Wildcards `%`, `_`, `\` in input escapate a literal characters
   - Min query 3 chars (parallel slice 7a/7b)
   - phx-debounce 300ms (live filtering)

## Decisione su filtri non applicabili

Per i filtri **durata** (slice 5), **budget** (slice 6) e **distanza** (slice 7b): un'idea con valore NULL viene **esclusa** quando il rispettivo filtro è attivo. Pattern uniforme. Razionale: chi filtra sta restringendo attivamente; un'idea senza valore non è "sicuramente non match" ma "non confermata match" → fuori.

Per il filtro distanza la regola si applica così: index slider 0 = filtro inattivo, NULL passa; index 1-6 = filtro attivo, idee con `lat: nil` o `lng: nil` escluse. Index 6 ("oltre 1000 km") differisce da index 0 SOLO per il NULL treatment.

**Eccezione documentata — filtro testo (slice 8)**: per la ricerca testuale la semantica `OR` naturale prevale (`title LIKE q OR description LIKE q`). Idee con `description = nil` ma `title` matchante PASSANO. Razionale: il text filter è "trova le idee che contengono X"; una description NULL non contribuisce al match ma non penalizza l'idea (a differenza di durata/budget/distanza dove NULL = "informazione mancante = non confermo match"). Il NULL-exclude verrebbe applicato esplicitamente solo se il sistema decidesse di richiedere description per ogni idea — non è il caso.

## Punti di forza dell'approccio LiveView per questo caso d'uso
- I filtri (categoria × durata × costo × distanza × testo) si compongono server-side sulla stessa query Ecto.
- Aggiornamento UI senza scrivere JS lato client.
- Pochissimo codice complessivo.

## Caveat noti
- **Dipendenza da WebSocket**: su connessioni mobili instabili può presentare micro-lag/riconnessioni. Accettato per questo caso d'uso.

## Prossimi passi
Slice 1-8 implementati e shippati su `main` (auth, schema, list, filter chip categoria, durata, budget, location, distance filter, text search). Slice 9 inserito post slice 8: budget chip → slider conversion (UX uniformity con slice 7b distance slider, no semantic change).

Roadmap residuo (post slice 11a):
1. **Slice 11b — Deploy su Gigalixir**: production deploy via Gigalixir + Postgres addon, real-user feedback unblock. È anche il prerequisito per validare i gate manuali V1/V2 di slice 10 (Lighthouse PWA audit + install prompt manuali richiedono HTTPS).

Slice 11a (SQLite → Postgres migration) implementato: adapter swap, migration history collassata in 1 initial_schema + seed_categories, docker-compose.yml committato per Postgres locale, CI Postgres service container.

Slice 10 (PWA installability) implementato: manifest.json + sw.js (D2 strategy: cache static-only) + 2 PNG maskable + 3 root layout tags + SW registration in app.js.

I primi 8 step della roadmap originale sono stati completati. Slice 9 è un refactor UX inserito tra slice 8 (text search) e PWA per mantenere coerenza pattern slider tra distance (slice 7b) e budget. Slice 9 NON aggiunge feature: chip budget eliminati, slider HTML5 introdotto in filter + form, semantica `max_cost <= X` invariata.
