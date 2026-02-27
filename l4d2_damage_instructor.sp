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

ConVar g_cvEnable;
ConVar g_cvTimeout;
ConVar g_cvAggregateWindow;
ConVar g_cvRange;
ConVar g_cvForceCaption;
ConVar g_cvMode;
ConVar g_cvChainReset;
ConVar g_cvColorNormal;
ConVar g_cvColorHeadshot;

bool g_bRuntimeStarted;
float g_fCfgTimeout;
float g_fCfgAggregateWindow;
int g_iCfgRange;
bool g_bCfgForceCaption;
int g_iCfgMode;
float g_fCfgChainReset;
char g_sCfgColorNormal[32];
char g_sCfgColorHeadshot[32];

int g_iSerial[MAXPLAYERS + 1];
int g_iSlotSerial[MAXPLAYERS + 1][STACK_LIMIT];
int g_iPendingDamage[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iPendingSerial[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
bool g_bPendingHeadshot[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fLastHeadshotAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
Handle g_hPendingTimer[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iChainVictim[MAXPLAYERS + 1][STACK_LIMIT];
int g_iChainDamage[MAXPLAYERS + 1][STACK_LIMIT];
float g_fChainLastHitAt[MAXPLAYERS + 1][STACK_LIMIT];
int g_iTraceIgnoreAttacker;
int g_iTraceIgnoreVictim;

// refs do env_instructor_hint por slot
int g_iSlotHintRef[MAXPLAYERS + 1][STACK_LIMIT];
int g_iSlotAnchorRef[MAXPLAYERS + 1][STACK_LIMIT];

public Plugin myinfo =
{
    name        = "[L4D2] Damage Instructor Hint",
    author      = "Weyrich",
    description = "Mostra dano em env_instructor_hint separado por atacante",
    version     = "4.0.0",
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnable  = CreateConVar("sm_dmg_instructor_enable", "1", "0=off 1=armado; inicia quando houver jogador humano", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTimeout = CreateConVar("sm_dmg_instructor_timeout", "0.65", "Tempo (seg) na tela (float)", FCVAR_NOTIFY, true, 0.05, true, 5.0);
    g_cvAggregateWindow = CreateConVar("sm_dmg_instructor_aggregate_window", "0.03", "Janela para somar pellets/ticks em um numero", FCVAR_NOTIFY, true, 0.0, true, 0.25);
    g_cvRange = CreateConVar("sm_dmg_instructor_range", "3000", "Distancia maxima para ver o hint em unidades", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvForceCaption = CreateConVar("sm_dmg_instructor_forcecaption", "1", "1=forca caption para aparecer a longa distancia", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMode = CreateConVar("sm_dmg_instructor_mode", "0", "0=modo atual empilhado, 1=modo acumulado continuo", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvChainReset = CreateConVar("sm_dmg_instructor_chain_reset", "1.0", "Tempo sem dano para resetar a soma do modo 1", FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_cvColorNormal = CreateConVar("sm_dmg_instructor_color_normal", "255 0 0", "Cor RGB do dano normal no formato: R G B");
    g_cvColorHeadshot = CreateConVar("sm_dmg_instructor_color_headshot", "255 140 0", "Cor RGB do headshot no formato: R G B");
    HookConVarChange(g_cvEnable, ConVarChanged_Settings);
    HookConVarChange(g_cvTimeout, ConVarChanged_Settings);
    HookConVarChange(g_cvAggregateWindow, ConVarChanged_Settings);
    HookConVarChange(g_cvRange, ConVarChanged_Settings);
    HookConVarChange(g_cvForceCaption, ConVarChanged_Settings);
    HookConVarChange(g_cvMode, ConVarChanged_Settings);
    HookConVarChange(g_cvChainReset, ConVarChanged_Settings);
    HookConVarChange(g_cvColorNormal, ConVarChanged_Settings);
    HookConVarChange(g_cvColorHeadshot, ConVarChanged_Settings);
    RegConsoleCmd("sm_dmghinttest", Command_DmgHintTest);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);

    AutoExecConfig(true, "l4d2_damage_instructor");

    // late load
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i)) OnClientPutInServer(i);

    RefreshRuntimeState();
}

public void OnClientPutInServer(int client)
{
    g_iSerial[client] = 0;
    for (int s = 0; s < STACK_LIMIT; s++)
    {
        g_iSlotSerial[client][s] = 0;
        g_iSlotHintRef[client][s] = INVALID_ENT_REFERENCE;
        g_iSlotAnchorRef[client][s] = INVALID_ENT_REFERENCE;
    }
    ResetChainState(client);

    // hook de dano em players também
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Any);

    RefreshRuntimeState();

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
    ResetChainState(client);
    g_iSerial[client] = 0;
    RefreshRuntimeState();
}

public void OnMapStart()
{
    g_bRuntimeStarted = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_iSerial[client] = 0;
        for (int s = 0; s < STACK_LIMIT; s++)
        {
            g_iSlotSerial[client][s] = 0;
            g_iSlotHintRef[client][s] = INVALID_ENT_REFERENCE;
            g_iSlotAnchorRef[client][s] = INVALID_ENT_REFERENCE;
        }
        ResetPendingDamageForAttacker(client);
        ResetChainState(client);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    // common infected / witch
    if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
    {
        SDKHook(entity, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Any);
    }
}

public void ConVarChanged_Settings(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvEnable)
    {
        RefreshRuntimeState();
        return;
    }

    if (g_bRuntimeStarted)
        LoadRuntimeConfig();
}

static bool HasAnyHumanPlayer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;

        return true;
    }

    return false;
}

static void LoadRuntimeConfig()
{
    g_fCfgTimeout = g_cvTimeout.FloatValue;
    g_fCfgAggregateWindow = g_cvAggregateWindow.FloatValue;
    g_iCfgRange = g_cvRange.IntValue;
    g_bCfgForceCaption = g_cvForceCaption.BoolValue;
    g_iCfgMode = g_cvMode.IntValue;
    g_fCfgChainReset = g_cvChainReset.FloatValue;
    g_cvColorNormal.GetString(g_sCfgColorNormal, sizeof(g_sCfgColorNormal));
    g_cvColorHeadshot.GetString(g_sCfgColorHeadshot, sizeof(g_sCfgColorHeadshot));
}

static void StartRuntime()
{
    if (g_bRuntimeStarted)
        return;

    LoadRuntimeConfig();
    g_bRuntimeStarted = true;
}

static void StopRuntime()
{
    if (!g_bRuntimeStarted)
        return;

    g_bRuntimeStarted = false;

    for (int client = 1; client <= MaxClients; client++)
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
        ResetChainState(client);
        g_iSerial[client] = 0;
    }
}

static void RefreshRuntimeState()
{
    if (!g_cvEnable.BoolValue || !HasAnyHumanPlayer())
    {
        StopRuntime();
        return;
    }

    StartRuntime();
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

static bool GetEntityCenterPos(int entity, float outPos[3], float zOffset)
{
    if (entity <= 0)
        return false;

    if (entity <= MaxClients)
    {
        if (!IsClientInGame(entity))
            return false;

        GetClientAbsOrigin(entity, outPos);
        outPos[2] += zOffset;
        return true;
    }

    if (!IsValidEntity(entity))
        return false;

    if (HasEntProp(entity, Prop_Data, "m_vecAbsOrigin"))
    {
        GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", outPos);
    }
    else if (HasEntProp(entity, Prop_Send, "m_vecOrigin"))
    {
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", outPos);
    }
    else
    {
        return false;
    }

    outPos[2] += zOffset;
    return true;
}

public bool TraceFilter_IgnoreAttackerVictim(int entity, int mask, any data)
{
    return (entity != g_iTraceIgnoreAttacker && entity != g_iTraceIgnoreVictim);
}

static bool GetHintAnchorPos(int attacker, int victimEnt, int slot, float outPos[3])
{
    float height = (victimEnt <= MaxClients) ? 50.0 : 28.0;
    if (!GetEntityCenterPos(victimEnt, outPos, height))
        return false;

    float eye[3];
    GetClientEyePosition(attacker, eye);

    float toEye[3];
    MakeVectorFromPoints(outPos, eye, toEye);
    float dist = GetVectorLength(toEye);
    if (dist > 0.1)
    {
        NormalizeVector(toEye, toEye);

        float towardEye = (dist < 120.0) ? 14.0 : 8.0;
        outPos[0] += toEye[0] * towardEye;
        outPos[1] += toEye[1] * towardEye;

        if (dist < 120.0)
            outPos[2] += 12.0;
    }

    if (slot >= 0)
    {
        float ang[3], fwd[3], right[3], up[3];
        GetClientEyeAngles(attacker, ang);
        GetAngleVectors(ang, fwd, right, up);

        float side = (float(slot) - ((float(STACK_LIMIT) - 1.0) * 0.5)) * 5.0;
        outPos[0] += right[0] * side;
        outPos[1] += right[1] * side;
        outPos[2] += float(slot) * 2.0;
    }

    return true;
}

static bool IsHintOccluded(int attacker, int victimEnt, const float targetPos[3])
{
    float eye[3];
    GetClientEyePosition(attacker, eye);

    g_iTraceIgnoreAttacker = attacker;
    g_iTraceIgnoreVictim = victimEnt;

    Handle trace = TR_TraceRayFilterEx(eye, targetPos, MASK_SHOT, RayType_EndPoint, TraceFilter_IgnoreAttackerVictim, 0);
    bool blocked = TR_DidHit(trace);
    delete trace;

    g_iTraceIgnoreAttacker = 0;
    g_iTraceIgnoreVictim = 0;
    return blocked;
}

static int CreateHintAnchor(int attacker, int victimEnt, int slot, int serialNow, const char[] parentName, char[] anchorName, int anchorNameLen)
{
    float anchorPos[3];
    if (!GetHintAnchorPos(attacker, victimEnt, slot, anchorPos))
        return -1;

    int anchor = CreateEntityByName("info_target_instructor_hint");
    if (anchor == -1)
        return -1;

    Format(anchorName, anchorNameLen, "dmg_anchor_%d_%d_%d", attacker, slot, serialNow);
    DispatchKeyValue(anchor, "targetname", anchorName);
    DispatchSpawn(anchor);
    TeleportEntity(anchor, anchorPos, NULL_VECTOR, NULL_VECTOR);

    SetVariantString(parentName);
    AcceptEntityInput(anchor, "SetParent");
    return anchor;
}

public void OnTakeDamagePost_Any(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    if (!g_bRuntimeStarted) return;
    if (damage <= 0.0) return;

    // atacante precisa ser player
    if (attacker < 1 || attacker > MaxClients) return;
    if (!IsClientInGame(attacker) || IsFakeClient(attacker)) return;

    // vítima precisa existir (player ou entity)
    if (victim <= 0 || !IsValidEntity(victim)) return;

    int dmg = RoundToNearest(damage);
    if (dmg <= 0) return;
    if (ShouldBlockTankDamageHint(victim, dmg)) return;

    float previewPos[3];
    if (!GetHintAnchorPos(attacker, victim, -1, previewPos)) return;
    if (IsHintOccluded(attacker, victim, previewPos)) return;

    QueueDamageHint(attacker, victim, dmg);
}

static void ShowDamageFollow(int attacker, int victimEnt, int dmg, float duration, bool headshot = false, int forcedSlot = -1)
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
    Format(targetName, sizeof(targetName), "dmg_target_%d", victimEnt);
    DispatchKeyValue(victimEnt, "targetname", targetName);

    char hintTargetName[NAME_LEN];
    strcopy(hintTargetName, sizeof(hintTargetName), targetName);

    char anchorName[NAME_LEN];
    int anchor = CreateHintAnchor(attacker, victimEnt, slot, serialNow, targetName, anchorName, sizeof(anchorName));
    if (anchor != -1)
    {
        strcopy(hintTargetName, sizeof(hintTargetName), anchorName);
    }

    char caption[16];
    Format(caption, sizeof(caption), "%d", dmg);
    ConfigureDamageHint(hint, attacker, slot, hintTargetName, caption, headshot);

    DispatchSpawn(hint);
    AcceptEntityInput(hint, "ShowHint");

    g_iSlotHintRef[attacker][slot] = EntIndexToEntRef(hint);
    g_iSlotAnchorRef[attacker][slot] = (anchor != -1) ? EntIndexToEntRef(anchor) : INVALID_ENT_REFERENCE;

    // timer mata ambos no tempo exato
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(attacker));
    dp.WriteCell(slot);
    dp.WriteCell(serialNow);
    dp.WriteCell(EntIndexToEntRef(hint));
    dp.WriteCell(g_iSlotAnchorRef[attacker][slot]);
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
    IntToString(g_iCfgRange, buffer, sizeof(buffer));
    DispatchKeyValue(hint, "hint_range", buffer);
    DispatchKeyValue(hint, "hint_nooffscreen", "1");
    DispatchKeyValue(hint, "hint_icon_onscreen", "");
    DispatchKeyValue(hint, "hint_icon_offscreen", "");
    DispatchKeyValue(hint, "hint_binding", "");
    DispatchKeyValue(hint, "hint_forcecaption", g_bCfgForceCaption ? "1" : "0");
    if (headshot)
        strcopy(color, sizeof(color), g_sCfgColorHeadshot);
    else
        strcopy(color, sizeof(color), g_sCfgColorNormal);
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

    g_iPendingDamage[attacker][victimEnt] += damage;

    float now = GetGameTime();
    if ((now - g_fLastHeadshotAt[attacker][victimEnt]) <= 0.10)
    {
        g_bPendingHeadshot[attacker][victimEnt] = true;
    }

    if (g_hPendingTimer[attacker][victimEnt] != null)
    {
        return;
    }

    g_iPendingSerial[attacker][victimEnt]++;

    float window = g_fCfgAggregateWindow;
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

static void MarkHeadshot(int attacker, int victimEnt)
{
    if (attacker < 1 || attacker > MaxClients)
        return;
    if (victimEnt <= 0 || victimEnt > MAX_TRACKED_ENTITIES)
        return;

    g_fLastHeadshotAt[attacker][victimEnt] = GetGameTime();
    if (g_iPendingDamage[attacker][victimEnt] > 0)
    {
        g_bPendingHeadshot[attacker][victimEnt] = true;
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

    for (int slot = 0; slot < STACK_LIMIT; slot++)
    {
        g_iChainVictim[attacker][slot] = 0;
        g_iChainDamage[attacker][slot] = 0;
        g_fChainLastHitAt[attacker][slot] = 0.0;
    }
}

static int FindChainSlot(int attacker, int victimEnt, float now)
{
    int freeSlot = -1;
    int expiredSlot = -1;
    int oldestSlot = 0;
    float oldestTime = 0.0;

    for (int slot = 0; slot < STACK_LIMIT; slot++)
    {
        if (g_iChainVictim[attacker][slot] == victimEnt)
        {
            if ((now - g_fChainLastHitAt[attacker][slot]) <= g_fCfgChainReset)
                return slot;

            expiredSlot = slot;
            break;
        }

        if (g_iChainVictim[attacker][slot] == 0)
        {
            if (freeSlot == -1)
                freeSlot = slot;
            continue;
        }

        if ((now - g_fChainLastHitAt[attacker][slot]) > g_fCfgChainReset)
        {
            if (expiredSlot == -1)
                expiredSlot = slot;
        }

        if (slot == 0 || g_fChainLastHitAt[attacker][slot] < oldestTime)
        {
            oldestTime = g_fChainLastHitAt[attacker][slot];
            oldestSlot = slot;
        }
    }

    if (expiredSlot != -1)
        return expiredSlot;
    if (freeSlot != -1)
        return freeSlot;
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
        g_fLastHeadshotAt[attacker][victimEnt] = 0.0;
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
        g_fLastHeadshotAt[attacker][victimEnt] = 0.0;
    }
}

static int ResolveAttackerFromEvent(Event event)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker", 0));
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
    if (!g_bRuntimeStarted)
        return;

    if (!EventIsHeadshot(event))
        return;

    int attacker = ResolveAttackerFromEvent(event);
    int victim = GetClientOfUserId(event.GetInt("userid", 0));
    if (attacker < 1 || victim < 1)
        return;

    MarkHeadshot(attacker, victim);
}

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bRuntimeStarted)
        return;

    if (!EventIsHeadshot(event))
        return;

    int attacker = ResolveAttackerFromEvent(event);
    int victimEnt = event.GetInt("entityid", 0);
    if (attacker < 1 || victimEnt <= 0)
        return;

    MarkHeadshot(attacker, victimEnt);
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

    if (damage <= 0)
        return Plugin_Stop;
    if (!IsClientInGame(attacker) || IsFakeClient(attacker))
        return Plugin_Stop;
    if (victimEnt > MaxClients && !IsValidEntity(victimEnt))
        return Plugin_Stop;
    if (victimEnt >= 1 && victimEnt <= MaxClients && !IsClientInGame(victimEnt))
        return Plugin_Stop;

    int displayDamage = damage;
    bool displayHeadshot = headshot;
    int displaySlot = -1;

    if (g_iCfgMode == 1)
    {
        float now = GetGameTime();
        int chainSlot = FindChainSlot(attacker, victimEnt, now);
        bool sameVictim = (g_iChainVictim[attacker][chainSlot] == victimEnt);
        bool chainAlive = sameVictim && ((now - g_fChainLastHitAt[attacker][chainSlot]) <= g_fCfgChainReset);

        if (!chainAlive)
        {
            g_iChainVictim[attacker][chainSlot] = victimEnt;
            g_iChainDamage[attacker][chainSlot] = 0;
        }

        g_iChainDamage[attacker][chainSlot] += damage;
        g_fChainLastHitAt[attacker][chainSlot] = now;

        displayDamage = g_iChainDamage[attacker][chainSlot];
        displayHeadshot = headshot;
        displaySlot = chainSlot;
    }

    ShowDamageFollow(attacker, victimEnt, displayDamage, g_fCfgTimeout, displayHeadshot, displaySlot);
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
        }
        ResetPendingDamageForAttacker(client);
        ResetChainState(client);
    }
}

public Action Command_DmgHintTest(int client, int args)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;
    if (!g_bRuntimeStarted)
    {
        ReplyToCommand(client, "[dmg_hint] plugin ainda nao iniciou");
        return Plugin_Handled;
    }

    int target = client;
    float duration = g_fCfgTimeout;
    ShowDamageFollow(client, target, 99, duration, false, g_iCfgMode == 1 ? 0 : -1);
    ReplyToCommand(client, "[dmg_hint] teste enviado");
    return Plugin_Handled;
}
