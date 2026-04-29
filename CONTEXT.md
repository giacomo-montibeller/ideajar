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

Stato attuale (slice 2 + 3 implementate):

```
ideas
  id
  title              string, required, max 200, trimmed
  description        text, optional, no length cap
  url                text, optional, max 2000, trimmed, http(s):// only
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

Slice future estenderanno `ideas` con `lat, lng, location_name` (slice 6),
`duration` enum (slice 5), `estimated_cost` (slice 5).

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
4. **Distanza max da me** — slider: 5 / 25 / 50 / 200 / 500 / 1000+ km
   - Richiede geolocation del browser (opt-in, bottone "📍 usa la mia posizione")
   - LiveView hook lato browser per inviare coordinate al server
   - Calcolo Haversine in Elixir (con poche centinaia di idee è istantaneo)
5. **Ricerca testuale** — su `title` + `description`

## Decisione su filtri non applicabili

Per il filtro **durata** (slice 5): un'idea con `duration: nil` viene **esclusa** quando ≥1 chip durata è on. Razionale: chi filtra per durata sta restringendo attivamente; un'idea senza durata stimata non è "sicuramente non weekend" ma "non confermata weekend" → fuori dal match.

Per filtri futuri (`estimated_cost` slice 6, `distanza` slice 7) la decisione sarà rivalutata caso per caso nello spec della slice corrispondente.

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
