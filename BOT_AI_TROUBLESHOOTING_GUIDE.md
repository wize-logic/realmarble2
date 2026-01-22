# Bot AI Troubleshooting Guide

## Quick Setup
1. Press **F3** to open debug menu
2. Go to **Page 4** (Debug Logging)
3. Enable **"Master Debug"**
4. Check **only "Bot AI"** category
5. Watch console while playing

---

## What To Look For

### 🔴 **SYMPTOM 1: Bot Standing Still / Not Moving**

#### **Pattern A: Stuck in WANDER with No Movement**
**Debug Output:**
```
[Bot AI] Bot_2 | State: WANDER | Ability: Cannon | Target: None | Pos: (10.5, 3.0, -5.2) | HP: 3
[Bot AI] Bot_2 | State: WANDER | Ability: Cannon | Target: None | Pos: (10.5, 3.0, -5.2) | HP: 3  ← Same position!
```

**Diagnosis:** Bot can't find targets
**Causes:**
- All enemies dead/out of range
- Vision system blocked
- Bot is far from center of arena

**Quick Check:** Look at position - if X or Z > 35 units from origin, bot is near edge and may be stuck

---

#### **Pattern B: Rapid State Cycling (Confusion)**
**Debug Output:**
```
[Bot AI] Bot_2: WANDER → CHASE | Enemy in aggro range: 35.2fu
[Bot AI] Bot_2: CHASE → WANDER | No valid target
[Bot AI] Bot_2: WANDER → CHASE | Enemy in aggro range: 38.1fu
[Bot AI] Bot_2: CHASE → WANDER | No valid target
```

**Diagnosis:** Bot is at edge of aggro range (40 units), constantly gaining/losing target
**Fix:** This is working as intended - bot will stabilize when enemy moves closer/farther

---

#### **Pattern C: Stuck in COLLECT_ABILITY State**
**Debug Output:**
```
[Bot AI] Bot_2 | State: COLLECT_ABILITY | Ability: None | Target: None | Pos: (5.0, 1.5, -10.0) | HP: 3
[Bot AI] Bot_2: COLLECT_ABILITY → WANDER | No ability found - searching
[Bot AI] Bot_2: WANDER → COLLECT_ABILITY | Found ability to collect
[Bot AI] Bot_2 | State: COLLECT_ABILITY | Ability: None | Target: None | Pos: (5.1, 1.5, -10.1) | HP: 3
```

**Diagnosis:** Bot sees ability but can't reach it
**Causes:**
- Ability spawned on unreachable platform
- Ability fell off stage
- Bot is stuck in geometry

**Quick Check:** If position changes by < 0.5 units per 2 seconds, bot is stuck

---

### 🔴 **SYMPTOM 2: Bot Won't Attack (Standing Next to Enemy)**

#### **Pattern A: Has Ability But Not Using It**
**Debug Output:**
```
[Bot AI] Bot_2 | State: ATTACK | Ability: Sword | Target: Player (2.5u, HP:2) | Pos: (12.0, 3.0, 5.0) | HP: 3
[Bot AI] Bot_2 | State: ATTACK | Ability: Sword | Target: Player (2.3u, HP:2) | Pos: (12.1, 3.0, 5.1) | HP: 3
```
(No "Used Sword" message)

**Diagnosis:** Ability usage conditions not met
**Possible Causes:**
1. **Height difference too large** (melee from platform)
   - Check target Y position vs bot Y position
   - Sword/Explosion: needs < 3 units height diff
   - Dash Attack: needs < 4 units height diff

2. **Not aligned with target** (facing wrong direction)
   - Sword: needs 20° alignment
   - Dash/Cannon: needs 10° alignment
   - Explosion: needs 30° alignment

3. **Ability not ready** (cooldown)
   - Check if ability has cooldown active

**Quick Test:** If bot and target are at similar height (Y diff < 2) and distance is right but no attack = alignment issue

