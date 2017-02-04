#include <sourcemod>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define MIN_PLAYERS 2

bool g_bWarmup = false;
int g_Warmup = 0;
ConVar g_CVar_sm_warmuptime;
ConVar g_CVar_sm_warmupratio;

bool g_bRoundEnded = false;
bool g_bZombieSpawned = false;
bool g_bIgnoreGameStart = false;
int g_TeamChangeQueue[MAXPLAYERS + 1] = { -1, ... };

public Plugin myinfo =
{
	name = "TeamManager",
	author = "BotoX",
	description = "",
	version = "1.0",
	url = "https://github.com/CSSZombieEscape/sm-plugins/tree/master/TeamManager"
};

public void OnPluginStart()
{
	AddCommandListener(OnJoinTeamCommand, "jointeam");
	HookEvent("round_start", OnRoundStart, EventHookMode_Pre);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

	g_CVar_sm_warmuptime = CreateConVar("sm_warmuptime", "10", "Warmup timer.", 0, true, 0.0, true, 60.0);
	g_CVar_sm_warmupratio = CreateConVar("sm_warmupratio", "0.60", "Ratio of connected players that need to be in game to start warmup timer.", 0, true, 0.0, true, 1.0);

	/* Late load */
	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client))
			continue;
	}

	AutoExecConfig(true, "plugin.TeamManager");
}

public void OnMapStart()
{
	g_bWarmup = false;
	g_Warmup = 0;
	if(g_CVar_sm_warmuptime.IntValue > 0 || g_CVar_sm_warmupratio.FloatValue > 0.0)
	{
		g_bWarmup = true;
		CreateTimer(1.0, OnWarmupTimer, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action OnWarmupTimer(Handle timer)
{
	if(g_CVar_sm_warmupratio.FloatValue > 0.0)
	{
		int ClientsConnected = GetClientCount(false);
		int ClientsInGame = GetClientCount(true);
		int ClientsNeeded = RoundToCeil(float(ClientsConnected) * g_CVar_sm_warmupratio.FloatValue);
		ClientsNeeded = ClientsNeeded > MIN_PLAYERS ? ClientsNeeded : MIN_PLAYERS;

		if(ClientsInGame < ClientsNeeded)
		{
			g_Warmup = 0;
			PrintCenterTextAll("Warmup: Waiting for %d more players to join.", ClientsNeeded - ClientsInGame);
			return Plugin_Continue;
		}
	}

	if(g_Warmup >= g_CVar_sm_warmuptime.IntValue)
	{
		g_bWarmup = false;
		g_Warmup = 0;
		CS_TerminateRound(3.0, CSRoundEnd_GameStart, false);
		return Plugin_Stop;
	}

	PrintCenterTextAll("Warmup: %d", g_CVar_sm_warmuptime.IntValue - g_Warmup);
	g_Warmup++;

	return Plugin_Continue;
}

public void OnClientConnected(int client)
{
	g_TeamChangeQueue[client] = -1;
}

public Action OnJoinTeamCommand(int client, const char[] command, int argc)
{
	if(client < 1 || client >= MaxClients || !IsClientInGame(client))
		return Plugin_Continue;

	char sArg[8];
	GetCmdArg(1, sArg, sizeof(sArg));

	int CurrentTeam = GetClientTeam(client);
	int NewTeam = StringToInt(sArg);

	if(NewTeam < CS_TEAM_NONE || NewTeam > CS_TEAM_CT)
		return Plugin_Handled;

	if(g_bRoundEnded)
	{
		if(NewTeam == CS_TEAM_T || NewTeam == CS_TEAM_NONE)
			NewTeam = CS_TEAM_CT;

		if(NewTeam == CurrentTeam)
		{
			if(g_TeamChangeQueue[client] != -1)
			{
				g_TeamChangeQueue[client] = -1;
				PrintCenterText(client, "Team change request canceled.");
			}
			return Plugin_Handled;
		}

		g_TeamChangeQueue[client] = NewTeam;
		PrintCenterText(client, "You will be placed in the selected team shortly.");
		return Plugin_Handled;
	}

	if(!g_bZombieSpawned)
	{
		if(NewTeam == CS_TEAM_T || NewTeam == CS_TEAM_NONE)
			NewTeam = CS_TEAM_CT;
	}
	else if(NewTeam == CS_TEAM_NONE)
		NewTeam = CS_TEAM_T;

	if(NewTeam == CurrentTeam)
		return Plugin_Handled;

	ChangeClientTeam(client, NewTeam);
	return Plugin_Handled;
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = false;
	g_bZombieSpawned = false;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client))
			continue;

		int CurrentTeam = GetClientTeam(client);
		int NewTeam = CS_TEAM_CT;

		if(g_TeamChangeQueue[client] != -1)
		{
			NewTeam = g_TeamChangeQueue[client];
			g_TeamChangeQueue[client] = -1;
		}
		else if(CurrentTeam <= CS_TEAM_SPECTATOR)
			continue;

		if(NewTeam == CurrentTeam)
			continue;

		if(NewTeam >= CS_TEAM_T)
			CS_SwitchTeam(client, NewTeam);
		else
			ChangeClientTeam(client, NewTeam);

		if(NewTeam >= CS_TEAM_T && !IsPlayerAlive(client))
			CS_RespawnPlayer(client);
	}
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = true;
	g_bZombieSpawned = false;
}

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	if(reason == CSRoundEnd_GameStart && g_bIgnoreGameStart)
	{
		g_bIgnoreGameStart = false;

		return Plugin_Handled;
	}

	if(g_bWarmup)
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn)
{
	if(g_bWarmup)
		return Plugin_Handled;

	if(motherInfect)
	{
		g_bIgnoreGameStart = true;
		g_bZombieSpawned = true;
	}

	return Plugin_Continue;
}
