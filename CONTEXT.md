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
- **SQLite via Ecto** (file singolo, backup = copia file)
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
5. **Ricerca testuale** — su `title` + `description`

## Decisione su filtri non applicabili

Per i filtri **durata** (slice 5), **budget** (slice 6) e **distanza** (slice 7b): un'idea con valore NULL viene **esclusa** quando il rispettivo filtro è attivo. Pattern uniforme. Razionale: chi filtra sta restringendo attivamente; un'idea senza valore non è "sicuramente non match" ma "non confermata match" → fuori.

Per il filtro distanza la regola si applica così: index slider 0 = filtro inattivo, NULL passa; index 1-6 = filtro attivo, idee con `lat: nil` o `lng: nil` escluse. Index 6 ("oltre 1000 km") differisce da index 0 SOLO per il NULL treatment.

Per filtri futuri (`text search` slice 8) la decisione sarà rivalutata caso per caso, ma il default è NULL-exclude.

## Punti di forza dell'approccio LiveView per questo caso d'uso
- I filtri (categoria × durata × costo × distanza × testo) si compongono server-side sulla stessa query Ecto.
- Aggiornamento UI senza scrivere JS lato client.
- Pochissimo codice complessivo.

## Caveat noti
- **Dipendenza da WebSocket**: su connessioni mobili instabili può presentare micro-lag/riconnessioni. Accettato per questo caso d'uso.

## Prossimi passi
1. Inizializzare progetto Phoenix
2. Definire schema + migrations + seed categorie
3. Primo LiveView con lista idee + filtri base
4. Form aggiunta idea (titolo, categorie, durata, costo, descrizione, link)
5. Integrazione mappa (Leaflet) per selezione posizione
6. Geolocation hook + filtro distanza
7. PWA manifest + service worker
8. Deploy su Gigalixir
