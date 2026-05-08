# Galaxy Conquest, TIC-80 Design Plan

An incremental game about conquering the galaxy one fleet at a time.
Branch: `claude/galaxy-conquest-game-plan-izqvc`. Target dir: `games/galaxy-conquest/`.

## 1. Core Loop

1. Idle income from owned planets and from kills.
2. Spend money on ships, research, and admiral hires.
3. Assign ships to an admiral, set a target planet, watch the fleet attack in a visible dogfight.
4. Killed ships leave wrecks that persist at the death site.
5. Salvage ships (escorted by fighters) scoop wrecks for bonus money and Research Points.
6. Spend RP on a 4-column tech tree to unlock bombers, capitals, more shipyards, more admiral slots, faster travel.
7. Push through 4 empires (Pirates, Hegemony, Star Kingdom, AI Hivemind), each gated by killing its capital.

## 2. Views

- **Galaxy map**: top-down, procedural ~40 systems, mouse to click. Lines show admiral movement vectors. Empire territories tinted.
- **System view**: zoom into a system to watch combat. Shows planet, defenses, your ships, enemy patrols, wrecks in orbit.
- Both share the same world simulation; combat ticks even when you are on the map.

## 3. Controls

- Mouse-driven UI. Hover tooltips, left-click select, right-click set target.
- Hotkeys: tab to swap map and system view, esc to deselect.

## 4. Resources

- **Money**: from kills, owned planets, salvaged wrecks. Buys ships, hires admirals, builds shipyards.
- **Research Points (RP)**: from kills, owned planets, salvage. Buys tech tree nodes.
- Saved via TIC-80 pmem.

## 5. Ships

| Class | Role | Notes |
|---|---|---|
| Fighter | Tank, draw fire | Cheap, fast, low HP. Starting unit. |
| Salvage | Wreck scoop | No guns, slow, fragile. Needs escort. Starting unit. |
| Bomber | Damage | Unlocked via Offense research. Mid HP, heavy guns, slow. |
| Capital (Flagship) | Admiral's command ship | Each admiral owns one. High HP, big guns. If destroyed in battle, the admiral dies. |

## 6. Admirals and Flagships

- The player starts with **1 admiral and their flagship already in-hand** at game start.
- Each admiral is permanently bound to one flagship (1:1). When you hire an admiral, a flagship is commissioned with them.
- Finite admiral slot count. Logistics research increases the cap up to roughly 6.
- New admirals come from **officer promotions**:
  - Officers (non-admiral crew) accumulate XP from missions and kills.
  - When one is "ready for promotion," a roster of 2 to 3 candidates appears with rolled traits; you pick one or pass.
  - Outside of promotion, you can also hire and fire from the active admiral list freely.
- Each admiral has 1 to 2 traits, e.g., +10% weapon damage, +1 fleet capacity, faster travel, salvage bonus.
- **Persistent fleet**: each admiral commands an ongoing fleet. Newly built ships can be assigned into any admiral's roster. The admiral always sails toward the currently selected target planet; change target anytime.
- **Flagship deploy toggle**: the admiral panel has a toggle, "Deploy flagship with fleet (on or off)." Persists until changed. The fleet works fine without the flagship; the admiral commands remotely from base. Use "off" to keep the flagship safe on a risky run.
- **Recall**: at any time, recall the fleet. Survivors retreat home. If the flagship was deployed, it returns with them.
- **Flagship death**: a flagship can only die in battle. While docked at home, it is never at risk. If the flagship is destroyed mid-fight, the admiral dies; remaining ships in the fleet are reabsorbed into the home pool.

## 7. Enemy Defenses

- **Planetary turrets**: always-on, scaling DPS and HP per planet tier.
- **Patrol fighters**: enemy planet spawns 1 to N patrols based on tier; engage your fleet on arrival.
- **Orbital station**: T3+ planets and all empire capitals have one. High HP, big guns, must be killed before the planet falls.

## 8. Construction

