#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define SKINS_CONFIG "configs/weapon_skins.cfg"
#define SHOTS_CONFIG "configs/skin_shots.cfg"
#define QUEUE_FILE "addons/sourcemod/data/skin_shots_queue.txt"
#define LOG_FILE "addons/sourcemod/data/skin_shots.log"
#define SCREENSHOTS_DIR "screenshots"
#define OUTPUT_DIR "screenshots/skinshots"
#define MAX_SHOT_RETRIES 20
#define EF_DIMLIGHT 4
#define EF_BONEMERGE 1
#define EF_BONEMERGE_FASTCULL 128
#define EF_PARENT_ANIMATES 512
#define DEFAULT_ACTOR_MODEL "models/survivors/survivor_mechanic.mdl"
#define PROP_NAME "skin_shots_prop"

enum struct WeaponModels
{
	char weapon[64];
	char viewModel[PLATFORM_MAX_PATH];
	char worldModel[PLATFORM_MAX_PATH];
	int viewModelIndex;
	int worldModelIndex;
}

enum struct Skin
{
	char id[64];
	char weapon[64];
	int family;
}

enum struct Scene
{
	float origin[3];
	float angles[3];
	float targetOrigin[3];
	float targetAngles[3];
	float meleeAngles[3];
	bool hasMeleeAngles;
	bool viewModel;
	int fov;
	char type[16];
}

ArrayList g_hModels;
ArrayList g_hSkins;
ArrayList g_hJobs;
ArrayList g_hSceneOrder;
StringMap g_hScenes;
StringMap g_hAnimations;
StringMap g_hFraming;

int g_iJob = -1;
int g_iPosedSurvivor = INVALID_ENT_REFERENCE;
int g_iPosedWeapon = INVALID_ENT_REFERENCE;
char g_sActorModel[PLATFORM_MAX_PATH] = DEFAULT_ACTOR_MODEL;
int g_iRetries;
int g_iActor = -1;
int g_iProp = INVALID_ENT_REFERENCE;
int g_iActiveSkin = -1;
float g_fSettle = 1.6;
bool g_bQuitWhenDone;
char g_sCurrentShot[16];

public Plugin myinfo =
{
	name = "L4D2 Skin Shots",
	author = "Altair Sossai",
	description = "Takes the same screenshots of every weapon skin on a local listen server",
	version = "1.0.0",
	url = "https://github.com/altair-sossai/l4d2-screenshot-studio"
};

public void OnPluginStart()
{
	g_hModels = new ArrayList(sizeof(WeaponModels));
	g_hSkins = new ArrayList(sizeof(Skin));
	g_hJobs = new ArrayList(ByteCountToCells(96));
	g_hScenes = new StringMap();
	g_hSceneOrder = new ArrayList(ByteCountToCells(16));
	g_hAnimations = new StringMap();
	g_hFraming = new StringMap();

	RegServerCmd("sm_shots_run", Command_Run, "sm_shots_run <scene|all> [skin ids or weapon classes...]");
	RegServerCmd("sm_shots_show", Command_Show, "sm_shots_show <skin> <scene>");
	RegServerCmd("sm_shots_snap", Command_Snap, "sm_shots_snap <name>");
	RegServerCmd("sm_shots_where", Command_Where, "Logs the host position, view angles and state");
	RegServerCmd("sm_shots_goto", Command_Goto, "sm_shots_goto <x> <y> <z> <pitch> <yaw> <roll>");
	RegServerCmd("sm_shots_stop", Command_Stop, "Stops the running sequence");
	RegServerCmd("sm_shots_quit", Command_Quit, "Quits the game when the sequence ends");
	RegServerCmd("sm_shots_frame", Command_Frame, "sm_shots_frame <pitch> <yaw> <fov>");
	RegServerCmd("sm_shots_weapon", Command_Weapon, "sm_shots_weapon <0|1|noshadow>");
	RegServerCmd("sm_shots_turn", Command_Turn, "sm_shots_turn <yaw>");
	RegServerCmd("sm_shots_pose", Command_Pose, "sm_shots_pose <pitch> <yaw> <roll>");
	RegServerCmd("sm_shots_unhook", Command_Unhook, "Stops the per-frame host changes");
	RegServerCmd("sm_shots_cvar", Command_Cvar, "sm_shots_cvar <name> [value]");

	CreateTimer(0.5, Timer_Queue, _, TIMER_REPEAT);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

Action Command_Cvar(int args)
{
	if (args < 1)
	{
		PrintToServer("sm_shots_cvar <name> [value]");
		return Plugin_Handled;
	}

	char name[64];
	GetCmdArg(1, name, sizeof(name));

	ConVar cvar = FindConVar(name);
	if (cvar == null)
	{
		Log("cvar %s not found", name);
		return Plugin_Handled;
	}

	if (args >= 2)
	{
		char value[64];
		GetCmdArg(2, value, sizeof(value));
		cvar.SetString(value, true, false);
	}

	char current[64];
	cvar.GetString(current, sizeof(current));
	Log("cvar %s = %s", name, current);
	return Plugin_Handled;
}

public void OnMapStart()
{
	LoadSkins();
	LoadScenes();
	g_iProp = INVALID_ENT_REFERENCE;
	g_iActor = -1;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);
}

