/**
 * L4D2 Damage Numbers - FOLLOW (env_instructor_hint + info_target_instructor_hint parented)
 *
 * - Dano vermelho grudado no alvo (infected/witch/players)
 * - Só aparece pro atacante
 * - Limite REAL de 5 por atacante (substitui o mais antigo)
 * - Some certinho (mata entidades no timer)
 *
 * Requer: SourceMod 1.12 + SDKHooks + SDKTools
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define STACK_LIMIT 5
#define MAX_TRACKED_ENTITIES 2048
#define NAME_LEN 48
#define INVALID_ACCUM_SLOT -1
#define EVENT_FALLBACK_DUP_WINDOW 0.05
#define HEADSHOT_MATCH_WINDOW 0.03

ConVar g_cvEnable;
ConVar g_cvTimeout;
ConVar g_cvAggregateWindow;
ConVar g_cvRange;
ConVar g_cvForceCaption;
ConVar g_cvMode;
ConVar g_cvChainReset;
ConVar g_cvColorNormal;
ConVar g_cvColorHeadshot;

int g_iSerial[MAXPLAYERS + 1];
int g_iSlotSerial[MAXPLAYERS + 1][STACK_LIMIT];
int g_iPendingDamage[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iPendingSerial[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
bool g_bPendingHeadshot[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fLastHeadshotAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
bool g_bPendingHeadshotCarry[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fLastQueuedAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
Handle g_hPendingTimer[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iRecentQueuedDamage[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fRecentQueuedAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iShotFatalHealth[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iShotFatalSerial[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fShotFatalAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fDirectFatalShownAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fLastShownAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iLastVictimEntRef[MAX_TRACKED_ENTITIES + 1];
bool g_bLastVictimPosValid[MAX_TRACKED_ENTITIES + 1];
float g_vLastVictimPos[MAX_TRACKED_ENTITIES + 1][3];
float g_fLastVictimPosAt[MAX_TRACKED_ENTITIES + 1];
int g_iChainVictim[MAXPLAYERS + 1];
int g_iChainDamage[MAXPLAYERS + 1];
bool g_bChainHeadshot[MAXPLAYERS + 1];
float g_fChainLastHitAt[MAXPLAYERS + 1];
int g_iAccumDamage[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iAccumEntRef[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iAccumSlot[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
bool g_bAccumHeadshot[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fAccumLastHitAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iAccumSlotVictim[MAXPLAYERS + 1][STACK_LIMIT];

// refs do env_instructor_hint por slot
int g_iSlotHintRef[MAXPLAYERS + 1][STACK_LIMIT];
int g_iSlotAnchorRef[MAXPLAYERS + 1][STACK_LIMIT];

public Plugin myinfo =
{
    name        = "[L4D2] Damage Instructor Hint",
    author      = "Weyrich",
    description = "Mostra dano em env_instructor_hint separado por atacante",
    version     = "4.1.0",
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnable  = CreateConVar("sm_dmg_instructor_enable", "0", "0=off 1=on", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTimeout = CreateConVar("sm_dmg_instructor_timeout", "0.65", "Tempo (seg) na tela (float)", FCVAR_NOTIFY, true, 0.05, true, 5.0);
    g_cvAggregateWindow = CreateConVar("sm_dmg_instructor_aggregate_window", "0.03", "Janela para somar pellets/ticks em um numero", FCVAR_NOTIFY, true, 0.0, true, 0.25);
    g_cvRange = CreateConVar("sm_dmg_instructor_range", "3000", "Distancia maxima para ver o hint em unidades", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvForceCaption = CreateConVar("sm_dmg_instructor_forcecaption", "1", "1=forca caption para aparecer a longa distancia", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMode = CreateConVar("sm_dmg_instructor_mode", "0", "0=modo atual empilhado, 1=modo acumulado continuo, 2=modo acumulado por infected", FCVAR_NOTIFY, true, 0.0, true, 2.0);
    g_cvChainReset = CreateConVar("sm_dmg_instructor_chain_reset", "1.0", "Tempo sem dano para resetar a soma do modo 1", FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_cvColorNormal = CreateConVar("sm_dmg_instructor_color_normal", "255 0 0", "Cor RGB do dano normal no formato: R G B");
    g_cvColorHeadshot = CreateConVar("sm_dmg_instructor_color_headshot", "255 140 0", "Cor RGB do headshot no formato: R G B");
    RegConsoleCmd("sm_dmghinttest", Command_DmgHintTest);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);
    HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);
    HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);

    AutoExecConfig(true, "l4d2_damage_instructor");

    // late load
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i)) OnClientPutInServer(i);
}

public void OnClientPutInServer(int client)
{
    g_iSerial[client] = 0;
    for (int s = 0; s < STACK_LIMIT; s++)
    {
        g_iSlotSerial[client][s] = 0;
        g_iSlotHintRef[client][s] = INVALID_ENT_REFERENCE;
        g_iSlotAnchorRef[client][s] = INVALID_ENT_REFERENCE;
        g_iAccumSlotVictim[client][s] = 0;
    }
    ResetAccumState(client);
    ResetChainState(client);

    // hook de dano em players também
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage_Any);
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Any);

}

public void OnClientDisconnect(int client)
{
    for (int s = 0; s < STACK_LIMIT; s++)
    {
        KillEntRef(g_iSlotHintRef[client][s]);
        KillEntRef(g_iSlotAnchorRef[client][s]);
        g_iSlotHintRef[client][s] = INVALID_ENT_REFERENCE;
        g_iSlotAnchorRef[client][s] = INVALID_ENT_REFERENCE;
        g_iSlotSerial[client][s] = 0;
    }
    ResetPendingDamageForAttacker(client);
    ResetPendingDamageForVictim(client);
    ResetAccumState(client);
    ResetAccumStateForVictim(client);
    ResetChainState(client);
    g_iSerial[client] = 0;
}

public void OnMapStart()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_iSerial[client] = 0;
        for (int s = 0; s < STACK_LIMIT; s++)
        {
            g_iSlotSerial[client][s] = 0;
            g_iSlotHintRef[client][s] = INVALID_ENT_REFERENCE;
            g_iSlotAnchorRef[client][s] = INVALID_ENT_REFERENCE;
            g_iAccumSlotVictim[client][s] = 0;
        }
        ResetPendingDamageForAttacker(client);
        ResetAccumState(client);
        ResetChainState(client);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    // common infected / witch
    if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
    {
        SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Any);
        SDKHook(entity, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Any);
    }
}

static bool IsTankVictim(int victim)
{
    if (victim < 1 || victim > MaxClients)
        return false;
    if (!IsClientInGame(victim))
        return false;
    if (GetClientTeam(victim) != 3)
        return false;
    if (!HasEntProp(victim, Prop_Send, "m_zombieClass"))
        return false;

    return GetEntProp(victim, Prop_Send, "m_zombieClass") == 8;
}

static bool ShouldBlockTankDamageHint(int victim, int damage)
{
    if (!IsTankVictim(victim))
        return false;

    return damage == 1 || damage > 5000;
}

static bool GetVictimOrigin(int victimEnt, float pos[3])
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;

    if (victimEnt <= MaxClients)
    {
        if (!IsClientInGame(victimEnt))
            return false;

        GetClientAbsOrigin(victimEnt, pos);
        return true;
    }

    if (!IsValidEntity(victimEnt))
        return false;

    if (HasEntProp(victimEnt, Prop_Data, "m_vecAbsOrigin"))
    {
        GetEntPropVector(victimEnt, Prop_Data, "m_vecAbsOrigin", pos);
        return true;
    }

    if (HasEntProp(victimEnt, Prop_Send, "m_vecOrigin"))
    {
        GetEntPropVector(victimEnt, Prop_Send, "m_vecOrigin", pos);
        return true;
    }

    return false;
}

static void StoreVictimPosition(int victimEnt)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    float pos[3];
    if (!GetVictimOrigin(victimEnt, pos))
        return;

    g_vLastVictimPos[victimEnt][0] = pos[0];
    g_vLastVictimPos[victimEnt][1] = pos[1];
    g_vLastVictimPos[victimEnt][2] = pos[2];
    g_bLastVictimPosValid[victimEnt] = true;
    g_fLastVictimPosAt[victimEnt] = GetGameTime();
    g_iLastVictimEntRef[victimEnt] = EntIndexToEntRef(victimEnt);
}

static bool HasFreshVictimPosition(int victimEnt)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;
    if (!g_bLastVictimPosValid[victimEnt])
        return false;

    return (GetGameTime() - g_fLastVictimPosAt[victimEnt]) <= 0.10;
}

static bool IsHumanSurvivor(int client)
{
    if (client < 1 || client > MaxClients)
        return false;
    if (!IsClientInGame(client) || IsFakeClient(client))
        return false;

    return GetClientTeam(client) == 2;
}

static bool IsShotDamageType(int damagetype)
{
    return damagetype == 0 || (damagetype & (DMG_BULLET | DMG_BUCKSHOT)) != 0;
}

static bool IsTrackedInfectedVictim(int victimEnt)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;

    if (victimEnt <= MaxClients)
    {
        if (!IsClientInGame(victimEnt))
            return false;
        if (GetClientTeam(victimEnt) != 3)
            return false;

        return !IsTankVictim(victimEnt);
    }

    if (!IsValidEntity(victimEnt))
        return false;

    char classname[16];
    GetEntityClassname(victimEnt, classname, sizeof(classname));
    return StrEqual(classname, "infected") || StrEqual(classname, "witch");
}

static int GetVictimHealthValue(int victimEnt)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return 0;

    if (victimEnt <= MaxClients)
    {
        if (!IsClientInGame(victimEnt))
            return 0;
    }
    else if (!IsValidEntity(victimEnt))
    {
        return 0;
    }

    if (HasEntProp(victimEnt, Prop_Data, "m_iHealth"))
        return GetEntProp(victimEnt, Prop_Data, "m_iHealth");
    if (HasEntProp(victimEnt, Prop_Send, "m_iHealth"))
        return GetEntProp(victimEnt, Prop_Send, "m_iHealth");

    return 0;
}

static void ClearShotFatalFallback(int attacker, int victimEnt)
{
    if (attacker < 1 || attacker > MaxClients)
        return;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    g_iShotFatalHealth[attacker][victimEnt] = 0;
    g_iShotFatalSerial[attacker][victimEnt] = 0;
    g_fShotFatalAt[attacker][victimEnt] = 0.0;
}

static bool WasShotFatalHeadshot(int attacker, int victimEnt, float shotAt)
{
    if (attacker < 1 || attacker > MaxClients)
        return false;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;

    float headshotAt = g_fLastHeadshotAt[attacker][victimEnt];
    if (headshotAt <= 0.0)
        return false;

    return FloatAbs(headshotAt - shotAt) <= 0.10;
}

static bool WasDirectFatalShownRecently(int attacker, int victimEnt)
{
    if (attacker < 1 || attacker > MaxClients)
        return false;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;

    return (GetGameTime() - g_fDirectFatalShownAt[attacker][victimEnt]) <= 0.10;
}

static bool HasRecentDamageActivity(int attacker, int victimEnt)
{
    if (attacker < 1 || attacker > MaxClients)
        return false;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;

    float shotAt = g_fShotFatalAt[attacker][victimEnt];
    if (shotAt <= 0.0)
        return false;
    if (g_iPendingDamage[attacker][victimEnt] > 0)
        return true;
    if (g_fRecentQueuedAt[attacker][victimEnt] >= shotAt)
        return true;
    if (g_fLastShownAt[attacker][victimEnt] >= shotAt)
        return true;

    return false;
}

static void TryQueueShotFatalFallback(int attacker, int victimEnt, bool headshot = false)
{
    if (!IsHumanSurvivor(attacker))
        return;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    int damage = g_iShotFatalHealth[attacker][victimEnt];
    if (damage <= 0)
        return;

    if ((GetGameTime() - g_fShotFatalAt[attacker][victimEnt]) > 0.20)
    {
        ClearShotFatalFallback(attacker, victimEnt);
        return;
    }

    if (HasRecentDamageActivity(attacker, victimEnt))
    {
        ClearShotFatalFallback(attacker, victimEnt);
        return;
    }

    ClearShotFatalFallback(attacker, victimEnt);

    if (ShouldBlockTankDamageHint(victimEnt, damage))
        return;

    QueueDamageHintFallback(attacker, victimEnt, damage, headshot);
}

public Action Timer_TryShotFatalFallback(Handle timer, any data)
{
    DataPack dp = view_as<DataPack>(data);
    dp.Reset();

    int attacker = dp.ReadCell();
    int victimEnt = dp.ReadCell();
    int serial = dp.ReadCell();
    delete dp;

    if (attacker < 1 || attacker > MaxClients)
        return Plugin_Stop;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return Plugin_Stop;
    if (g_iShotFatalSerial[attacker][victimEnt] != serial)
        return Plugin_Stop;

    float shotAt = g_fShotFatalAt[attacker][victimEnt];
    TryQueueShotFatalFallback(attacker, victimEnt, WasShotFatalHeadshot(attacker, victimEnt, shotAt));
    return Plugin_Stop;
}

public Action OnTakeDamage_Any(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_cvEnable.BoolValue)
        return Plugin_Continue;
    if (damage <= 0.0)
        return Plugin_Continue;

    StoreVictimPosition(victim);

    if (!IsHumanSurvivor(attacker))
        return Plugin_Continue;
    if (!IsTrackedInfectedVictim(victim))
        return Plugin_Continue;
    if (!IsShotDamageType(damagetype))
    {
        ClearShotFatalFallback(attacker, victim);
        return Plugin_Continue;
    }
    if (g_iPendingDamage[attacker][victim] > 0 || g_hPendingTimer[attacker][victim] != null)
        return Plugin_Continue;

    int victimHealth = GetVictimHealthValue(victim);
    if (victimHealth > 0)
    {
        int shotDamage = RoundToNearest(damage);
        g_iShotFatalHealth[attacker][victim] = victimHealth;
        g_fShotFatalAt[attacker][victim] = GetGameTime();

        if (shotDamage >= victimHealth)
        {
            g_fDirectFatalShownAt[attacker][victim] = GetGameTime();
            DisplayResolvedDamageHint(attacker, victim, victimHealth, false, true);
            ClearShotFatalFallback(attacker, victim);
        }
    }

    return Plugin_Continue;
}

static bool ResolveHintTarget(int victimEnt, int attacker, int slot, int serialNow, char[] targetName, int maxlen, int &anchorRef, bool forceAnchor = false)
{
    anchorRef = INVALID_ENT_REFERENCE;

    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;

    bool hasLiveTarget = false;
    if (victimEnt <= MaxClients)
    {
        hasLiveTarget = IsClientInGame(victimEnt);
    }
    else
    {
        hasLiveTarget = IsValidEntity(victimEnt);
    }

    if (!forceAnchor && hasLiveTarget)
    {
        int currentRef = EntIndexToEntRef(victimEnt);
        if (currentRef != INVALID_ENT_REFERENCE && currentRef == g_iLastVictimEntRef[victimEnt])
        {
            Format(targetName, maxlen, "dmg_target_%d", victimEnt);
            DispatchKeyValue(victimEnt, "targetname", targetName);
            return true;
        }
    }

    if (!g_bLastVictimPosValid[victimEnt])
        return false;

    int anchor = CreateEntityByName("info_target_instructor_hint");
    if (anchor == -1)
        return false;

    Format(targetName, maxlen, "dmg_anchor_%d_%d_%d", attacker, slot, serialNow);
    DispatchKeyValue(anchor, "targetname", targetName);
    DispatchSpawn(anchor);
    ActivateEntity(anchor);
    TeleportEntity(anchor, g_vLastVictimPos[victimEnt], NULL_VECTOR, NULL_VECTOR);
    anchorRef = EntIndexToEntRef(anchor);
    return true;
}

public void OnTakeDamagePost_Any(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    if (!g_cvEnable.BoolValue) return;
    if (damage <= 0.0) return;

    // atacante precisa ser player
    if (attacker < 1 || attacker > MaxClients) return;
    if (!IsClientInGame(attacker) || IsFakeClient(attacker)) return;
    if (WasDirectFatalShownRecently(attacker, victim)) return;

    // vítima precisa existir (player ou entity)
    if (victim <= 0 || victim > MAX_TRACKED_ENTITIES) return;

    bool hasLiveVictim = false;
    if (victim <= MaxClients)
        hasLiveVictim = IsClientInGame(victim);
    else
        hasLiveVictim = IsValidEntity(victim);

    if (!hasLiveVictim && !HasFreshVictimPosition(victim)) return;

    StoreVictimPosition(victim);

    int dmg = RoundToNearest(damage);
    if (dmg <= 0) return;
    if (ShouldBlockTankDamageHint(victim, dmg)) return;

    QueueDamageHint(attacker, victim, dmg);
}

static void ShowDamageFollow(int attacker, int victimEnt, int dmg, float duration, bool headshot = false, int forcedSlot = -1, bool forceAnchor = false)
{
    // ===== slot 0..4 (limite REAL)
    g_iSerial[attacker]++;
    int slot = (forcedSlot >= 0) ? forcedSlot : (g_iSerial[attacker] % STACK_LIMIT);
    int serialNow = g_iSerial[attacker];
    g_iSlotSerial[attacker][slot] = serialNow;

    // mata o antigo desse slot
    KillEntRef(g_iSlotHintRef[attacker][slot]);
    KillEntRef(g_iSlotAnchorRef[attacker][slot]);
    g_iSlotHintRef[attacker][slot] = INVALID_ENT_REFERENCE;
    g_iSlotAnchorRef[attacker][slot] = INVALID_ENT_REFERENCE;

    // ===== cria o env_instructor_hint mirando na âncora
    int hint = CreateEntityByName("env_instructor_hint");
    if (hint == -1)
    {
        return;
    }

    char targetName[NAME_LEN];
    int anchorRef = INVALID_ENT_REFERENCE;
    if (!ResolveHintTarget(victimEnt, attacker, slot, serialNow, targetName, sizeof(targetName), anchorRef, forceAnchor))
    {
        AcceptEntityInput(hint, "Kill");
        return;
    }

    char caption[16];
    Format(caption, sizeof(caption), "%d", dmg);
    ConfigureDamageHint(hint, attacker, slot, targetName, caption, headshot);

    DispatchSpawn(hint);
    AcceptEntityInput(hint, "ShowHint");
    g_fLastShownAt[attacker][victimEnt] = GetGameTime();

    g_iSlotHintRef[attacker][slot] = EntIndexToEntRef(hint);
    g_iSlotAnchorRef[attacker][slot] = anchorRef;

    // timer mata ambos no tempo exato
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(attacker));
    dp.WriteCell(slot);
    dp.WriteCell(serialNow);
    dp.WriteCell(EntIndexToEntRef(hint));
    dp.WriteCell(anchorRef);
    CreateTimer(duration, Timer_KillHintAndAnchor, dp, TIMER_FLAG_NO_MAPCHANGE);
}

static void ConfigureDamageHint(int hint, int attacker, int slot, const char[] targetName, const char[] caption, bool headshot)
{
    char buffer[64];
    char color[32];

    DispatchKeyValue(hint, "hint_target", targetName);
    DispatchKeyValue(hint, "hint_caption", caption);
    DispatchKeyValue(hint, "hint_activator_caption", caption);
    DispatchKeyValue(hint, "hint_static", "0");
    DispatchKeyValue(hint, "hint_timeout", "0.0");
    DispatchKeyValue(hint, "hint_icon_offset", "0");
    IntToString(g_cvRange.IntValue, buffer, sizeof(buffer));
    DispatchKeyValue(hint, "hint_range", buffer);
    DispatchKeyValue(hint, "hint_nooffscreen", "1");
    DispatchKeyValue(hint, "hint_icon_onscreen", "");
    DispatchKeyValue(hint, "hint_icon_offscreen", "");
    DispatchKeyValue(hint, "hint_binding", "");
    DispatchKeyValue(hint, "hint_forcecaption", g_cvForceCaption.BoolValue ? "1" : "0");
    if (headshot)
        g_cvColorHeadshot.GetString(color, sizeof(color));
    else
        g_cvColorNormal.GetString(color, sizeof(color));
    DispatchKeyValue(hint, "hint_color", color);
    DispatchKeyValue(hint, "hint_flags", "0");
    DispatchKeyValue(hint, "hint_display_limit", "0");
    DispatchKeyValue(hint, "hint_suppress_rest", "1");
    DispatchKeyValue(hint, "hint_instance_type", "2");
    DispatchKeyValue(hint, "hint_auto_start", "false");
    DispatchKeyValue(hint, "hint_local_player_only", "true");
    DispatchKeyValue(hint, "hint_allow_nodraw_target", "true");

    Format(buffer, sizeof(buffer), "dmg_hint_%d_%d", attacker, slot);
    DispatchKeyValue(hint, "hint_name", buffer);
    DispatchKeyValue(hint, "hint_replace_key", buffer);
}

static void QueueDamageHint(int attacker, int victimEnt, int damage)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    float now = GetGameTime();
    bool headshot = g_bPendingHeadshotCarry[attacker][victimEnt];
    g_bPendingHeadshotCarry[attacker][victimEnt] = false;

    g_iRecentQueuedDamage[attacker][victimEnt] = damage;
    g_fRecentQueuedAt[attacker][victimEnt] = now;
    g_fLastQueuedAt[attacker][victimEnt] = now;
    g_iPendingDamage[attacker][victimEnt] += damage;
    g_bPendingHeadshot[attacker][victimEnt] = headshot;

    g_iPendingSerial[attacker][victimEnt]++;

    if (g_hPendingTimer[attacker][victimEnt] != null)
    {
        delete g_hPendingTimer[attacker][victimEnt];
        g_hPendingTimer[attacker][victimEnt] = null;
    }

    float window = g_cvAggregateWindow.FloatValue;
    if (window < 0.0)
    {
        window = 0.0;
    }

    DataPack dp = new DataPack();
    dp.WriteCell(attacker);
    dp.WriteCell(victimEnt);
    dp.WriteCell(g_iPendingSerial[attacker][victimEnt]);
    g_hPendingTimer[attacker][victimEnt] = CreateTimer(window, Timer_FlushPendingDamage, dp, TIMER_FLAG_NO_MAPCHANGE);
}

static int ReadDamage(Event event)
{
    int damage = event.GetInt("dmg_health", 0);
    if (damage <= 0)
    {
        damage = event.GetInt("dmg_damage", 0);
    }
    if (damage <= 0)
    {
        damage = event.GetInt("damage", 0);
    }
    if (damage <= 0)
    {
        damage = event.GetInt("amount", 0);
    }
    return damage;
}

static bool WasRecentlyQueued(int attacker, int victimEnt, int damage)
{
    if (attacker < 1 || attacker > MaxClients)
        return false;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return false;
    if (g_iRecentQueuedDamage[attacker][victimEnt] != damage)
        return false;

    return (GetGameTime() - g_fRecentQueuedAt[attacker][victimEnt]) <= EVENT_FALLBACK_DUP_WINDOW;
}

static void QueueDamageHintFallback(int attacker, int victimEnt, int damage, bool headshot)
{
    if (damage <= 0)
        return;
    if (WasRecentlyQueued(attacker, victimEnt, damage))
        return;

    if (headshot)
    {
        MarkHeadshot(attacker, victimEnt);
    }

    QueueDamageHint(attacker, victimEnt, damage);
}

static void MarkHeadshot(int attacker, int victimEnt)
{
    if (attacker < 1 || attacker > MaxClients)
        return;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    g_fLastHeadshotAt[attacker][victimEnt] = GetGameTime();
    if (g_iPendingDamage[attacker][victimEnt] > 0 && (g_fLastHeadshotAt[attacker][victimEnt] - g_fLastQueuedAt[attacker][victimEnt]) <= HEADSHOT_MATCH_WINDOW)
    {
        g_bPendingHeadshot[attacker][victimEnt] = true;
    }
    else
    {
        g_bPendingHeadshotCarry[attacker][victimEnt] = true;
    }
}

public Action Timer_KillHintAndAnchor(Handle timer, any data)
{
    DataPack dp = view_as<DataPack>(data);
    dp.Reset();

    int attackerUid = dp.ReadCell();
    int slot        = dp.ReadCell();
    int serialExp   = dp.ReadCell();
    int hintRef     = dp.ReadCell();
    int anchorRef   = dp.ReadCell();
    delete dp;

    int attacker = GetClientOfUserId(attackerUid);
    if (attacker < 1 || attacker > MaxClients) return Plugin_Stop;
    if (!IsClientInGame(attacker)) return Plugin_Stop;

    if (slot < 0 || slot >= STACK_LIMIT) return Plugin_Stop;
    if (g_iSlotSerial[attacker][slot] != serialExp) return Plugin_Stop;

    KillEntRef(hintRef);
    KillEntRef(anchorRef);

    if (g_iSlotHintRef[attacker][slot] == hintRef) g_iSlotHintRef[attacker][slot] = INVALID_ENT_REFERENCE;
    if (g_iSlotAnchorRef[attacker][slot] == anchorRef) g_iSlotAnchorRef[attacker][slot] = INVALID_ENT_REFERENCE;

    return Plugin_Stop;
}

static void KillEntRef(int entRef)
{
    int ent = EntRefToEntIndex(entRef);
    if (ent == INVALID_ENT_REFERENCE || ent <= 0) return;
    if (!IsValidEntity(ent)) return;
    AcceptEntityInput(ent, "Kill");
}

static void ResetChainState(int attacker)
{
    if (attacker < 1 || attacker > MaxClients)
        return;

    g_iChainVictim[attacker] = 0;
    g_iChainDamage[attacker] = 0;
    g_bChainHeadshot[attacker] = false;
    g_fChainLastHitAt[attacker] = 0.0;
}

static void ResetAccumVictimState(int attacker, int victimEnt)
{
    if (attacker < 1 || attacker > MaxClients)
        return;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    int slot = g_iAccumSlot[attacker][victimEnt];
    if (slot >= 0 && slot < STACK_LIMIT && g_iAccumSlotVictim[attacker][slot] == victimEnt)
    {
        g_iAccumSlotVictim[attacker][slot] = 0;
    }

    g_iAccumDamage[attacker][victimEnt] = 0;
    g_iAccumEntRef[attacker][victimEnt] = INVALID_ENT_REFERENCE;
    g_iAccumSlot[attacker][victimEnt] = INVALID_ACCUM_SLOT;
    g_bAccumHeadshot[attacker][victimEnt] = false;
    g_fAccumLastHitAt[attacker][victimEnt] = 0.0;
}

static void ResetAccumState(int attacker)
{
    if (attacker < 1 || attacker > MaxClients)
        return;

    for (int victimEnt = 1; victimEnt <= MAX_TRACKED_ENTITIES; victimEnt++)
    {
        g_iAccumDamage[attacker][victimEnt] = 0;
        g_iAccumEntRef[attacker][victimEnt] = INVALID_ENT_REFERENCE;
        g_iAccumSlot[attacker][victimEnt] = INVALID_ACCUM_SLOT;
        g_bAccumHeadshot[attacker][victimEnt] = false;
        g_fAccumLastHitAt[attacker][victimEnt] = 0.0;
    }

    for (int slot = 0; slot < STACK_LIMIT; slot++)
    {
        g_iAccumSlotVictim[attacker][slot] = 0;
    }
}

static void ResetAccumStateForVictim(int victimEnt)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    for (int attacker = 1; attacker <= MaxClients; attacker++)
    {
        ResetAccumVictimState(attacker, victimEnt);
    }
}

static int FindAccumSlot(int attacker, int victimEnt, float now, float resetDelay)
{
    int slot = g_iAccumSlot[attacker][victimEnt];
    if (slot >= 0 && slot < STACK_LIMIT && g_iAccumSlotVictim[attacker][slot] == victimEnt)
    {
        return slot;
    }

    int oldestSlot = 0;
    float oldestAt = 0.0;
    bool oldestSet = false;

    for (int s = 0; s < STACK_LIMIT; s++)
    {
        int slotVictim = g_iAccumSlotVictim[attacker][s];
        if (slotVictim <= 0)
        {
            g_iAccumSlot[attacker][victimEnt] = s;
            g_iAccumSlotVictim[attacker][s] = victimEnt;
            return s;
        }

        int currentRef = EntIndexToEntRef(slotVictim);
        bool expired = false;
        if (currentRef == INVALID_ENT_REFERENCE)
        {
            expired = true;
        }
        else if (g_iAccumEntRef[attacker][slotVictim] != INVALID_ENT_REFERENCE && g_iAccumEntRef[attacker][slotVictim] != currentRef)
        {
            expired = true;
        }
        else if ((now - g_fAccumLastHitAt[attacker][slotVictim]) > resetDelay)
        {
            expired = true;
        }

        if (expired)
        {
            ResetAccumVictimState(attacker, slotVictim);
            g_iAccumSlot[attacker][victimEnt] = s;
            g_iAccumSlotVictim[attacker][s] = victimEnt;
            return s;
        }

        float slotLastHit = g_fAccumLastHitAt[attacker][slotVictim];
        if (!oldestSet || slotLastHit < oldestAt)
        {
            oldestSet = true;
            oldestAt = slotLastHit;
            oldestSlot = s;
        }
    }

    ResetAccumVictimState(attacker, g_iAccumSlotVictim[attacker][oldestSlot]);
    g_iAccumSlot[attacker][victimEnt] = oldestSlot;
    g_iAccumSlotVictim[attacker][oldestSlot] = victimEnt;
    return oldestSlot;
}

static void ResetPendingDamageForAttacker(int attacker)
{
    if (attacker < 1 || attacker > MaxClients)
        return;

    for (int victimEnt = 1; victimEnt <= MAX_TRACKED_ENTITIES; victimEnt++)
    {
        if (g_hPendingTimer[attacker][victimEnt] != null)
        {
            delete g_hPendingTimer[attacker][victimEnt];
            g_hPendingTimer[attacker][victimEnt] = null;
        }

        g_iPendingDamage[attacker][victimEnt] = 0;
        g_iPendingSerial[attacker][victimEnt] = 0;
        g_bPendingHeadshot[attacker][victimEnt] = false;
        g_bPendingHeadshotCarry[attacker][victimEnt] = false;
        g_fLastHeadshotAt[attacker][victimEnt] = 0.0;
        g_fLastQueuedAt[attacker][victimEnt] = 0.0;
        g_iRecentQueuedDamage[attacker][victimEnt] = 0;
        g_fRecentQueuedAt[attacker][victimEnt] = 0.0;
        g_iShotFatalHealth[attacker][victimEnt] = 0;
        g_iShotFatalSerial[attacker][victimEnt] = 0;
        g_fShotFatalAt[attacker][victimEnt] = 0.0;
        g_fDirectFatalShownAt[attacker][victimEnt] = 0.0;
        g_fLastShownAt[attacker][victimEnt] = 0.0;
    }
}

static void ResetPendingDamageForVictim(int victimEnt)
{
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    for (int attacker = 1; attacker <= MaxClients; attacker++)
    {
        if (g_hPendingTimer[attacker][victimEnt] != null)
        {
            delete g_hPendingTimer[attacker][victimEnt];
            g_hPendingTimer[attacker][victimEnt] = null;
        }

        g_iPendingDamage[attacker][victimEnt] = 0;
        g_iPendingSerial[attacker][victimEnt] = 0;
        g_bPendingHeadshot[attacker][victimEnt] = false;
        g_bPendingHeadshotCarry[attacker][victimEnt] = false;
        g_fLastHeadshotAt[attacker][victimEnt] = 0.0;
        g_fLastQueuedAt[attacker][victimEnt] = 0.0;
        g_iRecentQueuedDamage[attacker][victimEnt] = 0;
        g_fRecentQueuedAt[attacker][victimEnt] = 0.0;
        g_iShotFatalHealth[attacker][victimEnt] = 0;
        g_iShotFatalSerial[attacker][victimEnt] = 0;
        g_fShotFatalAt[attacker][victimEnt] = 0.0;
        g_fDirectFatalShownAt[attacker][victimEnt] = 0.0;
        g_fLastShownAt[attacker][victimEnt] = 0.0;
    }
}

static int ResolveAttackerFromEvent(Event event)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker", 0));
    if (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker))
        return attacker;

    attacker = GetClientOfUserId(event.GetInt("userid", 0));
    if (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker))
        return attacker;

    attacker = event.GetInt("attackerentid", 0);
    if (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker))
        return attacker;

    return 0;
}

static bool EventIsHeadshot(Event event)
{
    if (event.GetBool("headshot", false))
        return true;
    return event.GetInt("hitgroup", 0) == 1;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnable.BoolValue)
        return;

    if (!EventIsHeadshot(event))
        return;

    int attacker = ResolveAttackerFromEvent(event);
    int victim = GetClientOfUserId(event.GetInt("userid", 0));
    if (attacker < 1 || victim < 1)
        return;

    MarkHeadshot(attacker, victim);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnable.BoolValue)
        return;

    int victim = GetClientOfUserId(event.GetInt("userid", 0));
    if (victim < 1 || victim > MaxClients)
        return;
    if (!IsClientInGame(victim) || GetClientTeam(victim) != 3 || IsTankVictim(victim))
        return;

    int attacker = ResolveAttackerFromEvent(event);
    if (!IsHumanSurvivor(attacker) || attacker == victim)
        return;
    if (WasDirectFatalShownRecently(attacker, victim))
        return;

    TryQueueShotFatalFallback(attacker, victim, EventIsHeadshot(event));
}

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnable.BoolValue)
        return;

    int attacker = ResolveAttackerFromEvent(event);
    int victimEnt = event.GetInt("entityid", 0);
    if (attacker < 1 || victimEnt <= 0)
        return;

    StoreVictimPosition(victimEnt);

    bool headshot = EventIsHeadshot(event);
    if (headshot)
    {
        MarkHeadshot(attacker, victimEnt);
    }

    int damageType = event.GetInt("type", 0);
    if ((damageType & (DMG_CLUB | DMG_SLASH)) == 0)
        return;

    int damage = ReadDamage(event);
    if (damage <= 0)
        return;
    if (ShouldBlockTankDamageHint(victimEnt, damage))
        return;

    QueueDamageHintFallback(attacker, victimEnt, damage, headshot);
}

public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnable.BoolValue)
        return;

    int attacker = ResolveAttackerFromEvent(event);
    if (!IsHumanSurvivor(attacker))
        return;

    int victimEnt = event.GetInt("infected_id", 0);
    if (victimEnt <= 0)
        victimEnt = event.GetInt("entityid", 0);
    if (victimEnt <= 0)
        return;
    if (WasDirectFatalShownRecently(attacker, victimEnt))
        return;

    TryQueueShotFatalFallback(attacker, victimEnt, EventIsHeadshot(event));
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnable.BoolValue)
        return;

    int attacker = GetClientOfUserId(event.GetInt("userid", 0));
    if (!IsHumanSurvivor(attacker))
        return;

    int witch = event.GetInt("witchid", 0);
    if (witch <= 0)
        return;
    if (WasDirectFatalShownRecently(attacker, witch))
        return;

    TryQueueShotFatalFallback(attacker, witch, false);
}

static void DisplayResolvedDamageHint(int attacker, int victimEnt, int damage, bool headshot, bool forceAnchor = false)
{
    int displayDamage = damage;
    bool displayHeadshot = headshot;
    int displaySlot = -1;

    int mode = g_cvMode.IntValue;
    if (mode == 1)
    {
        float now = GetGameTime();
        float resetDelay = g_cvChainReset.FloatValue;
        bool resetChain = (g_iChainVictim[attacker] != victimEnt) || ((now - g_fChainLastHitAt[attacker]) > resetDelay);
        if (resetChain)
        {
            ResetChainState(attacker);
        }

        g_iChainVictim[attacker] = victimEnt;
        g_iChainDamage[attacker] += damage;
        g_bChainHeadshot[attacker] = headshot;
        g_fChainLastHitAt[attacker] = now;

        displayDamage = g_iChainDamage[attacker];
        displayHeadshot = g_bChainHeadshot[attacker];
        displaySlot = 0;
    }
    else if (mode == 2)
    {
        float now = GetGameTime();
        float resetDelay = g_cvChainReset.FloatValue;
        int currentRef = EntIndexToEntRef(victimEnt);

        if (g_iAccumEntRef[attacker][victimEnt] != INVALID_ENT_REFERENCE && g_iAccumEntRef[attacker][victimEnt] != currentRef)
        {
            ResetAccumVictimState(attacker, victimEnt);
        }
        else if ((now - g_fAccumLastHitAt[attacker][victimEnt]) > resetDelay)
        {
            ResetAccumVictimState(attacker, victimEnt);
        }

        int slot = FindAccumSlot(attacker, victimEnt, now, resetDelay);
        g_iAccumEntRef[attacker][victimEnt] = currentRef;
        g_iAccumDamage[attacker][victimEnt] += damage;
        g_bAccumHeadshot[attacker][victimEnt] = headshot;
        g_fAccumLastHitAt[attacker][victimEnt] = now;

        displayDamage = g_iAccumDamage[attacker][victimEnt];
        displayHeadshot = g_bAccumHeadshot[attacker][victimEnt];
        displaySlot = slot;
    }

    ShowDamageFollow(attacker, victimEnt, displayDamage, g_cvTimeout.FloatValue, displayHeadshot, displaySlot, forceAnchor);
}

public Action Timer_FlushPendingDamage(Handle timer, any data)
{
    DataPack dp = view_as<DataPack>(data);
    dp.Reset();

    int attacker = dp.ReadCell();
    int victimEnt = dp.ReadCell();
    int serial = dp.ReadCell();
    delete dp;

    if (attacker < 1 || attacker > MaxClients)
        return Plugin_Stop;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return Plugin_Stop;
    if (g_iPendingSerial[attacker][victimEnt] != serial)
        return Plugin_Stop;

    g_hPendingTimer[attacker][victimEnt] = null;

    int damage = g_iPendingDamage[attacker][victimEnt];
    bool headshot = g_bPendingHeadshot[attacker][victimEnt];
    g_iPendingDamage[attacker][victimEnt] = 0;
    g_bPendingHeadshot[attacker][victimEnt] = false;
    ClearShotFatalFallback(attacker, victimEnt);

    if (damage <= 0)
        return Plugin_Stop;
    if (!IsClientInGame(attacker) || IsFakeClient(attacker))
        return Plugin_Stop;
    DisplayResolvedDamageHint(attacker, victimEnt, damage, headshot);
    return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_iSerial[client] = 0;
        for (int s = 0; s < STACK_LIMIT; s++)
        {
            KillEntRef(g_iSlotHintRef[client][s]);
            KillEntRef(g_iSlotAnchorRef[client][s]);
            g_iSlotHintRef[client][s] = INVALID_ENT_REFERENCE;
            g_iSlotAnchorRef[client][s] = INVALID_ENT_REFERENCE;
            g_iSlotSerial[client][s] = 0;
            g_iAccumSlotVictim[client][s] = 0;
        }
        ResetPendingDamageForAttacker(client);
        ResetAccumState(client);
        ResetChainState(client);
    }
}

public Action Command_DmgHintTest(int client, int args)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    int target = client;
    float duration = g_cvTimeout.FloatValue;
    int slot = (g_cvMode.IntValue == 1) ? 0 : -1;
    ShowDamageFollow(client, target, 99, duration, false, slot);
    ReplyToCommand(client, "[dmg_hint] teste enviado");
    return Plugin_Handled;
}
