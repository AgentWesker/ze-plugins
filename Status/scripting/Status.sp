#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

ConVar g_Cvar_HostIP;
ConVar g_Cvar_HostPort;
ConVar g_Cvar_HostName;
ConVar g_Cvar_HostTags;

Handle g_hPlayerList[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
bool g_bDataAvailable = false;

public Plugin myinfo =
{
	name         = "Status Fixer",
	author       = "zaCade + BotoX + Obus",
	description  = "Fixes the 'status' command",
	version      = "1.3",
	url          = "https://github.com/CSSZombieEscape/sm-plugins/tree/master/Status/"
};

public void OnPluginStart()
{
	g_Cvar_HostIP   = FindConVar("hostip");
	g_Cvar_HostPort = FindConVar("hostport");
	g_Cvar_HostName = FindConVar("hostname");
	g_Cvar_HostTags = FindConVar("sv_tags");

	AddCommandListener(Command_Status, "status");
}

public Action Command_Status(int client, const char[] command, int args)
{
	if(client)
	{
		if(g_hPlayerList[client] != INVALID_HANDLE)
			return Plugin_Handled;

		static char sServerName[128];
		static char sServerTags[128];
		static char sServerAdress[128];

		int iServerIP   = g_Cvar_HostIP.IntValue;
		int iServerPort = g_Cvar_HostPort.IntValue;

		g_Cvar_HostName.GetString(sServerName, sizeof(sServerName));
		g_Cvar_HostTags.GetString(sServerTags, sizeof(sServerTags));

		Format(sServerAdress, sizeof(sServerAdress), "%d.%d.%d.%d:%d", iServerIP >>> 24 & 255, iServerIP >>> 16 & 255, iServerIP >>> 8 & 255, iServerIP & 255, iServerPort);

		static char sMapName[128];
		GetCurrentMap(sMapName, sizeof(sMapName));

		float fPosition[3];
		GetClientAbsOrigin(client, fPosition);

		int iRealClients;
		int iFakeClients;
		int iTotalClients;

		for(int player = 1; player <= MaxClients; player++)
		{
			if(IsClientConnected(player))
			{
				iTotalClients++;

				if(IsFakeClient(player))
					iFakeClients++;
				else
					iRealClients++;
			}
		}

		static char sSendBuffer[989];
		int iBufLength = 0;
		Format(sSendBuffer, sizeof(sSendBuffer), "hostname: %s\n", sServerName);
		Format(sSendBuffer, sizeof(sSendBuffer), "%stickrate: %d\n", sSendBuffer, RoundToZero(1.0 / GetTickInterval()));
		Format(sSendBuffer, sizeof(sSendBuffer), "%sudp/ip  : %s\n", sSendBuffer, sServerAdress);
		Format(sSendBuffer, sizeof(sSendBuffer), "%smap     : %s at: %.0f x, %.0f y, %.0f z\n", sSendBuffer, sMapName, fPosition[0], fPosition[1], fPosition[2]);
		Format(sSendBuffer, sizeof(sSendBuffer), "%stags    : %s\n", sSendBuffer, sServerTags);
		Format(sSendBuffer, sizeof(sSendBuffer), "%s%edicts : %d/%d/%d (used/max/free)\n", sSendBuffer, GetEntityCount(), GetMaxEntities(), GetMaxEntities() - GetEntityCount());
		Format(sSendBuffer, sizeof(sSendBuffer), "%splayers : %d %s | %d %s (%d/%d)\n", sSendBuffer, iRealClients, Multiple(iRealClients) ? "humans" : "human", iFakeClients, Multiple(iFakeClients) ? "bots" : "bot", iTotalClients, MaxClients);
		Format(sSendBuffer, sizeof(sSendBuffer), "%s# %8s %40s %24s %12s %4s %4s %s %s", sSendBuffer, "userid", "name", "uniqueid", "connected", "ping", "loss", "state", "addr");

		g_hPlayerList[client] = CreateArray(ByteCountToCells(989));

		PushArrayString(g_hPlayerList[client], sSendBuffer);
		g_bDataAvailable = true;
		sSendBuffer[0] = 0;

		for(int player = 1; player <= MaxClients; player++)
		{
			if(IsClientConnected(player))
			{
				static char sPlayerID[8];
				static char sPlayerName[40];
				char sPlayerAuth[24];
				char sPlayerTime[12];
				char sPlayerPing[4];
				char sPlayerLoss[4];
				static char sPlayerState[16];
				char sPlayerAddr[16];

				Format(sPlayerID, sizeof(sPlayerID), "%d", GetClientUserId(player));
				Format(sPlayerName, sizeof(sPlayerName), "\"%N\"", player);

				if(!GetClientAuthId(player, AuthId_Steam2, sPlayerAuth, sizeof(sPlayerAuth)))
					Format(sPlayerAuth, sizeof(sPlayerAuth), "STEAM_ID_PENDING");

				if(!IsFakeClient(player))
				{
					int iHours   = RoundToFloor((GetClientTime(player) / 3600));
					int iMinutes = RoundToFloor((GetClientTime(player) - (iHours * 3600)) / 60);
					int iSeconds = RoundToFloor((GetClientTime(player) - (iHours * 3600)) - (iMinutes * 60));

					if (iHours)
						Format(sPlayerTime, sizeof(sPlayerTime), "%d:%02d:%02d", iHours, iMinutes, iSeconds);
					else
						Format(sPlayerTime, sizeof(sPlayerTime), "%d:%02d", iMinutes, iSeconds);

					Format(sPlayerPing, sizeof(sPlayerPing), "%d", RoundFloat(GetClientLatency(player, NetFlow_Outgoing) * 800));
					Format(sPlayerLoss, sizeof(sPlayerLoss), "%d", RoundFloat(GetClientAvgLoss(player, NetFlow_Outgoing) * 100));
				}

				if(IsClientInGame(player))
					Format(sPlayerState, sizeof(sPlayerState), "active");
				else
					Format(sPlayerState, sizeof(sPlayerState), "spawning");

				if(GetAdminFlag(GetUserAdmin(client), Admin_Ban))
					GetClientIP(player, sPlayerAddr, sizeof(sPlayerAddr));

				static char sFormatted[128];
				Format(sFormatted, sizeof(sFormatted), "# %8s %40s %24s %12s %4s %4s %s %s\n", sPlayerID, sPlayerName, sPlayerAuth, sPlayerTime, sPlayerPing, sPlayerLoss, sPlayerState, sPlayerAddr);

				int iFormattedLength = strlen(sFormatted);
				if(iBufLength + iFormattedLength >= 989)
				{
					sSendBuffer[iBufLength - 1] = 0;
					PushArrayString(g_hPlayerList[client], sSendBuffer);
					sSendBuffer[0] = 0;
					iBufLength = 0;

					StrCat(sSendBuffer, sizeof(sSendBuffer), sFormatted);
					iBufLength += iFormattedLength;
				}
				else
				{
					StrCat(sSendBuffer, sizeof(sSendBuffer), sFormatted);
					iBufLength += iFormattedLength;
				}
			}
		}

		if(iBufLength)
		{
			sSendBuffer[iBufLength - 1] = 0;
			PushArrayString(g_hPlayerList[client], sSendBuffer);
		}

		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnGameFrame()
{
	if(!g_bDataAvailable)
		return;

	bool bGotData = false;
	for(int client = 0; client < MAXPLAYERS + 1; client++)
	{
		if(g_hPlayerList[client] == INVALID_HANDLE)
			continue;

		if(!IsClientInGame(client) || !GetArraySize(g_hPlayerList[client]))
		{
			CloseHandle(g_hPlayerList[client]);
			g_hPlayerList[client] = INVALID_HANDLE;
			continue;
		}

		static char sBuffer[989];
		GetArrayString(g_hPlayerList[client], 0, sBuffer, sizeof(sBuffer));
		RemoveFromArray(g_hPlayerList[client], 0);

		PrintToConsole(client, sBuffer);
		bGotData = true;
	}

	if(!bGotData)
		g_bDataAvailable = false;
}

stock bool Multiple(int num)
{
	return (!num || num > 1);
}
