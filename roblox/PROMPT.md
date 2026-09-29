# Prompt: het geluidspakket in je game laten zetten

Deze prompt geef je aan de AI-assistent in Roblox Studio, of aan een andere AI die je place kan bewerken.
De AI zet dan alle geluiden op de juiste plekken in je scripts. Dat werkt ook als je die scripts sinds
`mogwarts3.rbxl` hebt veranderd.

Twee dingen kan geen AI voor je doen, dus die doe je eerst zelf:

1. **Uploaden:** zet de 8 bestanden uit `audio/` in Studio via **View → Asset Manager → Bulk Import**. Kopieer
   daarna van elk bestand de id (rechtsklik → **Copy Asset ID**).
2. **Module plakken:** voeg in **ReplicatedStorage → WizardShared** een ModuleScript toe met de naam
   `MogwartsSounds`. Plak daarin de inhoud van `MogwartsSounds.lua`.

Vul in de prompt hieronder je 8 ids in op de plekken met `ID`. Kopieer daarna de hele prompt en plak hem in de assistent.
De prompt is in het Engels, omdat AI-assistenten code-opdrachten in het Engels het nauwkeurigst uitvoeren.

---

```text
Add the Mogwarts sound pack to this game. The ModuleScript ReplicatedStorage > WizardShared > MogwartsSounds already exists. Its API:
- Sounds.play(name, where, opts): plays a one-shot. `where` is a BasePart or Attachment (3D), a Vector3 (3D at that point) or nil (2D). opts = { volume = multiplier, pitch = multiplier, group = SoundGroup }. Returns the Sound, or nil if that sound is not available.
- Sounds.loop(name, where, opts): starts a looping sound and returns it (or nil).
- Sounds.affinity(affinityName, where, opts): plays the flavour layer for an affinity.
- Sounds.preload(): preloads the audio on a client.
Rules: keep every existing sound as a fallback. Wherever you replace one, only play the old sound when the pack call returned nil. Require the module once at the top of each script you change. Do not change anything else.

0. In MogwartsSounds, set Sounds.ASSET_IDS to: combat = ID, interface = ID, world = ID, charge_loop = ID, moonpool_loop = ID, underwater_loop = ID, deadwood_loop = ID, shore_loop = ID.

1. ServerScriptService > WizardServer > CombatServer
 a. Rename the local function sound(parent, key) to oldSound. Add a new local function sound(parent, key) that maps the key to a pack name (Cast = "cast", Impact = "impact", Blast = "blast", BlastWhoosh = "blast_whoosh", Shield = "shield_up", Dash = "dash", MythicCast = "mythic_cast", MythicWhoosh = "blast_whoosh", Draw = "duel_draw", Holster = "duel_holster"), calls Sounds.play(name, parent), and calls oldSound(parent, key) only if that returned nil.
 b. castBolt: right after sound(root, "Cast"), add Sounds.affinity(aff.Name, root).
 c. chargeRelease: replace sound(root, "Blast") and sound(root, "Cast") with Sounds.play("charge_release", root) (use the two old calls only if it returned nil), then add Sounds.affinity(aff.Name, root).
 d. applyDamage: where a hit is blocked by a shield ("Blocked"), add Sounds.play("shield_block", pos). Where a training dummy is knocked out ("KO!"), add Sounds.play("knockout", pos). In the lifesteal branch, also take the attacker's HumanoidRootPart from aliveChar and add Sounds.play("lifesteal", thatRootPart, { volume = 0.6 }). In the burn loop, after each burn damage number, add Sounds.play("burn_tick", head). Where the slow is applied (SlowMult attribute), add Sounds.play("frost_slow", pos).
 e. fireBolt: after sound(p, "Impact"), if splashModels is not empty, add Sounds.play("crystal_shatter", p).
 f. onCharacter: once the character is set up, play Sounds.play("respawn", its HumanoidRootPart), and connect Humanoid.Died to Sounds.play("defeat", the HumanoidRootPart's Position).

2. StarterPlayer > StarterPlayerScripts > SpellFXClient (the charged-shot orb)
 a. Where the looping charge hum (HUM_ID) is created on the orb, first try Sounds.loop("charge_loop", e.orb) and store it in e.snd. Only create the old hum if that returned nil.
 b. Every frame while charging, set e.snd.PlaybackSpeed = 0.85 + 0.35 * math.clamp(frac, 0, 1) so the hum rises as the charge builds.
 c. Where the charge becomes full (e.full = true), add Sounds.play("charge_full", tip).

3. ReplicatedStorage > WizardShared > UIStyle, function UI.play(kind, volume, speed)
 Require the module safely: local packOk, Pack = pcall(function() return require(script.Parent:FindFirstChild("MogwartsSounds")) end). At the start of UI.play, map Click = "ui_click", Hover = "ui_hover", Open = "ui_open", Close = "ui_close", Tab = "ui_tab", Denied = "ui_denied". If packOk and the kind is mapped, call Pack.play(name, nil, { volume = volume and volume / (kind == "Hover" and 0.12 or 0.35) or 1, pitch = speed, group = UI.soundGroup("UI") }) and return if it played. Otherwise run the old code.

4. StarterGui > WizardHUD > HUDController (use opts { group = UI.soundGroup("UI") } for every call here)
 a. revealItem: play Sounds.play("reveal_" .. string.lower(item.Rarity), nil, opts). Keep the old chime only when that returned nil.
 b. Reroll button: when clicked, Sounds.play("reroll", nil, opts). After a successful reroll whose rarity Order is below 3, Sounds.play("reveal_common", nil, opts). When the reroll fails, Sounds.play("ui_denied", nil, opts).
 c. Redeem button: on success Sounds.play("code_redeem", nil, opts), on failure Sounds.play("ui_denied", nil, opts).

5. ServerScriptService > WizardServer > DoorSystem: when a door opens, Sounds.play("magic_door_open", door). When it closes, Sounds.play("magic_door_close", door).

6. StarterPlayer > StarterPlayerScripts > Ambience
 a. Call Sounds.preload() once.
 b. Add three zone loops, each started with Sounds.loop(name, nil, { group = group("Ambience") }) and then set to Volume 0: "deadwood_loop" at Vector3.new(410, 20, 0), radius 130, max volume 0.5; "shore_loop" at Vector3.new(-305, 4, 360), radius 120, max 0.45; "moonpool_loop" at Vector3.new(-220, 13, -410), radius 60, max 0.4. In the existing Heartbeat loop, fade each one towards max * math.clamp((radius - distance) / (radius * 0.4), 0, 1), or 0 when underwater, the same way the existing layers fade.
 c. When NightLevel goes from 0.5 or lower to above 0.5, play Sounds.play("clock_bell", nil, { group = group("Ambience"), volume = inCastle and 0.8 or 0.5 }) three times, 2.6 seconds apart.

When done, list every script you changed and what you added to each.
```

---

## Liever geen prompt?

In `scripts/` staan dezelfde wijzigingen al kant-en-klaar, als complete scripts om over je versie van
`mogwarts3.rbxl` heen te plakken. Die route staat in `README.md`.