Action Timer_Queue(Handle timer)
{
	if (!FileExists(QUEUE_FILE))
	{
		return Plugin_Continue;
	}

	File file = OpenFile(QUEUE_FILE, "r");
	if (file == null)
	{
		return Plugin_Continue;
	}

	char line[512];
	ArrayList lines = new ArrayList(ByteCountToCells(sizeof(line)));
	while (file.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] != '\0')
		{
			lines.PushString(line);
		}
	}

	delete file;
	DeleteFile(QUEUE_FILE);

	for (int i = 0; i < lines.Length; i++)
	{
		lines.GetString(i, line, sizeof(line));
		Log("queue: %s", line);

		if (strncmp(line, "client ", 7) != 0)
		{
			ServerCommand("%s", line);
			continue;
		}

		int host = GetHost();
		if (host != -1)
		{
			ClientCommand(host, "%s", line[7]);
		}
	}

	delete lines;
	return Plugin_Continue;
}

void LoadSkins()
{
	g_hModels.Clear();
	g_hSkins.Clear();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), SKINS_CONFIG);

	KeyValues kv = new KeyValues("WeaponSkins");
	if (!kv.ImportFromFile(path))
	{
		Log("could not read %s", path);
		delete kv;
		return;
	}

	if (kv.JumpToKey("Weapons") && kv.GotoFirstSubKey())
	{
		do
		{
			WeaponModels models;
			kv.GetSectionName(models.weapon, sizeof(models.weapon));
			kv.GetString("view_model", models.viewModel, sizeof(models.viewModel));
			kv.GetString("world_model", models.worldModel, sizeof(models.worldModel));
			models.viewModelIndex = PrecacheModel(models.viewModel, true);
			models.worldModelIndex = PrecacheModel(models.worldModel, true);
			g_hModels.PushArray(models);
		}
		while (kv.GotoNextKey());

		kv.GoBack();
		kv.GoBack();
	}

	if (kv.JumpToKey("Skins") && kv.GotoFirstSubKey())
	{
		do
		{
			Skin skin;
			kv.GetSectionName(skin.id, sizeof(skin.id));
			kv.GetString("weapon", skin.weapon, sizeof(skin.weapon));
			skin.family = kv.GetNum("skin");
			g_hSkins.PushArray(skin);
		}
		while (kv.GotoNextKey());
	}

	delete kv;
	Log("loaded %d weapons and %d skins", g_hModels.Length, g_hSkins.Length);
}

