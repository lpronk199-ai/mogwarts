# Geluidseffecten

Alle geluidsprompts voor Mogwarts staan in [`prompts.json`](prompts.json), gegroepeerd per categorie:
voetstappen, vuur, ijs, gif, bliksem, duistere magie, licht, schild/wind/aarde en speciale effecten, plus
filmische effecten (braams, risers, sub drops, trommels), sfeerloops, wezens en spelmomenten.

Achter elke prompt wordt automatisch deze toevoeging geplakt:

```
, fantasy video game sound effect, high quality, clean, no music
```

Per geluid staat er een `duration` (in seconden) of `"loop": true` (naadloze loop). Die worden als
`duration_seconds` en `loop` naar de API gestuurd in plaats van in de tekst te staan.

## Gesynthetiseerde versies (zit al in de repo)

Alle 77 geluiden staan al als MP3 in `assets/sfx/`. Ze zijn procedureel gemaakt met
[`synth.py`](synth.py): elk geluid heeft daar een eigen recept van ruis, oscillatoren, filters en galm.
Er is geen API of sleutel voor nodig:

```bash
pip install numpy scipy lameenc
python3 sfx/synth.py --force          # alles opnieuw renderen
python3 sfx/synth.py --force fire     # alleen een categorie of een los geluid
```

Elk geluid gaat aan het eind door dezelfde klankkleuring (`master` in `synth.py`): +6 dB laag onder
140 Hz, -6 dB hoog boven 4,5 kHz en niets boven 11 kHz, zodat niets schel klinkt.

Het resultaat is elke keer hetzelfde. Wil je een geluid anders, pas dan het recept (de functie met
dezelfde naam als het id) aan en render opnieuw. Loops zijn naadloos gemaakt, maar MP3 voegt bij het
coderen een paar milliseconden stilte toe. In sommige spelers geeft dat een klein tikje op het
loop-punt. Kies bij problemen OGG of WAV voor de loops.

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
Omdat de gesynthetiseerde versies er al staan, gebruik je de eerste keer `--force` om ze te vervangen.
Niet tevreden over een geluid? Pas de prompt in `prompts.json` aan en draai het script met `--force <id>`.

## Een geluid toevoegen

Voeg een regel toe aan de juiste categorie in `prompts.json`:

```json
{ "id": "owl_hoot", "prompt": "Owl hooting softly at night in a castle tower", "duration": 2 }
```

Gebruik `"loop": true` in plaats van `duration` voor achtergrondgeluiden die moeten doorlopen.
`synth.py` meldt nieuwe ids zonder recept; die kun je met ElevenLabs maken of een eigen recept geven.
