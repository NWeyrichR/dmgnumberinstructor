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
#define NAME_LEN 48

ConVar g_cvEnable;
ConVar g_cvTimeout;

int g_iSerial[MAXPLAYERS + 1];
int g_iSlotSerial[MAXPLAYERS + 1][STACK_LIMIT];

// refs do env_instructor_hint por slot
int g_iSlotHintRef[MAXPLAYERS + 1][STACK_LIMIT];
int g_iSlotAnchorRef[MAXPLAYERS + 1][STACK_LIMIT];

public Plugin myinfo =
{
    name        = "[L4D2] Damage Instructor Hint",
    author      = "Codex",
    description = "Mostra dano em env_instructor_hint separado por atacante",
    version     = "4.0.0",
    url         = ""
};

public void OnPluginStart()
{
    g_cvEnable  = CreateConVar("sm_dmg_instructor_enable", "0", "0=off 1=on", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTimeout = CreateConVar("sm_dmg_instructor_timeout", "0.65", "Tempo (seg) na tela (float)", FCVAR_NOTIFY, true, 0.05, true, 5.0);
    RegConsoleCmd("sm_dmghinttest", Command_DmgHintTest);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

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

    ShowDamageFollow(attacker, victim, dmg, g_cvTimeout.FloatValue);
}

static void ShowDamageFollow(int attacker, int victimEnt, int dmg, float duration)
{
    // ===== slot 0..4 (limite REAL)
    g_iSerial[attacker]++;
    int slot = g_iSerial[attacker] % STACK_LIMIT;
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
    ConfigureDamageHint(hint, attacker, slot, targetName, caption);

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

static void ConfigureDamageHint(int hint, int attacker, int slot, const char[] targetName, const char[] caption)
{
    char buffer[64];
    char color[16];

    DispatchKeyValue(hint, "hint_target", targetName);
    DispatchKeyValue(hint, "hint_caption", caption);
    DispatchKeyValue(hint, "hint_activator_caption", caption);
    DispatchKeyValue(hint, "hint_static", "0");
    DispatchKeyValue(hint, "hint_timeout", "0.0");
    DispatchKeyValue(hint, "hint_icon_offset", "0");
    DispatchKeyValue(hint, "hint_range", "0");
    DispatchKeyValue(hint, "hint_nooffscreen", "1");
    DispatchKeyValue(hint, "hint_icon_onscreen", "");
    DispatchKeyValue(hint, "hint_icon_offscreen", "");
    DispatchKeyValue(hint, "hint_binding", "");
    DispatchKeyValue(hint, "hint_forcecaption", "0");
    FormatEx(color, sizeof(color), "%d %d %d", 255, 0, 0);
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
    }
}

public Action Command_DmgHintTest(int client, int args)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    int target = client;
    float duration = g_cvTimeout.FloatValue;
    ShowDamageFollow(client, target, 99, duration);
    ReplyToCommand(client, "[dmg_hint] teste enviado");
    return Plugin_Handled;
}