void LoadScenes()
{
	g_hScenes.Clear();
	g_hSceneOrder.Clear();
	g_hFraming.Clear();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), SHOTS_CONFIG);

	KeyValues kv = new KeyValues("SkinShots");
	if (!kv.ImportFromFile(path))
	{
		Log("could not read %s", path);
		delete kv;
		return;
	}

	g_fSettle = kv.GetFloat("settle", 1.6);
	kv.GetString("actor_model", g_sActorModel, sizeof(g_sActorModel), DEFAULT_ACTOR_MODEL);
	PrecacheModel(g_sActorModel, true);

	g_hAnimations.Clear();
	if (kv.JumpToKey("animations"))
	{
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				char weapon[64];
				char animation[64];
				kv.GetSectionName(weapon, sizeof(weapon));
				kv.GetString(NULL_STRING, animation, sizeof(animation));
				g_hAnimations.SetString(weapon, animation);
			}
			while (kv.GotoNextKey(false));

			kv.GoBack();
		}

		kv.GoBack();
	}

	char map[64];
	GetCurrentMap(map, sizeof(map));
	if (!kv.JumpToKey(map))
	{
		Log("no scenes for map %s", map);
		delete kv;
		return;
	}

	if (kv.GotoFirstSubKey())
	{
		do
		{
			char name[16];
			kv.GetSectionName(name, sizeof(name));

			Scene scene;
			kv.GetVector("origin", scene.origin);
			kv.GetVector("angles", scene.angles);
			kv.GetVector("target_origin", scene.targetOrigin);
			kv.GetVector("target_angles", scene.targetAngles);
			char meleeAngles[64];
			kv.GetString("melee_target_angles", meleeAngles, sizeof(meleeAngles));
			scene.hasMeleeAngles = strlen(meleeAngles) > 0;
			kv.GetVector("melee_target_angles", scene.meleeAngles);
			scene.viewModel = kv.GetNum("viewmodel", 0) == 1;
			scene.fov = kv.GetNum("fov", 0);
			kv.GetString("type", scene.type, sizeof(scene.type), name);
			g_hScenes.SetArray(name, scene, sizeof(scene));

			if (kv.JumpToKey("framing"))
			{
				if (kv.GotoFirstSubKey(false))
				{
					do
					{
						char weapon[64];
						char key[96];
						char value[64];
						char parts[4][16];
						float framing[4];
						kv.GetSectionName(weapon, sizeof(weapon));
						kv.GetString(NULL_STRING, value, sizeof(value));
						framing[3] = -1.0;
						int count = ExplodeString(value, " ", parts, sizeof(parts), sizeof(parts[]));
						for (int i = 0; i < count; i++)
						{
							framing[i] = StringToFloat(parts[i]);
						}

						FormatEx(key, sizeof(key), "%s|%s", name, weapon);
						g_hFraming.SetArray(key, framing, sizeof(framing));
					}
					while (kv.GotoNextKey(false));

					kv.GoBack();
				}

				kv.GoBack();
			}

			if (!StrEqual(scene.type, "park"))
			{
				g_hSceneOrder.PushString(name);
			}
		}
		while (kv.GotoNextKey());
	}

	delete kv;
	Log("loaded %d scenes for %s", g_hScenes.Size, map);
}

