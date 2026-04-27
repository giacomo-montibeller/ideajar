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

```
ideas
  id
  title              string, required
  description        text, optional
  url                string, optional
  lat, lng           float, optional
  location_name      string, optional
  duration           enum [few_hours, half_day, full_day, weekend, multi_day]
  estimated_cost     integer, optional, in € per coppia
  inserted_at, updated_at

categories            seed da codice, non CRUD
  id, name, icon, color, sort_order

ideas_categories      many-to-many
```

Nota: `created_by` **non** presente — irrilevante per due utenti che condividono lo spazio.

## Categorie (fisse, gestite via release)
Proposta iniziale di seed:

- 🌊 Mare
- 🏔️ Montagna
- 🏞️ Natura
- 🏛️ Cultura
- 🍽️ Gastronomia
- 🎭 Spettacolo
- 🎢 Avventura
- ✈️ Viaggio
- 🏠 Casa
- 🛍️ Shopping

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

### Decisione UX aperta
Quando un filtro non è applicabile a un'idea (es. budget filtrato a 50€ ma idea senza `estimated_cost`), la proposta è: **l'idea resta visibile**. Il filtro esclude solo ciò che certamente non rientra, evitando di nascondere idee buttate giù in fretta senza tutti i dettagli.

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
