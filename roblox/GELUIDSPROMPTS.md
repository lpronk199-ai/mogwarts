# Geluidsprompts voor het Mogwarts-gamepakket

Plak deze prompts in een AI-geluidsgenerator, bijvoorbeeld ElevenLabs Sound Effects. De zin in het eerste blok
hoort achter elke prompt. Geluiden onder "Maak meerdere versies" maak je een paar keer: elke keer krijg je een
iets andere versie, zodat het in de game niet steeds hetzelfde klinkt. Bij "seamless loop" zet je in de
generator de loop-optie aan.

```
, cinematic fantasy film sound effect, high quality, clean, no music
```

🪄 Gevecht

```
Wand spell cast: sharp magical crack, a burst of fizzing sparks and a rush of air with a deep punch, like a wizard duel in a film, 0.6 seconds
Magic spell hitting a target: explosive crack, a shower of sparks and a deep punchy thud, 0.9 seconds
Magic shockwave blast: huge deep boom, a rushing ring of air and stone debris falling, echoing in a castle hall, 2 seconds
Powerful air pressure wave whooshing outward from a magic explosion, deep and fast, 1 second
Charging a spell: deep humming magical energy with a singing bowl tone, fizzing sparks and swirling air, seamless loop
Spell fully charged: bright shimmering bell tree glissando over a deep swelling hum, 0.8 seconds
Releasing a fully charged spell: loud magical crack, deep boom and a fast whoosh with a spray of sparks, 1.2 seconds
Protective magic shield raised: rising whoosh into a deep singing bowl hum and shimmering bells, glowing, 1.5 seconds
Spell deflected by a magic shield: deep resonant bell-like bass impact with a rippling energy wobble, 0.8 seconds
Magical dash: fast twisting whoosh of air with a soft crack, like a wizard vanishing, 0.6 seconds
Legendary spell cast: sharp crack and fizzing sparks, deep boom, epic choir swell and falling shimmering bells, 1.6 seconds
Drawing a wooden wand from a robe for a duel: cloth swish, wood slide and a soft magical hum with tiny bells, 0.6 seconds
Putting a wooden wand away into a robe: soft cloth swish and a fading magical hum, 0.5 seconds
Knockout blow in a wizard duel: cinematic impact with a deep boom, a metallic ring and a short dark choir hit, 1.5 seconds
Wizard defeated: dark falling whoosh, deep boom, low mournful strings and a fading heartbeat, 2.5 seconds
Wizard respawning: reversed shimmering bells rising into a warm choir and a soft celesta chime, 2 seconds
Burning damage: short fiery flare with crackling embers, 0.5 seconds
Frost spell slowing a target: icy crackling freeze, glassy tinkling and a cold hiss, 0.8 seconds
Life-draining dark magic: swirling reverse whoosh pulling energy back, with a ghostly whisper, 0.8 seconds
Magic crystal shattering into shards: glassy explosion with falling tinkling fragments and a deep thud, 1 second
```

Maak meerdere versies: Wand spell cast (4×); Magic spell hitting a target (4×); Magic shockwave blast (3×); Powerful air pressure wave (2×); Releasing a fully charged spell (2×); Protective magic shield raised (2×); Spell deflected by a magic shield (3×); Magical dash (3×); Legendary spell cast (2×); Drawing a wooden wand from a robe for a duel (2×); Putting a wooden wand away into a robe (2×); Burning damage (3×).

🌈 Affiniteiten

```
Fire magic burst: whooshing flame ignition with crackling embers, 0.8 seconds
Ice magic burst: crystalline chimes, crackling frost and a cold shimmer, 0.8 seconds
Wind magic burst: swirling gust of air, 0.8 seconds
Storm magic burst: electric lightning crack with a short thunder rumble, 0.8 seconds
Nature magic burst: rustling leaves, creaking wood and soft celesta notes, 0.8 seconds
Dark magic burst: ominous reverse whoosh with a low whispering choir, 0.8 seconds
Light magic burst: radiant falling bells with a soft angelic choir, 0.8 seconds
```

