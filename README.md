## L4D2 Damage Instructor Hint

A Left 4 Dead 2 damage display plugin using `env_instructor_hint`, with per-attacker separated damage hints.

### Features
- Shows dealt damage in real time
- Headshots use a different color
- Shotgun pellets are merged into a single number within a short time window
- Filters broken Tank values such as `1` damage or extremely large numbers
- Two display modes controlled by cvars

### Credits
This plugin was built using the `l4d2_infected_hud.sp` plugin by BloodyBlade as a base:  
https://github.com/BloodyBlade/L4D2-Plugins/blob/main/l4d2_infected_hud.sp

### Cvars
- `sm_dmg_instructor_enable`
  - `0` = disabled
  - `1` = enabled

- `sm_dmg_instructor_timeout`
  - How long the damage number stays visible
  - Example: `0.65`

- `sm_dmg_instructor_aggregate_window`
  - Time window used to merge pellets/ticks into a single number
  - Useful for shotguns
  - Example: `0.03`

- `sm_dmg_instructor_range`
  - Maximum range at which the hint can be seen
  - Example: `3000`

- `sm_dmg_instructor_forcecaption`
  - `0` = normal caption behavior
  - `1` = forces the caption to display more consistently

- `sm_dmg_instructor_mode`
  - `0` = default mode, shows separate damage numbers
  - `1` = chained mode, replaces the previous number with the current accumulated total

- `sm_dmg_instructor_chain_reset`
  - Time without dealing damage before the chained total resets in mode `1`
  - Example: `1.0`
    
- `sm_dmg_instructor_color_normal`
  - Defines the color used for normal damage numbers.
  - Example: `sm_cvar sm_dmg_instructor_color_normal "255 0 0"`
    
- `sm_dmg_instructor_color_headshot`
  - Defines the color used for headshot damage numbers.
  - Example: `sm_cvar sm_dmg_instructor_color_headshot "255 165 0"`

> ⚠️ Note: These colors are defined using RGB values, but due to the game's palette limitations, the displayed colors may not be *100%* accurate to the exact RGB you choose.

### Modes
#### Mode 0
Default plugin behavior.  
Each damage instance is shown separately.

#### Mode 1
Continuous accumulated damage mode.  
As long as you keep hitting, the previous number disappears and is replaced with the new accumulated total.  
If you stop dealing damage for the time set in `sm_dmg_instructor_chain_reset`, the counter resets.

### Example configuration
```cfg
sm_cvar sm_dmg_instructor_enable 1
sm_cvar sm_dmg_instructor_timeout 0.65
sm_cvar sm_dmg_instructor_aggregate_window 0.03
sm_cvar sm_dmg_instructor_range 3000
sm_cvar sm_dmg_instructor_forcecaption 1
sm_cvar sm_dmg_instructor_mode 0
sm_cvar sm_dmg_instructor_chain_reset 1.0
