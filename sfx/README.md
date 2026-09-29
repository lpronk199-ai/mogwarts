# Geluidseffecten

Alle geluidsprompts voor Mogwarts staan in [`prompts.json`](prompts.json), gegroepeerd per categorie
(voetstappen, vuur, ijs, gif, bliksem, duistere magie, licht, schild/wind/aarde, speciale effecten).

Achter elke prompt wordt automatisch deze toevoeging geplakt:

```
, fantasy video game sound effect, high quality, clean, no music
```

Per geluid staat er een `duration` (in seconden) of `"loop": true` (naadloze loop). Die worden als
`duration_seconds` en `loop` naar de API gestuurd in plaats van in de tekst te staan.

## Genereren met ElevenLabs

```bash
export ELEVENLABS_API_KEY=...        # https://elevenlabs.io/app/settings/api-keys
python3 sfx/generate.py              # alles wat nog ontbreekt
```

De bestanden komen in `assets/sfx/<categorie>/<id>.mp3`, bijvoorbeeld `assets/sfx/fire/fire_cast.mp3`.

| Commando | Wat het doet |
| --- | --- |
| `python3 sfx/generate.py --list` | toont alle ids, met hun lengte of loop |
| `python3 sfx/generate.py fire ice_cast` | alleen categorie `fire` en het geluid `ice_cast` |
| `python3 sfx/generate.py --force heal` | `heal` opnieuw genereren, ook als het bestand al bestaat |
| `python3 sfx/generate.py --influence 0.8` | houdt zich strakker aan de prompt (0–1, standaard 0.5) |
| `python3 sfx/generate.py --dry-run` | laat zien wat er verstuurd zou worden, zonder API-calls |

Bestanden die al bestaan worden overgeslagen, dus een onderbroken run kun je gewoon opnieuw starten.
Niet tevreden over een geluid? Pas de prompt in `prompts.json` aan en draai het script met `--force <id>`.

## Een geluid toevoegen

Voeg een regel toe aan de juiste categorie in `prompts.json`:

```json
{ "id": "owl_hoot", "prompt": "Owl hooting softly at night in a castle tower", "duration": 2 }
```

Gebruik `"loop": true` in plaats van `duration` voor achtergrondgeluiden die moeten doorlopen.
