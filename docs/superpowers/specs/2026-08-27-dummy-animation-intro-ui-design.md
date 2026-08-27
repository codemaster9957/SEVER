# Dummy Animation + Battle Intro UI Design

## Goal
Fix the training dummy attacking during battle intro, restore proper movement/combat animation, and replace the old battle intro / inconsistent matchmaking styling with one cohesive SEVER UI family based on the training dummy settings.

## Combat lifecycle
- Dummy AI must not start until the server sends `Fighting`.
- During `BattleIntro` and the pre-fight delay the dummy is passive: no movement, no attacks, no block/parry, no grapple, no dash.
- Level changes during the intro only update the selected level; the AI controller is created/enabled once fighting actually starts.

## Dummy animation system
Create a server-side NPC animation controller because LocalScripts such as Roblox `Animate` cannot drive the server-created NPC clone.

The controller will:
- Ensure the dummy Humanoid has an Animator.
- Harvest normal movement animations from Animation instances already contained inside the cloned dummy/its disabled `Animate` hierarchy.
- Harvest scythe combat Animation instances from the training dummy clone and the live StarterPack scythe Tool where available.
- Use known existing SEVER fallback animation IDs only where already established in the project/history: dash `83398771525907`, block `103952923479033`, spin `89608736085843`, throw `95546671624902`.
- Never invent a Soul Reap asset ID; if a Soul Reap Animation instance exists it is used, otherwise Soul Reap keeps its VFX/movement without a fabricated animation.
- Drive idle/walk/run/jump/fall automatically from Humanoid state and play action tracks for slash/dash/grapple/block/throw/spin/soul reap when the AI chooses those actions.
- Action animations temporarily override locomotion and cleanly stop/fade when the action ends or the level changes.

## UI theme source
- Matchmaking styling must sample training-setting controls whether they are visible or hidden.
- It copies the actual authored visual language: background, transparency, UICorner, UIStroke, UIGradient and font/text treatment.
- Existing matchmaking buttons and event connections remain intact; only presentation/visibility changes.

## New battle intro
Replace the old visual with a new ReplicatedFirst-created overlay while keeping server timing unchanged.

Style:
- full-screen dim layer
- two compact rounded player cards, left and right
- circular/rounded avatar portraits
- player names and optional streak labels
- central `VS` with a sharp scythe-slice divider
- restrained motion: cards slide in, divider flashes, then the whole overlay fades before countdown
- theme tokens sampled from training settings so it belongs to the same UI family
- responsive layout for small phones and desktop

The old intro UI is hidden only while the replacement intro is active, then restored/left to its normal state afterward.

## Battle HUD
Keep the previous upper-left / upper-right compact health layout, but theme it from the same real training-settings template. Matchmaking remains hidden for all non-lobby battle phases.

## Verification
- Static diff must touch only client presentation files plus training dummy server/AI animation lifecycle files.
- No damage numbers, hitboxes, ranked logic, matchmaking remote behavior or normal match timers are changed.
- Runtime test checklist in Studio: training Level 1 and Level 10 intros cannot damage/move before `Fighting`; idle/walk/dash/block/throw/spin animate where source assets are found; matchmaking visually matches training settings; old intro is suppressed; new intro scales on PC and Mobile Emulator.