---

#### **Pattern B: Constantly Switching States**
**Debug Output:**
```
[Bot AI] Bot_2: ATTACK → CHASE | Enemy too far: 15.3fu
[Bot AI] Bot_2: CHASE → ATTACK | In attack range: 11.2fu
[Bot AI] Bot_2: ATTACK → CHASE | Enemy too far: 13.8fu
```

**Diagnosis:** Bot at edge of attack range (12 units), constantly switching
**Fix:** This will stabilize - attack range has hysteresis (12u → 14.4u)

---

### 🔴 **SYMPTOM 3: Bot Becomes Suddenly Passive (Was Fighting, Now Not)**

#### **Pattern A: Lost Ability**
**Debug Output:**
```
[Bot AI] Bot_2: ATTACK → COLLECT_ABILITY | No ability - collecting
[Bot AI] Bot_2 | State: COLLECT_ABILITY | Ability: None | Target: None
```

**Diagnosis:** Bot died/respawned and lost ability
**Expected:** Bot should immediately seek new ability (PRIORITY 0)
**Problem If:** Bot stays in COLLECT_ABILITY > 5 seconds without finding ability

---

#### **Pattern B: Retreat Loop**
**Debug Output:**
```
[Bot AI] Bot_2: ATTACK → RETREAT | Low health: 1/3
[Bot AI] Bot_2 | State: RETREAT | Ability: Cannon | Target: Player (25.3u, HP:3)
[Bot AI] Bot_2 | State: RETREAT | Ability: Cannon | Target: Player (28.1u, HP:3)
```

**Diagnosis:** Bot is retreating (health <= 1, enemy close)
**Expected:** Bot will retreat for 2.5-4.5 seconds then re-engage
**Problem If:** Bot stays in RETREAT > 5 seconds = stuck in retreat logic

---

#### **Pattern C: Platform Paralysis**
**Debug Output:**
```
[Bot AI] Bot_2 | State: CHASE | Ability: Sword | Target: Player (18.0u, HP:2) | Pos: (10.0, 5.0, 5.0) | HP: 3
[Bot AI] Bot_2 | State: CHASE | Ability: Sword | Target: Player (17.8u, HP:2) | Pos: (10.1, 5.0, 5.1) | HP: 3
```
(Tiny position changes, Y = 5.0 indicates platform)

**Diagnosis:** Bot on platform, not descending to chase
**This was supposed to be fixed!** Should have "jump-off logic"
**If this happens:** Bot has valid target below but isn't jumping down

---

### 🔴 **SYMPTOM 4: Bot Just Rolls Around Aimlessly**

#### **Pattern: Frequent State Changes with No Action**
**Debug Output:**
```
[Bot AI] Bot_2: WANDER → WANDER | No valid target
[Bot AI] Bot_2: WANDER → WANDER | No valid target
[Bot AI] Bot_2 | State: WANDER | Ability: Cannon | Target: None
```

**Diagnosis:** No enemies in range OR all enemies dead
**Check:** How many players alive? If only bots left, they need to find each other
**Problem If:** Multiple enemies < 40 units away but bot doesn't see them

---

## Key Metrics To Track

### Position Changes
- **Normal:** 2-5 units per 2 seconds (wandering), 5-10 units per 2 seconds (chasing)
- **Stuck:** < 0.5 units per 2 seconds
- **Platform stabilization:** 0 units for 0.8 seconds (expected)

### State Duration
- **WANDER:** Should not exceed 5 seconds if enemies present
- **CHASE:** Variable, but should switch to ATTACK within 10 seconds if successful
- **ATTACK:** Variable (2-10 seconds typical)
- **RETREAT:** Should last 2.5-4.5 seconds then transition
- **COLLECT_ABILITY:** Should complete in < 3 seconds if ability reachable
- **COLLECT_ORB:** Should complete in < 2 seconds if orb reachable

