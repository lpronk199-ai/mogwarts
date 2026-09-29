# Mogwarts-geluidspakket voor Roblox

47 filmische geluiden, gemaakt voor de scripts in `mogwarts3.rbxl`. Ze klinken bij spreuken (Q, E, R, Z, X),
de dash, affiniteiten, de grimoire, codes, de interface, de magische deuren, de spookzones en het vallen van de nacht.
Veelgebruikte geluiden hebben 2 tot 4 varianten en een kleine toonhoogtevariatie, zodat niets steeds hetzelfde klinkt.

Beluisteren kan in het soundboard (de categorieën die met "Mogwarts:" beginnen).

## Wat zit hier

| Pad | Wat |
| --- | --- |
| `audio/*.ogg` | De 8 bestanden die je uploadt: 3 "sheets" met alle korte geluiden en 5 loops |
| `MogwartsSounds.lua` | ModuleScript die weet waar elk geluid in welk bestand zit, en ze afspeelt |
| `scripts/*.lua` | Je eigen scripts uit `mogwarts3.rbxl`, aangevuld met de geluiden |

Roblox beperkt hoeveel audiobestanden je per maand mag uploaden. Daarom staan alle korte geluiden samen in drie
lange bestanden, en speelt de module steeds alleen het juiste stukje af. Zo heb je aan 8 uploads genoeg.

## Stap 1: de 8 bestanden uploaden

1. Open je place in Roblox Studio.
2. Ga naar **View → Asset Manager** en klik op **Bulk Import**.
3. Kies alle 8 bestanden uit `roblox/audio/`.
4. Wacht tot Roblox ze heeft goedgekeurd. Dat duurt meestal een paar minuten.
5. Klik in de Asset Manager met rechts op elk bestand en kies **Copy Asset ID**.

Uploaden via de Creator Hub (Creations → Audio) kan ook.

## Stap 2: de module toevoegen

1. Ga in de Explorer naar **ReplicatedStorage → WizardShared**.
2. Voeg een **ModuleScript** toe en noem het precies `MogwartsSounds`.
3. Plak de inhoud van `MogwartsSounds.lua` erin.
4. Vul bovenaan bij `Sounds.ASSET_IDS` de ids uit stap 1 in, bijvoorbeeld:

```lua
Sounds.ASSET_IDS = {
	combat = 123456789,        -- sheet_combat.ogg
	interface = 123456790,     -- sheet_interface.ogg
	...
```

## Stap 3: de scripts vervangen

Open elk script, selecteer alles (Ctrl+A) en plak de nieuwe versie uit `scripts/`:

| Bestand | Script in Studio |
| --- | --- |
| `CombatServer.server.lua` | ServerScriptService → WizardServer → CombatServer |
| `DoorSystem.server.lua` | ServerScriptService → WizardServer → DoorSystem |
| `SpellFXClient.client.lua` | StarterPlayer → StarterPlayerScripts → SpellFXClient |
| `Ambience.client.lua` | StarterPlayer → StarterPlayerScripts → Ambience |
| `HUDController.client.lua` | StarterGui → WizardHUD → HUDController |
| `UIStyle.lua` | ReplicatedStorage → WizardShared → UIStyle |

Deze versies zijn gemaakt van `mogwarts3.rbxl` (29 september). Heb je die scripts daarna nog aangepast, plak
ze dan niet over je nieuwe versie heen. Zoek in de bestanden in plaats daarvan naar `[MogwartsSounds]`. Elke
regel met dat label is een toevoeging, en die kun je met de hand overnemen.

Zolang er bij `ASSET_IDS` nog een `0` staat, blijven de oude geluiden gewoon werken. Je kunt dus stap voor stap overstappen.

## Wat je hoort

