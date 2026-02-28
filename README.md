# [L4D2] Damage Instructor Hint

SourceMod plugin for Left 4 Dead 2 that displays damage numbers using `env_instructor_hint`, attached to the target and visible only to the player who dealt the damage.

## What this plugin does

- Shows damage on common infected, Witch, and special infected.
- The hint is only shown to the attacker.
- Groups pellets and very close damage ticks into a single number.
- Supports separate colors for normal damage and headshots.
- Includes 3 display modes.
- Uses a real limit of 5 active hints per attacker.

## Requirements

- SourceMod 1.12+
- `sdkhooks`
- `sdktools`

## Files

- Source: `l4d2_damage_instructor.sp`
- Auto-generated config: `cfg/sourcemod/l4d2_damage_instructor.cfg`

## Installation

1. Compile `l4d2_damage_instructor.sp`.
2. Move the compiled `.smx` to `addons/sourcemod/plugins/`.
3. Restart the server or load the plugin manually.
4. Edit `cfg/sourcemod/l4d2_damage_instructor.cfg`.

Manual load example:

```cfg
sm plugins load l4d2_damage_instructor
```

## Command

- `sm_dmghinttest`
  Sends a test hint with value `99` to the player using the command. Useful for validating position, duration, and color.

## Cvars

### `sm_dmg_instructor_enable`

- Default: `0`
- Range: `0` to `1`
- Purpose: Enables or disables the plugin.

```cfg
sm_dmg_instructor_enable "1"
```

### `sm_dmg_instructor_timeout`

- Default: `0.65`
- Range: `0.05` to `5.0`
- Purpose: How long, in seconds, the damage number stays visible.

Lower values keep the screen cleaner. Higher values make the numbers easier to track.

```cfg
sm_dmg_instructor_timeout "0.65"
```

### `sm_dmg_instructor_aggregate_window`

- Default: `0.03`
- Range: `0.0` to `0.25`
- Purpose: Aggregation window used to merge very close damage events into a single number.

This is especially useful for shotgun pellets and some damage ticks that happen almost at the same time.

```cfg
sm_dmg_instructor_aggregate_window "0.03"
```

### `sm_dmg_instructor_range`

- Default: `3000`
- Range: `0` to `10000`
- Purpose: Maximum distance, in game units, at which the hint can be shown.

```cfg
sm_dmg_instructor_range "3000"
```

### `sm_dmg_instructor_forcecaption`

- Default: `1`
- Range: `0` to `1`
- Purpose: Forces the instructor caption to display more consistently, including at longer distances.

If you want behavior closer to the game's default instructor system, try `0`.

```cfg
sm_dmg_instructor_forcecaption "1"
```

### `sm_dmg_instructor_mode`

- Default: `0`
- Range: `0` to `2`
- Purpose: Defines how damage is displayed or accumulated.

Modes:

- `0`: stacked. Each resolved damage event becomes a new hint, respecting the 5-slot limit per attacker.
- `1`: continuous accumulated. Damage keeps adding in the same slot until the chain expires.
- `2`: accumulated per infected. Each target keeps its own running total while it remains inside the reset window.

```cfg
sm_dmg_instructor_mode "0"
```

### `sm_dmg_instructor_chain_reset`

- Default: `1.0`
- Range: `0.1` to `10.0`
- Purpose: Time without damage before accumulated totals are reset.

Note: this cvar mainly matters in modes `1` and `2`.

```cfg
sm_dmg_instructor_chain_reset "1.0"
```

### `sm_dmg_instructor_color_normal`

- Default: `255 0 0`
- Format: `R G B`
- Purpose: Hint color for normal damage.

```cfg
sm_dmg_instructor_color_normal "255 0 0"
```

### `sm_dmg_instructor_color_headshot`

- Default: `255 140 0`
- Format: `R G B`
- Purpose: Hint color for headshots.

```cfg
sm_dmg_instructor_color_headshot "255 140 0"
```

## How each mode behaves

### Mode 0: stacked

Best if you want fast feedback with separate numbers for each hit.

- Each resolved damage event creates its own hint.
- The plugin reuses up to 5 slots per attacker.
- Good for a more arcade-like visual style.

### Mode 1: continuous accumulated

Best for tracking burst damage on a single target.

- All damage keeps adding in the same slot.
- The total resets if you switch targets.
- The total also resets if the delay defined by `sm_dmg_instructor_chain_reset` is exceeded.

### Mode 2: accumulated per infected

Best for per-target focus tracking.

- Each infected can keep its own running total.
- The plugin still respects the limit of 5 active slots per attacker.
- If a target disappears, changes entity reference, or expires by reset time, its total is cleared.

## Example configuration

### Balanced default setup

```cfg
sm_dmg_instructor_enable "1"
sm_dmg_instructor_timeout "0.65"
sm_dmg_instructor_aggregate_window "0.03"
sm_dmg_instructor_range "3000"
sm_dmg_instructor_forcecaption "1"
sm_dmg_instructor_mode "0"
sm_dmg_instructor_chain_reset "1.0"
sm_dmg_instructor_color_normal "255 0 0"
sm_dmg_instructor_color_headshot "255 140 0"
```

### Accumulated reading setup

```cfg
sm_dmg_instructor_enable "1"
sm_dmg_instructor_mode "2"
sm_dmg_instructor_chain_reset "1.25"
sm_dmg_instructor_timeout "0.8"
```

## Notes

- The plugin is intended for human survivors.
- Hints are local to the attacker, not global.
- Tank damage is filtered by the plugin logic in several cases, so the main focus is common infected, Witch, and non-Tank special infected.
- Headshots can use a separate color.
- The config file is generated automatically by `AutoExecConfig`.

## License

Add the repository license that matches how you want to publish the project.
