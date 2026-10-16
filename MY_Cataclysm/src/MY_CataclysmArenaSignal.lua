--------------------------------------------------------------------------------
-- This file is part of the JX3 Mingyi Plugin.
--------------------------------------------------------------------------------
local X = MY
--------------------------------------------------------------------------------
local MODULE_PATH = 'MY_Cataclysm/MY_CataclysmArenaSignal'
local PLUGIN_NAME = 'MY_Cataclysm'
local PLUGIN_ROOT = X.PACKET_INFO.ROOT .. PLUGIN_NAME
local MODULE_NAME = 'MY_CataclysmArenaSignal'
local _L = X.LoadLangPack(PLUGIN_ROOT .. '/lang/')
--------------------------------------------------------------------------------
if not X.AssertVersion(MODULE_NAME, _L[MODULE_NAME] or MODULE_NAME, '^29.0.18') then
	return
end
--[[#DEBUG BEGIN]]X.ReportModuleLoading(MODULE_PATH, 'START')--[[#DEBUG END]]
--------------------------------------------------------------------------------
local INI_PATH = PLUGIN_ROOT .. '/ui/MY_CataclysmArenaSignal.ini'
local FRAME_NAME = 'MY_CataclysmArenaSignal'
local DISPLAY_TIME = 3000
local UPDATE_INTERVAL = 50
local MAX_BUBBLE_COUNT = 3
local SIGNAL_TYPE = {
	ATTACK = 1,
	RETREAT = 2,
	SOS = 3,
}

local D = {
	tSignals = {},
	hFrame = nil,
	nNextUpdateTick = 0,
}

local function GetFrame()
	return D.hFrame or Station.Lookup('Normal/' .. FRAME_NAME)
end

local function GetBubbleRoot(hFrame)
	return hFrame and hFrame:Lookup('', '')
end

local function IsPanelVisible()
	if not MY_Cataclysm or not MY_Cataclysm.bEnable or MY_Cataclysm.bFold then
		return false
	end
	if MY_CataclysmMain and MY_CataclysmMain.GetFrame then
		local hPanel = MY_CataclysmMain.GetFrame()
		return hPanel and hPanel:IsVisible()
	end
	return false
end

local function IsArenaSignal(nType, dwSourceID)
	return (nType == SIGNAL_TYPE.ATTACK
		or nType == SIGNAL_TYPE.RETREAT
		or nType == SIGNAL_TYPE.SOS)
	and dwSourceID and dwSourceID > 0
	and X.IsInArenaMap()
	and IsPanelVisible()
end

local function GetSignalText(nType)
	return Table_GetArenaAssistantQuickSignal(nType).szText
end

local function RemoveBubble(tSignal, hRoot)
	if tSignal.hBubble and hRoot then
		hRoot:RemoveItem(tSignal.hBubble)
	end
	tSignal.hBubble = nil
end

local function RemoveSignal(dwSourceID, hRoot)
	local tSignal = D.tSignals[dwSourceID]
	if tSignal then
		RemoveBubble(tSignal, hRoot)
		D.tSignals[dwSourceID] = nil
	end
end

local function CountSignals()
	local nCount = 0
	for _ in pairs(D.tSignals) do
		nCount = nCount + 1
	end
	return nCount
end

local function RemoveOldestSignal(hRoot)
	local dwOldestID, nOldestCloseTick
	for dwSourceID, tSignal in pairs(D.tSignals) do
		if not nOldestCloseTick or tSignal.nCloseTick < nOldestCloseTick then
			dwOldestID = dwSourceID
			nOldestCloseTick = tSignal.nCloseTick
		end
	end
	if dwOldestID then
		RemoveSignal(dwOldestID, hRoot)
	end
end

local function UpdateContent(hBubble, tSignal)
	if hBubble.szText == tSignal.szText then
		return
	end
	hBubble:Lookup('Text_Content'):SetText(tSignal.szText)
	hBubble.szText = tSignal.szText
end

local function UpdateBubble(tSignal, hFrame)
	local hMember = MY_CataclysmParty
		and MY_CataclysmParty.GetMemberHandle
		and MY_CataclysmParty.GetMemberHandle(tSignal.dwSourceID)
	if not hMember or not hMember:IsValid() then
		if tSignal.hBubble then
			RemoveBubble(tSignal, GetBubbleRoot(hFrame))
		end
		return false
	end

	local hBubble = tSignal.hBubble
	local hRoot = GetBubbleRoot(hFrame)
	if not hRoot then
		return false
	end
	if not hBubble or not hBubble:IsValid() then
		hBubble = hRoot:Lookup('Handle_Bubble_' .. tSignal.dwSourceID)
		if not hBubble then
			hBubble = hRoot:AppendItemFromIni(INI_PATH, 'Handle_Bubble')
			if not hBubble then
				return false
			end
			hBubble:SetName('Handle_Bubble_' .. tSignal.dwSourceID)
		end
		tSignal.hBubble = hBubble
	end

	UpdateContent(hBubble, tSignal)

	local nMemberX, nMemberY = hMember:GetAbsPos()
	local nMemberW, nMemberH = hMember:GetSize()
	local nBubbleW, nBubbleH = hBubble:GetSize()
	local nScreenW, nScreenH = Station.GetClientSize()
	local nX = nMemberX + nMemberW + 4
	local nY = nMemberY + (nMemberH - nBubbleH) / 2
	if nX + nBubbleW > nScreenW then
		nX = nMemberX - nBubbleW - 4
	end
	nX = math.max(0, math.min(nX, nScreenW - nBubbleW))
	nY = math.max(0, math.min(nY, nScreenH - nBubbleH))
	hBubble:SetRelPos(nX, nY)
	hBubble:SetAbsPos(nX, nY)
	hBubble:Show()
	return true
end

local function RefreshBubbles(hFrame, nNow)
	local hRoot = GetBubbleRoot(hFrame)
	local bHasBubble = false
	for dwSourceID, tSignal in pairs(D.tSignals) do
		if nNow >= tSignal.nCloseTick then
			RemoveSignal(dwSourceID, hRoot)
		else
			bHasBubble = UpdateBubble(tSignal, hFrame) or bHasBubble
		end
	end
	if hRoot then
		hRoot:FormatAllItemPos()
		for _, tSignal in pairs(D.tSignals) do
			if tSignal.hBubble and tSignal.hBubble:IsValid() then
				UpdateBubble(tSignal, hFrame)
			end
		end
	end
	return bHasBubble
end

local function ClearSignals(hFrame)
	local hRoot = GetBubbleRoot(hFrame)
	for dwSourceID in pairs(D.tSignals) do
		RemoveSignal(dwSourceID, hRoot)
	end
	D.tSignals = {}
end

local function SyncFrameSize(hFrame)
	local nScreenW, nScreenH = Station.GetClientSize()
	hFrame:SetAbsPos(0, 0)
	hFrame:SetSize(nScreenW, nScreenH)
	local hRoot = GetBubbleRoot(hFrame)
	if hRoot then
		hRoot:SetSize(nScreenW, nScreenH)
	end
end

local function OnQuickSignal()
	local nType = tonumber(arg0)
	local dwSourceID = tonumber(arg1)
	if not IsArenaSignal(nType, dwSourceID) then
		return
	end

	local hFrame = GetFrame()
	if not hFrame then
		X.UI.OpenFrame(INI_PATH, FRAME_NAME)
		hFrame = GetFrame()
	end
	if not hFrame then
		return
	end
	SyncFrameSize(hFrame)

	local hRoot = GetBubbleRoot(hFrame)
	if not D.tSignals[dwSourceID] and CountSignals() >= MAX_BUBBLE_COUNT then
		RemoveOldestSignal(hRoot)
	end
	local tSignal = D.tSignals[dwSourceID] or {}
	tSignal.dwSourceID = dwSourceID
	tSignal.szText = GetSignalText(nType)
	tSignal.nCloseTick = GetTime() + DISPLAY_TIME
	D.tSignals[dwSourceID] = tSignal
	RefreshBubbles(hFrame, GetTime())
	hFrame:Show()
end

function D.OnFrameCreate()
	D.hFrame = this
	this:Lookup('', ''):Clear()
	this:RegisterEvent('UI_SCALED')
	this:RegisterEvent('ARENA_END')
	this:RegisterEvent('LOADING_BEGIN')
	this:RegisterEvent('PARTY_DISBAND')
	this:RegisterEvent('PLAYER_LEAVE_SCENE')
	SyncFrameSize(this)
end

function D.OnFrameDestroy()
	D.hFrame = nil
	D.tSignals = {}
	D.nNextUpdateTick = 0
end

function D.OnEvent(szEvent)
	if szEvent == 'UI_SCALED' then
		SyncFrameSize(this)
	elseif szEvent == 'ARENA_END'
	or szEvent == 'LOADING_BEGIN'
	or szEvent == 'PARTY_DISBAND'
	or szEvent == 'MY_CLIENT_PLAYER_LEAVE_SCENE'
	or (szEvent == 'PLAYER_LEAVE_SCENE' and not X.IsInArenaMap()) then
		ClearSignals(this)
		X.UI.CloseFrame(this)
	end
end

function D.OnFrameBreathe()
	if not IsPanelVisible() then
		ClearSignals(this)
		X.UI.CloseFrame(this)
		return
	end
	this:SetVisible(true)
	local nNow = GetTime()
	if nNow < D.nNextUpdateTick then
		return
	end
	D.nNextUpdateTick = nNow + UPDATE_INTERVAL
	if not RefreshBubbles(this, nNow) and CountSignals() == 0 then
		X.UI.CloseFrame(this)
	end
end

local settings = {
	name = FRAME_NAME,
	exports = {
		{
			root = D,
			preset = 'UIEvent',
		},
	},
}
MY_CataclysmArenaSignal = X.CreateModule(settings)

local function CloseSignalFrame()
	local hFrame = GetFrame()
	if hFrame then
		ClearSignals(hFrame)
		X.UI.CloseFrame(hFrame)
	end
end

X.RegisterEvent('ARENA_ASSISTANT_QUICK_SIGNAL', 'MY_CataclysmArenaSignal', OnQuickSignal)
X.RegisterEvent('MY_CLIENT_PLAYER_LEAVE_SCENE', 'MY_CataclysmArenaSignal', CloseSignalFrame)
X.RegisterEvent({ 'MY_CATACLYSM_SET_VISIBLE', 'MY_CATACLYSM_SET_FOLD' }, 'MY_CataclysmArenaSignal', function()
	if not IsPanelVisible() then
		CloseSignalFrame()
	end
end)

--[[#DEBUG BEGIN]]X.ReportModuleLoading(MODULE_PATH, 'FINISH')--[[#DEBUG END]]