| Moment | Geluid |
| --- | --- |
| Bolt (Q), Barrage (X) | `cast` + een affiniteitslaag (vuur, ijs, wind, storm, natuur, duister of licht) |
| Bolt raakt | `impact`, bij Crystal ook `crystal_shatter` |
| Blast (E) | `blast` + `blast_whoosh` |
| Shield (R) | `shield_up`; een geblokkeerde spreuk geeft `shield_block` |
| Charge (Z vasthouden) | `charge_loop`, dat hoger gaat klinken hoe verder je laadt; `charge_full` bij volle lading; `charge_release` bij loslaten |
| Dash (C) | `dash` |
| Mythic-affiniteit | `mythic_cast` |
| Toverstok pakken of wegstoppen | `duel_draw` / `duel_holster` |
| Ember/Solar-brand, Frost-vertraging, lifesteal | `burn_tick`, `frost_slow`, `lifesteal` |
| Dummy KO | `knockout` |
| Doodgaan / spawnen | `defeat` / `respawn` |
| Grimoire | `reroll` bij klikken, daarna `reveal_common` t/m `reveal_mythic` per zeldzaamheid |
| Code inwisselen | `code_redeem`, of `ui_denied` als het niet lukt |
| Knoppen | `ui_click`, `ui_hover`, `ui_open` |
| Magische deuren | `magic_door_open` / `magic_door_close` |
| Deadwood Hollow, Mourning Shore, Moonpool | eigen sfeerloops die aanzwellen als je in de buurt komt |
| Het wordt nacht | de klok van het kasteel slaat 3 keer (`BELLS` in Ambience) |

## Echte filmgeluiden

Deze geluiden zijn uit rekenwerk opgebouwd (synthese). Ze klinken filmisch, maar niet zo echt als opnames.
Voor echte filmkwaliteit zijn er twee routes. Allebei werken ze met dezelfde module en dezelfde scripts.

**1. Roblox Creator Store (gratis, geen uploads nodig).** Roblox heeft duizenden professionele
geluidseffecten die je gratis in je game mag gebruiken.

1. Open in Studio de **Toolbox**, kies **Creator Store → Audio** en zet het filter op **Sound Effects**.
2. Zoek bijvoorbeeld op *magic spell*, *spell impact*, *whoosh*, *cinematic hit*, *shield*, *magic chime*,
   *book page* of *castle door*.
3. Luister, en klik met rechts op een geluid dat je mooi vindt → **Copy Asset ID**.
4. Zet de id in `Sounds.LIBRARY` in `MogwartsSounds`, onder de naam van het geluid dat je wilt vervangen:

```lua
Sounds.LIBRARY = {
	cast = { 1234567890, 1234567891 },   -- twee opnames: de game kiest er telkens één
	impact = { 1234567892 },
}
```

Je kunt zo één geluid tegelijk vervangen. Wat niet in `LIBRARY` staat, komt gewoon uit het pakket.

**2. ElevenLabs (AI, alle prompts in één keer).** Alle prompts staan klaar in `sfx/prompts.json`, ook de varianten.
Met een ElevenLabs-account draai je op je eigen computer:

```bash
export ELEVENLABS_API_KEY=...
python3 sfx/generate.py --force game_combat game_affinity game_rewards game_ui game_world
python3 sfx/roblox_export.py --source files
```

Daarna upload je de 8 nieuwe bestanden uit `roblox/audio/` en plak je de nieuwe `MogwartsSounds.lua` in Studio.

## Aanpassen

- **Volume, toonhoogte en afstand per geluid:** in `MogwartsSounds.lua` staan bij `Sounds.LIST` per geluid
  `volume` (0 tot 1), `pitch` (hoeveel de toonhoogte willekeurig varieert) en `range` (tot hoeveel studs je
  het hoort). De volumeschuifjes in je Settings-menu blijven gewoon werken.
- **Aantal klokslagen en de zones:** bovenaan de toevoeging in `Ambience.client.lua`.
- **Ergens anders een geluid:** `Sounds.play("naam", part)` op een part, `Sounds.play("naam", positie)` op een
  punt, of `Sounds.play("naam")` voor een geluid zonder positie.

## Opnieuw maken

```bash
python3 sfx/synth.py --force game_combat game_affinity game_rewards game_ui game_world
python3 sfx/roblox_export.py
```

Upload daarna de gewijzigde bestanden opnieuw. Plak ook de nieuwe `MogwartsSounds.lua` in Studio, want
de tijden in de sheets kunnen verschoven zijn. Zet je ids er dan weer in.

## Goed om te weten

- Ik heb dit niet in Roblox zelf kunnen testen. De Luau-code compileert en de module is getest met
  nagebootste Roblox-onderdelen, maar Studio is de echte test.
- De module speelt een stukje van een sheet af met `PlaybackRegion`. Hoor je ergens een verkeerd of
  afgekapt geluid, laat het me weten. Er zit een reservemethode in, maar die is minder precies.
