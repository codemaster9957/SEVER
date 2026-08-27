# Training Dummy Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn training into an untimed sparring mode with selectable Levels 0–10, authored combat VFX, and a persistent hidden adaptive Level 10 opponent.

**Architecture:** Keep `DummyBattleServer` authoritative for battle lifecycle and settings, add a focused `TrainingDummyAI` policy module plus a runtime combat controller, and persist only compact per-player learning statistics in `DataService`. A ReplicatedFirst client helper clones an existing training settings control at runtime so the new level button exactly inherits the existing UI style, and hides the battle timer only during training.

**Tech Stack:** Roblox Luau, Rojo, RemoteEvents, Humanoid/physics, existing SEVER authored VFX, DataService.

**Spec:** User-approved conversation design, 2026-08-27.

## Global Constraints

- Training dummy battle has no time limit.
- Level 0 is fully passive.
- Levels 1–9 unlock abilities cumulatively exactly as specified.
- Level 10 starts extremely strong and silently adapts to each player across sessions.
- Never disclose Level 10 learning/adaptation to the player.
- Level 10 does not read future inputs, bypass cooldowns, or use impossible zero-frame reactions.
- Use existing authored scythe slash/throw/spin/Soul Reap VFX; do not replace slash VFX with generated Parts.
- New difficulty control must clone/inherit an existing training settings button rather than invent a different style.

---

### Task 1: Difficulty contract and persistent memory

**Files:**
- Create: `migration/ServerScriptService/TrainingDummyAI.spec.luau`
- Create: `migration/ServerScriptService/TrainingDummyAI.luau`
- Modify: `migration/ServerScriptService/DataService.luau`

- [x] Write the contract test first.
- [x] Add cumulative capability tiers and compact adaptive memory model.
- [ ] Add `TrainingDummyLevel` and `TrainingAIMemory` to the profile schema.

### Task 2: Untimed battle and settings remote

**Files:**
- Modify: `migration/ServerScriptService/DummyBattleServer.server.luau`
- Create: `migration/ReplicatedStorage/MatchEvents/TrainingDummyControls/SetDummyLevel.model.json`

- [ ] Remove the training-only timer/update/end condition.
- [ ] Load the player's saved difficulty when training begins.
- [ ] Validate and apply Level 0–10 changes server-side.
- [ ] Include difficulty in `TrainingControlsSync`.

### Task 3: Runtime combat controller

**Files:**
- Create: `migration/ServerScriptService/TrainingDummyCombatAI.luau`
- Modify: `migration/ServerScriptService/DummyBattleServer.server.luau`
- Modify: `migration/ReplicatedFirst/ScytheVFXController.client.luau`

- [ ] Disable legacy embedded dummy combat scripts on the battle clone.
- [ ] Implement cumulative slash/movement/dash/grapple/block/throw/spin/Soul Reap abilities.
- [ ] Reuse authored SEVER VFX assets.
- [ ] Implement fair Level 5/9 advanced decision-making.
- [ ] Implement Level 10 persistent opponent modelling and adaptive counter-selection.
- [ ] Record player wins/losses and combat tendencies without exposing them in UI.

### Task 4: Exact-style client setting and timer hiding

**Files:**
- Create: `migration/ReplicatedFirst/TrainingDummySettingsEnhancer.client.luau`

- [ ] Detect training state from `GameStateUpdate`.
- [ ] Clone an existing training settings button and change only its name/text/action.
- [ ] Cycle Level 0–10 and sync the authoritative server value.
- [ ] Hide/restore battle timer UI only during training.
- [ ] Work with mouse, touch, and gamepad activation through `GuiButton.Activated`.

### Task 5: Verification

- [ ] Re-fetch every changed file from the branch.
- [ ] Compare branch against `main` and confirm no normal/ranked timer code changed.
- [ ] Confirm Level 0 cannot move/attack and Level 1 cannot move.
- [ ] Confirm Level 10 memory is never included in any client payload.
- [ ] Studio test: levels 0–9, button cycling, no timer, VFX, Return to Lobby.
- [ ] Published server test: Level 10 persistence across leave/rejoin.