🏅 Grimoire

```
Flicking through an old spell book: quick page riffle with a tiny magical chime, 0.5 seconds
Item revealed: two soft celesta notes with a gentle shimmer, 0.8 seconds
Rare item revealed: rising celesta arpeggio with sparkling bells and soft strings, 1.5 seconds
Epic item revealed: magical celesta melody in a minor key, swelling strings, a timpani hit and shimmering bells, 2 seconds
Legendary item revealed: triumphant orchestral brass chord, strings, choir, timpani and cymbal with a shower of bells, 2.5 seconds
Mythic item revealed: huge cinematic orchestral hit with deep brass, full choir, timpani, a sub boom and dazzling shimmering bells, 3.5 seconds
Reward redeemed: jingling gold coins and a bright magical celesta flourish, 1.5 seconds
```

Maak meerdere versies: Flicking through an old spell book (3×).

📜 Interface

```
Soft interface click: short wooden tick on old parchment, 0.5 seconds
Very soft paper touch, barely audible, 0.5 seconds
Opening a heavy leather spell book: soft thump, pages fluttering and a faint magical shimmer, 0.8 seconds
Closing a leather spell book: soft muffled thump, 0.5 seconds
Turning a single parchment page, 0.5 seconds
Two soft low wooden knocks, not allowed, 0.5 seconds
```

Maak meerdere versies: Soft interface click (3×); Very soft paper touch (2×); Turning a single parchment (2×).

🏰 Wereld

```
Heavy wooden castle door swinging open: deep creak, stone scrape and a soft magical hum, 1.2 seconds
Heavy wooden castle door closing with a deep echoing thud, 0.9 seconds
Deep castle clock tower bell strike with a long humming decay, echoing over the grounds, 5 seconds
Enchanted moonlit pond: gently lapping water, a soft magical shimmer and distant chimes, seamless loop
Underwater: deep muffled rumble with slow rising bubbles, seamless loop
Haunted dead forest: eerie wind through bare trees, creaking branches and a low ominous drone, seamless loop
Foggy grey lake shore: slow waves rolling onto the beach with a haunting low drone, seamless loop
```

## Zo komen ze in je game

1. Upload de gemaakte bestanden in Roblox Studio (View → Asset Manager → Bulk Import) en kopieer hun ids.
2. Zet de ids in `MogwartsSounds` bij `Sounds.LIBRARY`, onder de naam van het geluid. Varianten zet je in
   hetzelfde lijstje; de game kiest er telkens één:

```lua
Sounds.LIBRARY = {
	cast = { 111111111, 222222222, 333333333, 444444444 },
	impact = { 555555555 },
}
```

De namen per geluid, in dezelfde volgorde als hierboven:

- 🪄 gevecht: `cast`, `impact`, `blast`, `blast_whoosh`, `charge_loop`, `charge_full`, `charge_release`, `shield_up`, `shield_block`, `dash`, `mythic_cast`, `duel_draw`, `duel_holster`, `knockout`, `defeat`, `respawn`, `burn_tick`, `frost_slow`, `lifesteal`, `crystal_shatter`
- 🌈 affiniteiten: `aff_fire`, `aff_ice`, `aff_wind`, `aff_storm`, `aff_nature`, `aff_dark`, `aff_light`
- 🏅 grimoire: `reroll`, `reveal_common`, `reveal_rare`, `reveal_epic`, `reveal_legendary`, `reveal_mythic`, `code_redeem`
- 📜 interface: `ui_click`, `ui_hover`, `ui_open`, `ui_close`, `ui_tab`, `ui_denied`
- 🏰 wereld: `magic_door_open`, `magic_door_close`, `clock_bell`, `moonpool_loop`, `underwater_loop`, `deadwood_loop`, `shore_loop`

Roblox beperkt hoeveel audio je per maand mag uploaden. Begin daarom met de geluiden die je het vaakst
hoort (de spreuk, de treffer, blast, shield, dash en de knoppen). Wat je niet vervangt, blijft uit het pakket komen.
