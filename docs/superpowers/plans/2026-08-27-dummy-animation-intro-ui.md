# Dummy Animation + Battle Intro UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the training dummy from acting during battle intro, give it real movement/combat animations using existing SEVER assets, and replace the old intro / inconsistent matchmaking styling with one cohesive training-settings visual family.

**Architecture:** Keep the server authoritative for when AI becomes active, add a focused server NPC animation controller that harvests existing Animation instances and known established fallback IDs, and add a ReplicatedFirst replacement intro that hides the old intro only while the new overlay is active. Extend the existing runtime UI unifier so it can sample hidden training-settings controls and reuse their authored visual tokens.

**Tech Stack:** Roblox Luau, Humanoid/Animator, ReplicatedFirst, PlayerGui, RemoteEvent/GameStateUpdate, TweenService, Players:GetUserThumbnailAsync.

**Spec:** `docs/superpowers/specs/2026-08-27-dummy-animation-intro-ui-design.md`

## Global Constraints

- Do not change damage values, hitboxes, ranked logic, matchmaking remote behavior, or normal match timers.
- Dummy AI cannot move/attack/defend before `Fighting`.
- Do not invent a Soul Reap animation asset ID.
- Prefer existing Animation instances; only use the already-established fallback IDs for dash/block/spin/throw.
- Matchmaking buttons keep their original click/event scripts.
- New intro must be responsive on PC and small mobile screens.

---

### Task 1: Gate Training AI Until Fighting

**Files:**
- Modify: `migration/ServerScriptService/DummyBattleServer.server.luau`
- Test: `migration/ServerScriptService/TrainingDummyBattleLifecycle.spec.luau`

**Interfaces:**
- Consumes: `startAIController(player, battle, level)` and `SetDummyLevelRemote`.
- Produces: `battle.fighting` boolean; AI controller exists only after the Fighting state is sent.

- [ ] **Step 1: Add lifecycle spec**

Create a Luau spec asserting the battle starts with `fighting=false`, level changes before fighting do not create an AI controller, and transitioning to fighting creates the controller exactly once.

- [ ] **Step 2: Verify current source violates the spec by inspection**

Confirm current `DummyBattleServer.server.luau` calls `startAIController(...)` immediately after teleporting the dummy, before `BattleIntro`/`Fighting`.

- [ ] **Step 3: Implement gating**

Set `battle.fighting = false` at creation, remove the early `startAIController(...)`, and after the server sends `Fighting`, set `battle.fighting = true` then call `startAIController(...)`. In `SetDummyLevelRemote`, destroy/restart the AI only when `battle.fighting == true`; otherwise update level/persistence only.

- [ ] **Step 4: Static verify**

Search the final file for any `startAIController` call before the `Fighting` send; there must be none.

- [ ] **Step 5: Commit**

Commit message: `fix: keep training dummy passive during intro`.

---

### Task 2: Add NPC Animation Controller

**Files:**
- Create: `migration/ServerScriptService/TrainingDummyAnimator.luau`
- Modify: `migration/ServerScriptService/TrainingDummyCombatAI.luau`
- Test: `migration/ServerScriptService/TrainingDummyAnimator.spec.luau`

**Interfaces:**
- Produces: `TrainingDummyAnimator.new(dummyModel)`, `:PlayAction(actionName)`, `:SetLocomotionEnabled(enabled)`, `:Destroy()`.
- Consumes: disabled Animate hierarchy on the cloned dummy and `StarterPack` scythe Animation instances.

- [ ] **Step 1: Add animator contract spec**

Assert the resolver maps animation-name keywords to locomotion/actions, accepts the established fallback IDs for Dash/Block/Spin/Throw, and leaves SoulReap unresolved if no real Animation exists.

- [ ] **Step 2: Implement asset harvesting**

Ensure an Animator exists under the Humanoid. Recursively collect Animation instances from the dummy clone and `game:GetService("StarterPack")`, normalize names to lowercase, and select tracks by keyword groups: idle, walk/run, jump, fall, slash/attack/swing, dash, grapple, block/parry, throw, spin, soul/reap.

- [ ] **Step 3: Add established fallbacks**

Use only:
- Dash: `rbxassetid://83398771525907`
- Block: `rbxassetid://103952923479033`
- Spin: `rbxassetid://89608736085843`
- Throw: `rbxassetid://95546671624902`