- Parallel shipyards. Start with 1, unlock more via Logistics research (cap around 5).
- Each shipyard builds one ship at a time, queued. Money charged on start.
- Ships report to the "home pool" until assigned to an admiral.

## 9. Tech Tree (4 branching columns)

- **Offense**: Bomber unlock, Capital-class hull buffs, +damage tiers, armor-piercing rounds.
- **Defense**: +hull HP, shields, repair drones for capitals, friendly turret around home.
- **Economy**: cheaper ships, more planet income, salvage value boost.
- **Logistics**: more shipyards, more admiral slots, faster travel, longer salvage range, faster build speed.

## 10. Combat (visible dogfights)

- Real-time, simple physics: ship has pos, vel, target. Fires bullets when in range.
- Hit detection is circle vs bullet.
- Ship death spawns a wreck entity at the death site, persistent (no decay).
- Salvage ships seek wrecks in their assigned target system, scoop, return for money + RP.

## 11. Map and Empires

- Procedural galaxy seeded by save slot, ~40 systems.
- 4 empire territories, each a cluster of 8 to 12 systems with 1 capital.
- Capital must be conquered to count the empire as defeated.
- Win when all 4 capitals fall.

## 12. Persistence (pmem layout)

- Money, RP
- Per-empire conquest flags
- Per-system: owner, defense level, wreck count (compressed)
- Admirals: slot index, flagship HP, traits, target planet id, fleet composition counts, deploy-flagship toggle
- Officer XP totals and pending promotion flags
- Research node bitmask
- Shipyard count and queue snapshot

## 13. Build Order (milestones, single branch)

1. **M1 Shell**: project scaffold under `games/galaxy-conquest/`, `meta.json`, blank `cart.p8` with placeholder `__label__`, mouse cursor, two-view skeleton (map + system), procedural map gen.
2. **M2 Combat**: fighter ship sim, bullets, HP, death, wreck drop, one enemy planet with turret.
3. **M3 Economy**: money, planet income, build queue, shipyard, fighter cost.
4. **M4 Salvage**: salvage ship class, wreck scoop, return-to-home, RP gain.
5. **M5 Admirals v1**: starting admiral + flagship, persistent fleet assignment, target select, deploy-flagship toggle, recall, flagship death.
6. **M6 Officers**: officer XP, promotion roster popup, trait rolls, hire/fire UI.
7. **M7 Research**: 4-column tech tree UI, node unlocks affecting sim.
8. **M8 Empires**: 4 empire clusters, patrols, orbital stations on capitals, win check.
9. **M9 Defenses polish**: T1 to T4 planet defenses, escalating fights.
10. **M10 Save/Load**: pmem read/write, slot menu.
11. **M11 Polish**: SFX, music, screen shake, label capture, balance pass, build deploy.

## 14. Risks and Open Items

- Token budget: TIC-80 has a 65,536-char source cap. A game this big will get tight; minify late and split logic into terse helpers.
- Mouse: requires TIC-80 PRO at edit time, but plays fine in browser export.
- Procedural map readability at 240x136: 40 stars is doable if we use 1px stars and zoom into territory clusters.
- Wrecks "no decay" can pile up; store as per-system counter rather than per-wreck entity once a system is offscreen.

## 15. Notes Pinned from Discussion

- Galaxy map + zoom into system view.
- Real-time idle, auto-launch when target is set.
- Visible dogfights with bullets.
- Persist via pmem.
- Money + Research Points only.
- Wrecks at death site, no decay.
- Parallel shipyards (unlock more).
- 4 empires, capital-gated.
- Mouse-driven UI.
- Player picks one target per admiral (persistent fleet).
- Procedural ~40 systems.
- Admirals = slot + 1 to 2 traits, persistent fleet, recallable, can die when flagship dies in battle.
- Officers rank up, promotion roster on promotion, finite slots gated by Logistics research, hire and fire freely.
- Player starts with 1 admiral and 1 flagship.
- Flagship deploy is a per-admiral toggle; fleet operates fine without it.
- Flagship can only die in battle; safe at home.