Action Command_Run(int args)
{
	if (args < 1)
	{
		PrintToServer("sm_shots_run <scene|all> [skin ids or weapon classes...]");
		return Plugin_Handled;
	}

	LoadSkins();
	LoadScenes();

	char shots[128];
	GetCmdArg(1, shots, sizeof(shots));

	ArrayList filters = new ArrayList(ByteCountToCells(64));
	for (int i = 2; i <= args; i++)
	{
		char filter[64];
		GetCmdArg(i, filter, sizeof(filter));
		filters.PushString(filter);
	}

	g_hJobs.Clear();
	for (int s = 0; s < g_hSceneOrder.Length; s++)
	{
		char scene[16];
		g_hSceneOrder.GetString(s, scene, sizeof(scene));
		char wanted[24];
		FormatEx(wanted, sizeof(wanted), ",%s,", scene);
		char list[132];
		FormatEx(list, sizeof(list), ",%s,", shots);
		if (!StrEqual(shots, "all") && StrContains(list, wanted) == -1)
		{
			continue;
		}

		for (int i = 0; i < g_hSkins.Length; i++)
		{
			Skin skin;
			g_hSkins.GetArray(i, skin);
			if (filters.Length > 0 && filters.FindString(skin.id) == -1 && filters.FindString(skin.weapon) == -1)
			{
				continue;
			}

			char job[96];
			FormatEx(job, sizeof(job), "%s|%s", scene, skin.id);
			g_hJobs.PushString(job);
		}
	}

	delete filters;

	PrepareOutput();
	PrepareWorld();
	Log("run %s: %d shots", shots, g_hJobs.Length);

	g_iJob = -1;
	CreateTimer(1.0, Timer_NextJob, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

Action Command_Show(int args)
{
	if (args < 2)
	{
		PrintToServer("sm_shots_show <skin> <scene>");
		return Plugin_Handled;
	}

	LoadScenes();
	PrepareWorld();

	char id[64];
	char shot[16];
	GetCmdArg(1, id, sizeof(id));
	GetCmdArg(2, shot, sizeof(shot));

	int index = FindSkin(id);
	if (index == -1)
	{
		Log("unknown skin %s", id);
		return Plugin_Handled;
	}

	SetupScene(shot, index);
	return Plugin_Handled;
}

Action Command_Snap(int args)
{
	char name[64] = "snap";
	if (args >= 1)
	{
		GetCmdArg(1, name, sizeof(name));
	}

	PrepareOutput();
	strcopy(g_sCurrentShot, sizeof(g_sCurrentShot), "test");

	DataPack pack = new DataPack();
	pack.WriteString(name);
	TakeScreenshot();
	CreateTimer(0.5, Timer_MoveSnap, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
	return Plugin_Handled;
}

Action Timer_MoveSnap(Handle timer, DataPack pack)
{
	pack.Reset();

	char name[64];
	pack.ReadString(name, sizeof(name));

	char target[PLATFORM_MAX_PATH];
	FormatEx(target, sizeof(target), "%s/test/%s.jpg", OUTPUT_DIR, name);

	if (MoveNewestScreenshot(target))
	{
		Log("snap saved %s", target);
		return Plugin_Stop;
	}

	Log("snap not found yet for %s", target);
	return Plugin_Stop;
}

Action Command_Where(int args)
{
	int host = GetHost();
	if (host == -1)
	{
		Log("no host");
		return Plugin_Handled;
	}

	float origin[3];
	float angles[3];
	GetClientAbsOrigin(host, origin);
	GetClientEyeAngles(host, angles);
	Log("where origin \"%.1f %.1f %.1f\" angles \"%.1f %.1f %.1f\" team %d alive %d observer %d", origin[0], origin[1], origin[2], angles[0], angles[1], angles[2], GetClientTeam(host), IsPlayerAlive(host), GetEntProp(host, Prop_Send, "m_iObserverMode"));
	char model[PLATFORM_MAX_PATH];
	GetClientModel(host, model, sizeof(model));
	Log("state hidehud %d flags %d character %d model %s", GetEntProp(host, Prop_Send, "m_iHideHUD"), GetEntityFlags(host), GetEntProp(host, Prop_Send, "m_survivorCharacter"), model);
	for (int i = 0; i < 2; i++)
	{
		int vm = GetEntPropEnt(host, Prop_Send, "m_hViewModel", i);
		if (vm == -1)
		{
			Log("viewmodel %d none", i);
			continue;
		}

		char vmModel[PLATFORM_MAX_PATH];
		GetEntPropString(vm, Prop_Data, "m_ModelName", vmModel, sizeof(vmModel));
		Log("viewmodel %d entity %d model %s effects %d body %d skin %d", i, vm, vmModel, GetEntProp(vm, Prop_Send, "m_fEffects"), GetEntProp(vm, Prop_Send, "m_nBody"), GetEntProp(vm, Prop_Send, "m_nSkin"));
	}
	return Plugin_Handled;
}

Action Command_Goto(int args)
{
	int host = GetHost();
	if (host == -1 || args < 6)
	{
		PrintToServer("sm_shots_goto <x> <y> <z> <pitch> <yaw> <roll>");
		return Plugin_Handled;
	}

	float values[6];
	for (int i = 0; i < 6; i++)
	{
		values[i] = GetCmdArgFloat(i + 1);
	}

	float origin[3];
	float angles[3];
	origin[0] = values[0];
	origin[1] = values[1];
	origin[2] = values[2];
	angles[0] = values[3];
	angles[1] = values[4];
	angles[2] = values[5];
	TeleportEntity(host, origin, angles, view_as<float>({ 0.0, 0.0, 0.0 }));
	return Plugin_Handled;
}

Action Command_Stop(int args)
{
	g_hJobs.Clear();
	g_iJob = -1;
	Log("stopped");
	return Plugin_Handled;
}

Action Command_Quit(int args)
{
	g_bQuitWhenDone = true;
	return Plugin_Handled;
}

Action Timer_NextJob(Handle timer)
{
	g_iJob++;
	if (g_iJob >= g_hJobs.Length)
	{
		Log("done");
		g_iActiveSkin = -1;

		if (g_bQuitWhenDone)
		{
			ServerCommand("quit");
		}

		return Plugin_Stop;
	}

	char job[96];
	char parts[2][64];
	g_hJobs.GetString(g_iJob, job, sizeof(job));
	ExplodeString(job, "|", parts, sizeof(parts), sizeof(parts[]));

	int index = FindSkin(parts[1]);
	if (index == -1 || !SetupScene(parts[0], index))
	{
		Log("skipped %s", job);
		CreateTimer(0.1, Timer_NextJob, _, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}

	strcopy(g_sCurrentShot, sizeof(g_sCurrentShot), parts[0]);
	CreateTimer(g_fSettle, Timer_Shoot, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

Action Timer_Shoot(Handle timer)
{
	TakeScreenshot();
	g_iRetries = 0;
	CreateTimer(0.4, Timer_Collect, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	return Plugin_Stop;
}

Action Timer_Collect(Handle timer)
{
	char job[96];
	char parts[2][64];
	g_hJobs.GetString(g_iJob, job, sizeof(job));
	ExplodeString(job, "|", parts, sizeof(parts), sizeof(parts[]));

	char target[PLATFORM_MAX_PATH];
	FormatEx(target, sizeof(target), "%s/%s/%s.jpg", OUTPUT_DIR, parts[0], parts[1]);

	if (MoveNewestScreenshot(target))
	{
		Log("%d/%d %s", g_iJob + 1, g_hJobs.Length, target);
		CreateTimer(0.1, Timer_NextJob, _, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}

	g_iRetries++;
	if (g_iRetries < MAX_SHOT_RETRIES)
	{
		return Plugin_Continue;
	}

	Log("missing screenshot for %s", job);
	CreateTimer(0.1, Timer_NextJob, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

bool SetupScene(const char[] shot, int index)
{
	Scene scene;
	if (!g_hScenes.GetArray(shot, scene, sizeof(scene)))
	{
		Log("scene %s is not configured for this map", shot);
		return false;
	}

	int host = GetHost();
	if (host == -1)
	{
		Log("no host");
		return false;
	}

	Skin skin;
	g_hSkins.GetArray(index, skin);

	float angles[3];
	angles = scene.angles;
	int fov = scene.fov;

	char key[96];
	float framing[4];
	float actorAngles[3];
	actorAngles = scene.targetAngles;
	FormatEx(key, sizeof(key), "%s|%s", shot, skin.weapon);
	if (g_hFraming.GetArray(key, framing, sizeof(framing)))
	{
		angles[0] = framing[0];
		angles[1] = framing[1];
		fov = RoundToNearest(framing[2]);
		if (framing[3] >= 0.0)
		{
			actorAngles[1] = framing[3];
		}
	}

	SetEntityMoveType(host, StrEqual(scene.type, "third") ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
	TeleportEntity(host, scene.origin, angles, view_as<float>({ 0.0, 0.0, 0.0 }));
	SetLocalCvar("r_drawviewmodel", scene.viewModel ? "1" : "0");
	SetEntProp(host, Prop_Send, "m_iFOV", fov);

	RemoveProp();
	g_iActiveSkin = -1;

	if (StrEqual(scene.type, "hand"))
	{
		HideActor();
		GiveWeapon(host, skin.weapon);
		g_iActiveSkin = index;
		return true;
	}

	if (StrEqual(scene.type, "ground"))
	{
		HideActor();
		bool melee = StrContains(skin.weapon, "weapon_melee_") == 0 && scene.hasMeleeAngles;
		return SpawnProp(index, scene.targetOrigin, melee ? scene.meleeAngles : scene.targetAngles);
	}

	HideActor();
	return SpawnPosedSurvivor(index, scene.targetOrigin, actorAngles);
}

Action Command_Frame(int args)
{
	int host = GetHost();
	if (host == -1 || args < 3)
	{
		PrintToServer("sm_shots_frame <pitch> <yaw> <fov>");
		return Plugin_Handled;
	}

	float angles[3];
	angles[0] = GetCmdArgFloat(1);
	angles[1] = GetCmdArgFloat(2);
	TeleportEntity(host, NULL_VECTOR, angles, NULL_VECTOR);
	SetEntProp(host, Prop_Send, "m_iFOV", GetCmdArgInt(3));
	return Plugin_Handled;
}

Action Command_Turn(int args)
{
	int survivor = EntRefToEntIndex(g_iPosedSurvivor);
	if (survivor == INVALID_ENT_REFERENCE || args < 1)
	{
		PrintToServer("sm_shots_turn <yaw>");
		return Plugin_Handled;
	}

	float angles[3];
	angles[1] = GetCmdArgFloat(1);
	TeleportEntity(survivor, NULL_VECTOR, angles, NULL_VECTOR);
	return Plugin_Handled;
}

Action Command_Pose(int args)
{
	int prop = EntRefToEntIndex(g_iProp);
	if (prop == INVALID_ENT_REFERENCE || args < 3)
	{
		PrintToServer("sm_shots_pose <pitch> <yaw> <roll>");
		return Plugin_Handled;
	}

	float angles[3];
	angles[0] = GetCmdArgFloat(1);
	angles[1] = GetCmdArgFloat(2);
	angles[2] = GetCmdArgFloat(3);
	TeleportEntity(prop, NULL_VECTOR, angles, NULL_VECTOR);
	return Plugin_Handled;
}

Action Command_Weapon(int args)
{
	int weapon = EntRefToEntIndex(g_iPosedWeapon);
	if (weapon == INVALID_ENT_REFERENCE)
	{
		weapon = EntRefToEntIndex(g_iProp);
	}

	if (weapon == INVALID_ENT_REFERENCE)
	{
		Log("no weapon prop");
		return Plugin_Handled;
	}

	char state[16];
	GetCmdArg(1, state, sizeof(state));
	if (StrEqual(state, "noshadow"))
	{
		AcceptEntityInput(weapon, "DisableShadow");
		return Plugin_Handled;
	}

	AcceptEntityInput(weapon, StringToInt(state) == 1 ? "TurnOn" : "TurnOff");
	return Plugin_Handled;
}

bool SpawnPosedSurvivor(int index, const float origin[3], const float angles[3])
{
	Skin skin;
	g_hSkins.GetArray(index, skin);

	WeaponModels models;
	if (!FindModels(skin.weapon, models))
	{
		Log("no models for %s", skin.weapon);
		return false;
	}

	char animation[64];
	if (!g_hAnimations.GetString(skin.weapon, animation, sizeof(animation)))
	{
		strcopy(animation, sizeof(animation), "Idle_Standing_SMG");
	}

	int survivor = CreateEntityByName("prop_dynamic_override");
	if (survivor == -1)
	{
		return false;
	}

	DispatchKeyValue(survivor, "model", g_sActorModel);
	DispatchKeyValue(survivor, "solid", "0");
	DispatchKeyValue(survivor, "targetname", PROP_NAME);
	DispatchKeyValue(survivor, "DefaultAnim", animation);
	DispatchSpawn(survivor);
	TeleportEntity(survivor, origin, angles, NULL_VECTOR);
	SetVariantString(animation);
	AcceptEntityInput(survivor, "SetAnimation");
	SetEntPropFloat(survivor, Prop_Send, "m_flPlaybackRate", 0.0);
	SetEntPropFloat(survivor, Prop_Send, "m_flCycle", 0.0);

	int weapon = CreateEntityByName("prop_dynamic_override");
	if (weapon == -1)
	{
		RemoveEntity(survivor);
		return false;
	}

	DispatchKeyValue(weapon, "model", models.worldModel);
	DispatchKeyValue(weapon, "solid", "0");
	DispatchKeyValue(weapon, "targetname", PROP_NAME);
	DispatchKeyValue(weapon, "effects", "129");
	DispatchSpawn(weapon);
	SetEntProp(weapon, Prop_Send, "m_nSkin", skin.family);
	TeleportEntity(weapon, origin, angles, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(weapon, "SetParent", survivor);
	SetVariantString("weapon_bone");
	AcceptEntityInput(weapon, "SetParentAttachment");
	TeleportEntity(weapon, view_as<float>({ 0.0, 0.0, 0.0 }), view_as<float>({ 0.0, 0.0, 0.0 }), NULL_VECTOR);
	SetEntProp(weapon, Prop_Send, "m_fEffects", GetEntProp(weapon, Prop_Send, "m_fEffects") | EF_BONEMERGE | EF_BONEMERGE_FASTCULL | EF_PARENT_ANIMATES);

	g_iPosedSurvivor = EntIndexToEntRef(survivor);
	g_iPosedWeapon = EntIndexToEntRef(weapon);
	return true;
}

void OnPostThinkPost(int client)
{
	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	if (effects & EF_DIMLIGHT)
	{
		SetEntProp(client, Prop_Send, "m_fEffects", effects & ~EF_DIMLIGHT);
	}

	int index = client == GetHost() ? g_iActiveSkin : -1;
	if (index == -1)
	{
		return;
	}

	Skin skin;
	g_hSkins.GetArray(index, skin);

	WeaponModels models;
	if (!FindModels(skin.weapon, models))
	{
		return;
	}

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon > MaxClients && IsValidEntity(weapon))
	{
		if (GetEntProp(weapon, Prop_Send, "m_nModelIndex") != models.worldModelIndex)
		{
			SetEntityModel(weapon, models.worldModel);
		}

		if (HasEntProp(weapon, Prop_Send, "m_iWorldModelIndex"))
		{
			SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", models.worldModelIndex);
		}

		SetEntProp(weapon, Prop_Send, "m_nSkin", skin.family);
	}

	if (client != GetHost())
	{
		return;
	}

	int viewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	if (viewModel <= MaxClients || !IsValidEntity(viewModel))
	{
		return;
	}

	SetEntProp(viewModel, Prop_Send, "m_nModelIndex", models.viewModelIndex);
	SetEntProp(viewModel, Prop_Send, "m_nSkin", skin.family);
}

bool SpawnProp(int index, const float origin[3], const float angles[3])
{
	Skin skin;
	g_hSkins.GetArray(index, skin);

	WeaponModels models;
	if (!FindModels(skin.weapon, models))
	{
		Log("no models for %s", skin.weapon);
		return false;
	}

	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop == -1)
	{
		return false;
	}

	DispatchKeyValue(prop, "model", models.worldModel);
	DispatchKeyValue(prop, "solid", "0");
	DispatchKeyValue(prop, "targetname", PROP_NAME);
	DispatchSpawn(prop);

	float resting[3];
	resting = origin;
	resting[2] = origin[2] - LowestPoint(prop, angles);
	TeleportEntity(prop, resting, angles, NULL_VECTOR);
	SetEntProp(prop, Prop_Send, "m_nSkin", skin.family);

	g_iProp = EntIndexToEntRef(prop);
	return true;
}

float LowestPoint(int entity, const float angles[3])
{
	float mins[3];
	float maxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);

	float front[3];
	float right[3];
	float up[3];
	GetAngleVectors(angles, front, right, up);

	float lowest = 0.0;
	for (int corner = 0; corner < 8; corner++)
	{
		float x = (corner & 1) != 0 ? maxs[0] : mins[0];
		float y = (corner & 2) != 0 ? maxs[1] : mins[1];
		float z = (corner & 4) != 0 ? maxs[2] : mins[2];
		float height = front[2] * x - right[2] * y + up[2] * z;
		if (corner == 0 || height < lowest)
		{
			lowest = height;
		}
	}

	return lowest;
}

void RemoveProp()
{
	int props[3];
	props[0] = EntRefToEntIndex(g_iProp);
	props[1] = EntRefToEntIndex(g_iPosedWeapon);
	props[2] = EntRefToEntIndex(g_iPosedSurvivor);

	for (int i = 0; i < sizeof(props); i++)
	{
		if (props[i] > MaxClients && IsValidEntity(props[i]))
		{
			RemoveEntity(props[i]);
		}
	}

	char name[64];
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
	{
		if (!IsValidEntity(entity) || !HasEntProp(entity, Prop_Data, "m_iName"))
		{
			continue;
		}

		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if (StrEqual(name, PROP_NAME))
		{
			RemoveEntity(entity);
		}
	}

	g_iProp = INVALID_ENT_REFERENCE;
	g_iPosedWeapon = INVALID_ENT_REFERENCE;
	g_iPosedSurvivor = INVALID_ENT_REFERENCE;
}

public void OnPluginEnd()
{
	RemoveProp();
}

void HideActor()
{
	int actor = GetActor();
	if (actor == -1)
	{
		return;
	}

	Scene park;
	if (g_hScenes.GetArray("park", park, sizeof(park)))
	{
		TeleportEntity(actor, park.origin, park.angles, view_as<float>({ 0.0, 0.0, 0.0 }));
		SetEntityMoveType(actor, MOVETYPE_NONE);
		return;
	}

	SetEntityRenderMode(actor, RENDER_NONE);
}

void GiveWeapon(int client, const char[] weapon)
{
	char item[64];
	strcopy(item, sizeof(item), weapon);
	ReplaceStringEx(item, sizeof(item), "weapon_", "");
	ReplaceStringEx(item, sizeof(item), "melee_", "");

	int slot = StrContains(weapon, "weapon_melee_") == 0 || StrContains(weapon, "weapon_pistol") == 0 ? 1 : 0;
	int current = GetPlayerWeaponSlot(client, slot);
	if (current != -1)
	{
		RemovePlayerItem(client, current);
		RemoveEntity(current);
	}

	CheatCommand(client, "give", item);

	int given = GetPlayerWeaponSlot(client, slot);
	if (given == -1 && slot == 1 && StrContains(weapon, "weapon_melee_") == 0)
	{
		given = CreateMelee(client, item);
	}
	if (given != -1)
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", given);
		char classname[64];
		GetEntityClassname(given, classname, sizeof(classname));
		FakeClientCommand(client, "use %s", classname);
		return;
	}

	Log("could not give %s", item);
}

int CreateMelee(int client, const char[] script)
{
	int melee = CreateEntityByName("weapon_melee");
	if (melee == -1)
	{
		return -1;
	}

	DispatchKeyValue(melee, "melee_script_name", script);
	DispatchSpawn(melee);

	float origin[3];
	GetClientAbsOrigin(client, origin);
	TeleportEntity(melee, origin, NULL_VECTOR, NULL_VECTOR);
	EquipPlayerWeapon(client, melee);

	return GetPlayerWeaponSlot(client, 1);
}

void CheatCommand(int client, const char[] command, const char[] argument)
{
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, argument);
	SetCommandFlags(command, flags);
}

void PrepareWorld()
{
	ServerCommand("sv_cheats 1; director_stop; z_common_limit 0; sb_stop 1; nb_stop 1; sv_infinite_ammo 1");
	ServerCommand("nb_delete_all infected");
	RemoveLooseItems();

	char settings[][][] =
	{
		{ "sv_cheats", "1" },
		{ "hidehud", "4" },
		{ "cl_drawhud", "0" },
		{ "crosshair", "0" },
		{ "cl_showfps", "0" },
		{ "cl_showpos", "0" },
		{ "net_graph", "0" },
		{ "con_drawnotify", "0" },
		{ "jpeg_quality", "95" },
		{ "mat_motion_blur_enabled", "0" },
		{ "engine_no_focus_sleep", "0" }
	};

	for (int i = 0; i < sizeof(settings); i++)
	{
		SetLocalCvar(settings[i][0], settings[i][1]);
	}

	int actor = GetActor();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (client != actor && IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == 2)
		{
			KickClient(client);
		}
	}
}

void SetLocalCvar(const char[] name, const char[] value)
{
	ConVar cvar = FindConVar(name);
	if (cvar == null)
	{
		Log("cvar %s not found", name);
		return;
	}

	cvar.SetString(value, true, false);
}

void RemoveLooseItems()
{
	int removed;
	char classname[64];
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
	{
		if (!IsValidEntity(entity) || !GetEntityClassname(entity, classname, sizeof(classname)))
		{
			continue;
		}

		if (strncmp(classname, "weapon_", 7) != 0 && strncmp(classname, "upgrade_", 8) != 0)
		{
			continue;
		}

		if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") > 0)
		{
			continue;
		}

		RemoveEntity(entity);
		removed++;
	}

	Log("removed %d loose items", removed);
}

void PrepareOutput()
{
	CreateDirectory(OUTPUT_DIR, 511);
	char sub[PLATFORM_MAX_PATH];
	FormatEx(sub, sizeof(sub), "%s/test", OUTPUT_DIR);
	CreateDirectory(sub, 511);

	for (int i = 0; i < g_hSceneOrder.Length; i++)
	{
		char name[16];
		g_hSceneOrder.GetString(i, name, sizeof(name));
		FormatEx(sub, sizeof(sub), "%s/%s", OUTPUT_DIR, name);
		CreateDirectory(sub, 511);
	}
}

void TakeScreenshot()
{
	int host = GetHost();
	if (host != -1)
	{
		ClientCommand(host, "jpeg");
	}
}

bool MoveNewestScreenshot(const char[] target)
{
	DirectoryListing dir = OpenDirectory(SCREENSHOTS_DIR);
	if (dir == null)
	{
		return false;
	}

	char name[PLATFORM_MAX_PATH];
	char found[PLATFORM_MAX_PATH];
	FileType type;
	while (dir.GetNext(name, sizeof(name), type))
	{
		if (type != FileType_File || StrContains(name, ".jpg", false) == -1)
		{
			continue;
		}

		if (found[0] == '\0' || strcmp(name, found) > 0)
		{
			strcopy(found, sizeof(found), name);
		}
	}

	delete dir;

	if (found[0] == '\0')
	{
		return false;
	}

	char source[PLATFORM_MAX_PATH];
	FormatEx(source, sizeof(source), "%s/%s", SCREENSHOTS_DIR, found);

	if (FileSize(source) <= 0)
	{
		return false;
	}

	if (FileExists(target))
	{
		DeleteFile(target);
	}

	return RenameFile(target, source);
}

int GetHost()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			return client;
		}
	}

	return -1;
}

int GetActor()
{
	if (g_iActor > 0 && g_iActor <= MaxClients && IsClientInGame(g_iActor) && IsFakeClient(g_iActor) && GetClientTeam(g_iActor) == 2)
	{
		return g_iActor;
	}

	g_iActor = -1;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client))
		{
			g_iActor = client;
			break;
		}
	}

	return g_iActor;
}

int FindSkin(const char[] id)
{
	Skin skin;
	for (int i = 0; i < g_hSkins.Length; i++)
	{
		g_hSkins.GetArray(i, skin);
		if (StrEqual(skin.id, id))
		{
			return i;
		}
	}

	return -1;
}

bool FindModels(const char[] weapon, WeaponModels models)
{
	for (int i = 0; i < g_hModels.Length; i++)
	{
		g_hModels.GetArray(i, models);
		if (StrEqual(models.weapon, weapon))
		{
			return true;
		}
	}

	return false;
}

void Log(const char[] format, any ...)
{
	char message[512];
	VFormat(message, sizeof(message), format, 2);

	char time[32];
	FormatTime(time, sizeof(time), "%H:%M:%S");

	File file = OpenFile(LOG_FILE, "a");
	if (file != null)
	{
		file.WriteLine("%s %s", time, message);
		delete file;
	}

	PrintToServer("[skin_shots] %s", message);
}

Action Command_Unhook(int args)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPost);
		}
	}

	Log("unhooked");
	return Plugin_Handled;
}