### Ability Usage Frequency
- **Cannon:** Should see "Used Cannon" every 1-3 seconds in ATTACK state (if aligned)
- **Sword:** Should see "Used Sword" every 1-2 seconds in ATTACK state (if in range)
- **Dash Attack:** Should see "Used Dash Attack" every 2-4 seconds
- **Explosion:** Should see "Used Explosion" every 1-2 seconds (if in range)

**Problem If:** Bot in ATTACK state for > 5 seconds with NO ability usage messages

---

## Critical State Machine Rules

### PRIORITY 0 (Absolute First):
```
No ability? → COLLECT_ABILITY or WANDER to search
```
**Expected:** This transition should be INSTANT (< 0.1 seconds)

### PRIORITY 1 (Second):
```
Health <= 1 AND enemy close? → RETREAT
```

### PRIORITY 2 (Third):
```
Has ability AND enemy < 14.4u? → ATTACK
```

### PRIORITY 3 (Fourth):
```
Has ability AND enemy < 40u? → CHASE
```

### PRIORITY 5 (Last):
```
No valid targets? → WANDER
```

---

## Emergency Red Flags 🚩

1. **Bot never prints ability usage** despite being in ATTACK state
   → Alignment/height checks failing continuously

2. **Bot logs same position 5+ times in a row** (excluding platform stabilization)
   → Bot physically stuck in geometry

3. **Bot switches states > 5 times in 2 seconds**
   → State machine instability (shouldn't happen after our fixes!)

4. **Bot stays in COLLECT_ABILITY > 10 seconds**
   → Pathfinding to ability failing

5. **Bot logs "No valid target" but you see enemies nearby**
   → Vision/target finding system broken

6. **Bot stops logging entirely**
   → Bot script crashed or bot was removed

---

## Quick Diagnostic Commands

While watching logs, ask yourself:

1. **Is the bot moving?** → Check position changes
2. **What state is it in?** → Should match behavior
3. **Does it have an ability?** → If no, should be collecting
4. **Does it have a valid target?** → If yes, should be engaging
5. **Is it at correct distance?** → CHASE (>14.4u), ATTACK (<14.4u)
6. **Is it using abilities?** → Look for "Used [Ability]" messages
7. **How long in current state?** → Flag if > expected duration

---

## Most Common Issues (Based on Fixes Made)

### ✅ FIXED:
- Bots clustering/huddling (player avoidance)
- Bots freezing on platforms (re-targeting same platform)
- Bots becoming passive (proactive edge checking)
- Bots not attacking from height (height awareness added)
- Bots freezing in place (rail navigation interference)

### ⚠️ POTENTIAL REMAINING:
- Bots not descending from platforms when target below
- Alignment checks too strict (10°-20° may be hard to meet)
- Platform navigation interfering with combat
- Vision system failures (can't see enemies through geometry)

---

## What To Share For Help

If you see an issue, copy these lines from console:
1. 10-20 seconds of bot logs showing the problem
2. Note the bot's state and position
3. Note what you expected vs what happened
4. Mention how many other players/bots are present

Example good report:
```
Bot_2 is standing still next to enemy player:

[Bot AI] Bot_2 | State: ATTACK | Ability: Sword | Target: Player (2.5u, HP:2) | Pos: (12.0, 3.0, 5.0) | HP: 3
[Bot AI] Bot_2 | State: ATTACK | Ability: Sword | Target: Player (2.3u, HP:2) | Pos: (12.1, 3.0, 5.1) | HP: 3
[Bot AI] Bot_2 | State: ATTACK | Ability: Sword | Target: Player (2.4u, HP:2) | Pos: (12.1, 3.0, 5.0) | HP: 3

Expected: Bot should swing sword (distance 2.4u is correct for sword < 6u)
Actual: Bot not attacking
Note: Player Y=3.0, Bot Y=3.0 (same height, so height check should pass)
```

With this, I can diagnose: alignment issue or cooldown issue.