Do not create a Soul Reap fallback.

- [ ] **Step 4: Implement locomotion state playback**

Listen to Humanoid Running/StateChanged and crossfade Idle/Walk/Run/Jump/Fall where tracks exist. Do nothing if an expected source animation is absent.

- [ ] **Step 5: Integrate combat actions**

Instantiate the animator inside `TrainingDummyCombatAI.new`. Call `PlayAction` from slash, dash, grapple, block/parry, throw, spin and soul reap. Destroy animator with the AI controller.

- [ ] **Step 6: Commit**

Commit message: `feat: animate training dummy combat and movement`.

---

### Task 3: Replace the Battle Intro

**Files:**
- Create: `migration/ReplicatedFirst/SeverBattleIntro.client.luau`
- Modify: `migration/ReplicatedFirst/UnifiedUIController.client.luau`
- Test: `migration/ReplicatedFirst/SeverBattleIntroPolicy.spec.luau`

**Interfaces:**
- Consumes: `MatchEvents.GameStateUpdate` `BattleIntro`, `Countdown`, `Fighting`, `Lobby`.
- Produces: one `ScreenGui` named `SEVER_BattleIntro`; old intro-looking GuiObjects hidden only while replacement intro is active.

- [ ] **Step 1: Add intro-state spec**

Specify that the replacement appears only for `BattleIntro`, begins cleanup on `Countdown`/`Fighting`, and never hides health/matchmaking controls by text alone.

- [ ] **Step 2: Build replacement overlay**

Create a full-screen dim background, left/right rounded cards, avatar thumbnails via `GetUserThumbnailAsync`, player names, optional streak text, central `VS`, and a thin diagonal scythe-slice divider. Use Scale positions with size clamps suitable for small phones.

- [ ] **Step 3: Add restrained animation**

Tween left card from offscreen-left and right card from offscreen-right; fade/scale the VS divider; fade the whole overlay before countdown. No continuous expensive loops.

- [ ] **Step 4: Suppress old intro visually**

During BattleIntro, scan visible GuiObjects that strongly match `battleintro`, `versus`, exact player names under intro-like ancestors, snapshot `Visible`, hide them, then restore snapshots when the replacement ends.

- [ ] **Step 5: Theme from training settings**

Reuse theme sampling from UnifiedUIController where possible; if no training control is found at the instant of intro, use the same fallback tokens already used by the unifier.

- [ ] **Step 6: Commit**

Commit message: `feat: replace legacy battle intro with unified sever intro`.

---

### Task 4: Make Matchmaking Actually Use Training Settings Style

**Files:**
- Modify: `migration/ReplicatedFirst/UnifiedUIController.client.luau`

**Interfaces:**
- Consumes: existing live GuiButtons in PlayerGui.
- Produces: presentation-only changes; no remotes or button connections changed.

- [ ] **Step 1: Fix template discovery**

Remove the requirement that a training settings button be visible. Prefer Respawn Dummy, Infinite Health, Return to Lobby, or Dummy Level controls whether hidden or visible.

- [ ] **Step 2: Apply full authored tokens**

Copy background, transparency, UICorner, UIStroke, UIGradient, FontFace, text colors/strokes and button automatic-color behavior to matchmaking buttons.

- [ ] **Step 3: Keep battle visibility behavior**

Continue hiding casual/ranked/queue controls for all battle states and restoring their original visibility only in Lobby.

- [ ] **Step 4: Commit**

Commit message: `fix: style matchmaking from real training settings controls`.

---

### Task 5: Verify the Combined Patch

**Files:** all files above.

- [ ] **Step 1: Compare branch to main**

Confirm only training lifecycle/animation and presentation files plus specs/docs changed.

- [ ] **Step 2: Re-fetch modified production files**

Check for syntax mistakes, accidental placeholder files, and stale references.

- [ ] **Step 3: Verify invariants by source inspection**

Confirm: no AI controller before Fighting; no fabricated SoulReap ID; no changes to DamageHandler/ranked/match timers; old intro suppression restores visibility; matchmaking functions are not replaced.

- [ ] **Step 4: Runtime test handoff**

Studio checks: Level 1/10 cannot act during intro; idle/walk/dash/block/throw/spin animations render where assets exist; new intro replaces old; matchmaking matches training settings; PC + Mobile Emulator layout is clear.
