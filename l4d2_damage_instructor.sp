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

int g_iSerial[MAXPLAYERS + 1];
int g_iSlotSerial[MAXPLAYERS + 1][STACK_LIMIT];
int g_iPendingDamage[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iPendingSerial[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
bool g_bPendingHeadshot[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
float g_fLastHeadshotAt[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
Handle g_hPendingTimer[MAXPLAYERS + 1][MAX_TRACKED_ENTITIES + 1];
int g_iChainVictim[MAXPLAYERS + 1];
int g_iChainDamage[MAXPLAYERS + 1];
bool g_bChainHeadshot[MAXPLAYERS + 1];
float g_fChainLastHitAt[MAXPLAYERS + 1];

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
    g_cvEnable  = CreateConVar("sm_dmg_instructor_enable", "0", "0=off 1=on", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTimeout = CreateConVar("sm_dmg_instructor_timeout", "0.65", "Tempo (seg) na tela (float)", FCVAR_NOTIFY, true, 0.05, true, 5.0);
    g_cvAggregateWindow = CreateConVar("sm_dmg_instructor_aggregate_window", "0.03", "Janela para somar pellets/ticks em um numero", FCVAR_NOTIFY, true, 0.0, true, 0.25);
    g_cvRange = CreateConVar("sm_dmg_instructor_range", "3000", "Distancia maxima para ver o hint em unidades", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvForceCaption = CreateConVar("sm_dmg_instructor_forcecaption", "1", "1=forca caption para aparecer a longa distancia", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMode = CreateConVar("sm_dmg_instructor_mode", "0", "0=modo atual empilhado, 1=modo acumulado continuo", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvChainReset = CreateConVar("sm_dmg_instructor_chain_reset", "1.0", "Tempo sem dano para resetar a soma do modo 1", FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_cvColorNormal = CreateConVar("sm_dmg_instructor_color_normal", "255 0 0", "Cor RGB do dano normal no formato: R G B");
    g_cvColorHeadshot = CreateConVar("sm_dmg_instructor_color_headshot", "255 140 0", "Cor RGB do headshot no formato: R G B");
    RegConsoleCmd("sm_dmghinttest", Command_DmgHintTest);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);

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
    }
    ResetChainState(client);

    // hook de dano em players também
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

public void OnTakeDamagePost_Any(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    if (!g_cvEnable.BoolValue) return;
    if (damage <= 0.0) return;

    // atacante precisa ser player
    if (attacker < 1 || attacker > MaxClients) return;
    if (!IsClientInGame(attacker) || IsFakeClient(attacker)) return;

    // vítima precisa existir (player ou entity)
    if (victim <= 0 || !IsValidEntity(victim)) return;

    int dmg = RoundToNearest(damage);
    if (dmg <= 0) return;
    if (ShouldBlockTankDamageHint(victim, dmg)) return;

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

    char caption[16];
    Format(caption, sizeof(caption), "%d", dmg);
    ConfigureDamageHint(hint, attacker, slot, targetName, caption, headshot);

    DispatchSpawn(hint);
    AcceptEntityInput(hint, "ShowHint");

    g_iSlotHintRef[attacker][slot] = EntIndexToEntRef(hint);
    g_iSlotAnchorRef[attacker][slot] = INVALID_ENT_REFERENCE;

    // timer mata ambos no tempo exato
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(attacker));
    dp.WriteCell(slot);
    dp.WriteCell(serialNow);
    dp.WriteCell(EntIndexToEntRef(hint));
    dp.WriteCell(INVALID_ENT_REFERENCE);
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

    g_iPendingDamage[attacker][victimEnt] += damage;

    float now = GetGameTime();
    if ((now - g_fLastHeadshotAt[attacker][victimEnt]) <= 0.10)
    {
        g_bPendingHeadshot[attacker][victimEnt] = true;
    }

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

    g_iChainVictim[attacker] = 0;
    g_iChainDamage[attacker] = 0;
    g_bChainHeadshot[attacker] = false;
    g_fChainLastHitAt[attacker] = 0.0;
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

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnable.BoolValue)
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

    if (g_cvMode.IntValue == 1)
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
        if (headshot)
        {
            g_bChainHeadshot[attacker] = true;
        }
        g_fChainLastHitAt[attacker] = now;

        displayDamage = g_iChainDamage[attacker];
        displayHeadshot = g_bChainHeadshot[attacker];
        displaySlot = 0;
    }

    ShowDamageFollow(attacker, victimEnt, displayDamage, g_cvTimeout.FloatValue, displayHeadshot, displaySlot);
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

    int target = client;
    float duration = g_cvTimeout.FloatValue;
    ShowDamageFollow(client, target, 99, duration, false, g_cvMode.IntValue == 1 ? 0 : -1);
    ReplyToCommand(client, "[dmg_hint] teste enviado");
    return Plugin_Handled;
}
