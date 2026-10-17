---------------------------------------------------------
-- Change IconScale to adjust the size of flight icons
-- Value is a decimal between 0 and 1
local IconScale = 1.0

---------------------------------------------------------
-- End of user settings
---------------------------------------------------------

local flightMapFrame = FlightMapFrame
local originalTaxiButtons = {}
-- InFlight uses FlightMapFrame directly, so it's necessary to change references
FlightMapFrame = WorldMapFrame
-- TaxiFrame = WorldMapFrame

-- Map data functions
local MapSizeCache = {} -- [uiMapID] = {left, top, right, bottom, etc}
local function GetCurrentMapContinent(uiMapID)
	--local uiMapID = uiMapID -- or WorldMapFrame:GetMapID()
	if uiMapID then
		local continent = MapUtil.GetMapParentInfo(uiMapID, Enum.UIMapType.Continent)
		if continent then
			return continent.mapID
		end
	end
end

local function GetParentZone(uiMapID)
	if uiMapID then
		local zone = MapUtil.GetMapParentInfo(uiMapID, Enum.UIMapType.Zone, uiMapID ~= 2346 and true or false)
		if zone then
			return zone.mapID
		end
		local continent = MapUtil.GetMapParentInfo(WorldMapFrame:GetMapID(), Enum.UIMapType.Continent)
		if continent then
			return continent.mapID
		end
		return uiMapID
	end
end

local function GetMapSize(uiMapID, noLoop)
	local uiMapID = uiMapID or WorldMapFrame:GetMapID()
	if not uiMapID then return end
	
	-- Return cached information if we've looked it up before
	if MapSizeCache[uiMapID] then
		return MapSizeCache[uiMapID]
	end
	
	local instanceID, topleft = C_Map.GetWorldPosFromMapPos(uiMapID, {x = 0, y = 0})
	local instanceID, bottomright = C_Map.GetWorldPosFromMapPos(uiMapID, {x = 1, y = 1})
	if not instanceID then return end
	
	local left, top = topleft.y, topleft.x
	local right, bottom = bottomright.y, bottomright.x
	local width, height = left - right, top - bottom
	
	local continentMapID = GetCurrentMapContinent(uiMapID)
	
	local mapInfo = C_Map.GetMapInfo(uiMapID)
	
	-- Transform coordinates for areas that draw on a different continent than the instance they belong to
	if continentMapID and not noLoop then
		local continentSize = GetMapSize(continentMapID, true)
		if continentSize then
			local relLeft, relRight, relTop, relBottom = C_Map.GetMapRectOnMap(uiMapID, continentMapID)
			left = continentSize.left - continentSize.width * relLeft
			right = continentSize.left - continentSize.width * relRight
			top = continentSize.top - continentSize.height * relTop
			bottom = continentSize.top - continentSize.height * relBottom
		end
	end
	
	local mapSize = {left = left, top = top, right = right, bottom = bottom, width = width, height = height, mapID = uiMapID, continent = continentMapID, mapInfo = mapInfo}
	
	-- Cache result so we don't have to do this again
	MapSizeCache[uiMapID] = mapSize
	
	return mapSize
end

-- Map provider
WorldFlightMapProvider = CreateFromMixins(FlightMap_FlightPathDataProviderMixin)
function WorldFlightMapProvider:OnAdded(...)
	FlightMap_FlightPathDataProviderMixin.OnAdded(self, ...)
	
	-- 12.1.5 的開圖事件由 GameEvent 接管。
	GameEvent.UnregisterInternalEvent('TAXIMAP_OPENED')

	self:RegisterEvent('TAXIMAP_OPENED')
	self:RegisterEvent('TAXIMAP_CLOSED')
	self:RegisterEvent('TAXI_NODE_STATUS_CHANGED')
	self:RegisterEvent('ADDON_LOADED')

	local button = CreateFrame('Button', nil, self:GetMap().BorderFrame, 'UIPanelButtonTemplate')
	button:SetSize(128, 24)
	button:SetPoint('RIGHT', self:GetMap().BorderFrame.MaximizeMinimizeFrame, 'LEFT', -8, 0)
	button:SetText('暴雪飛行地圖')
	button:SetScript('OnClick', function() self:SwitchToNativeMap() end)
	button:Hide()
	self.nativeMapButton = button
end

function WorldFlightMapProvider:OpenNativeTaxiMap(uiMapSystem)
	FlightMapFrame = flightMapFrame
	-- 原生 TaxiFrame 會重用已建立的按鈕，先還原被插件借用的全域引用。
	for name, button in pairs(originalTaxiButtons) do
		_G[name] = button or nil
		originalTaxiButtons[name] = nil
	end
	GameEvent.HandleTaxiMapOpened(self, 'TAXIMAP_OPENED', uiMapSystem)
end

function WorldFlightMapProvider:SwitchToNativeMap()
	if not self:IsTaxiOpen() then return end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
		return
	end

	local uiMapSystem = self.taxiMapSystem
	-- 只交接介面，不結束飛行對話；先停用自己的圖層，避免 OnHide 關閉航點資料。
	self:SetTaxiState(false)
	self:RemoveAllData()
	HideUIPanel(self:GetMap())
	self:OpenNativeTaxiMap(uiMapSystem)
end

-- Arrow functions
local PinArrows = {} -- [pin] = arrow frame
local function BounceAnimation(self) -- SetLooping('BOUNCE') is producing broken animations, so we're just simulating what it's supposed to do
	local tx, parent, bounce = self.tx, self.parent, self.bounce
	tx:ClearAllPoints()
	if self.up then
		tx:SetPoint('BOTTOM', parent, 'TOP', 0, 10)
		bounce:SetSmoothing('OUT')
	else
		tx:SetPoint('BOTTOM', parent, 'TOP')
		bounce:SetSmoothing('IN')
	end
	bounce:SetOffset(0, self.up and -10 or 10)
	self.up = not self.up
	self:Play()
end

local function ResetAnimation(self)
	self:Stop()
	self.up = true
	BounceAnimation(self)
end

local function GetArrow(pin)
	-- Add an arrow frame to a pin
	if PinArrows[pin] then return PinArrows[pin] end
	local f = CreateFrame('frame', nil, pin)
	f:SetAllPoints(pin)
	
	local tx = f:CreateTexture(nil, 'OVERLAY')
	tx:SetPoint('BOTTOM', f, 'TOP')
	tx:SetSize(32, 32)
	tx:SetTexture('interface/minimap/minimap-deadarrow')
	tx:SetTexCoord(0, 1, 1, 0)
	
	local duration = 0.75
	local group = tx:CreateAnimationGroup()
	group.tx = tx
	
	local bounce = group:CreateAnimation('Translation')
	bounce:SetOffset(0, 10)
	bounce:SetDuration(0.5)
	bounce:SetSmoothing('IN')
	group.bounce = bounce
	
	group.up = true
	
	group:SetScript('OnFinished', BounceAnimation)
	group.parent = f
	f.arrow = tx
	f.pin = pin
	group:Play()
	f.group = group
	
	PinArrows[pin] = f
	return f
end

function WorldFlightMapProvider:OnEvent(event, ...)
	if event == 'TAXIMAP_OPENED' then
		-- You can't take a flight in combat, and opening the world map in combat taints the interface
		-- Therefor we need to prevent the interaction in the first place
		if InCombatLockdown() then
			CloseTaxiMap()
		else
			if IsInInstance() then
				-- 副本內由暴雪依事件的地圖類型選擇原生飛行介面。
				self:OpenNativeTaxiMap(...)
				return
			end

			self.taxiMapSystem = ...
			self:SetTaxiState(true)
			self.taxiMap = GetMapSize(GetTaxiMapID())
			
			local playerMapID = C_Map.GetBestMapForUnit('player')
			local playerMapInfo = C_Map.GetMapInfo(playerMapID)
			self.playerContinent = GetCurrentMapContinent(playerMapID)
			
			if not self:GetMap():IsShown() and not InCombatLockdown() then
				if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) else HideUIPanel(WorldMapFrame) end
				--if self.playerContinent == 905 and playerMapInfo.mapType > Enum.UIMapType.Zone and playerMapInfo.parentMapID then
				--	self:GetMap():SetMapID(playerMapInfo.parentMapID)
				-- Zoom to parent zone if we're in a lower map
				-- We used to zoom out until we could fit multiple flight points on the same map, but this is simpler
				-- if playerMapInfo.mapType > Enum.UIMapType.Zone and playerMapInfo.parentMapID then
				if playerMapInfo.parentMapID then
					local parentZone = GetParentZone(playerMapID)
					if parentZone then
						self:GetMap():SetMapID(parentZone)
					end
				--else
					--self:GetMap():SetMapID(self.playerContinent)
				end
			end

			-- 開圖期間也會刷新 provider，最後選定的地圖才是本次飛行對話的起點。
			self.startingMapID = self:GetMap():GetMapID()
			self:RefreshAllData()
		end
	elseif event == 'TAXIMAP_CLOSED' then
		if FlightMapFrame ~= WorldMapFrame then
			-- 兩種原生介面自行處理關閉事件，這裡只恢復副本外的替換引用。
			FlightMapFrame = WorldMapFrame
			return
		end

		self:SetTaxiState(false)
		-- 戰鬥中可能保留世界地圖，仍須結束這次飛行對話的地圖狀態。
		FlightMap_FlightPathDataProviderMixin.OnHide(self)

		-- CloseTaxiMap()
		if self:GetMap():IsShown() and not InCombatLockdown() then
			if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) else HideUIPanel(WorldMapFrame) end
		end

		self:RemoveAllData()
	elseif event == 'TAXI_NODE_STATUS_CHANGED' then
		-- 原生飛行點會在這個事件重建，交由地圖下一次統一更新去重。
		self:GetMap():SetPinSuppressionDirty()
	end
end

function WorldFlightMapProvider:RefreshAllData(...)
	if self:IsTaxiOpen() then
		FlightMap_FlightPathDataProviderMixin.RefreshAllData(self, ...)
	else
		self:RemoveAllData()
	end
end

function WorldFlightMapProvider:OnMapChanged()
	local uiMapID = self:GetMap():GetMapID()
	self.worldMap = GetMapSize(uiMapID)
	FlightMap_FlightPathDataProviderMixin.OnMapChanged(self)
end

local e = math.exp(1)

function WorldFlightMapProvider:AddFlightNode(taxiNodeData)
	if self.taxiMap and self.worldMap and self.worldMap.left then
		-- limit to maps belonging to the same "continent" as the player (should really be the instance ID)
		if self.worldMap.continent == self.playerContinent then
			local taxiX, taxiY = taxiNodeData.position:GetXY()
			local worldTaxiX, worldTaxiY = self.taxiMap.left - taxiX * self.taxiMap.width, self.taxiMap.top - taxiY * self.taxiMap.height
			
			local mapTaxiX = (self.worldMap.left - worldTaxiX) / self.worldMap.width
			local mapTaxiY = (self.worldMap.top - worldTaxiY) / self.worldMap.height
			
			local drawPin = false
			--if self.playerContinent == 905 then -- match against node names for argus because coordinates are useless here (plus the vindicaar moves)
				local taxiNodes = C_TaxiMap.GetTaxiNodesForMap(self.worldMap.mapID)
				for _, landmark in pairs(taxiNodes) do
					if landmark.nodeID == taxiNodeData.nodeID then
						taxiNodeData.position.x = landmark.position.x
						taxiNodeData.position.y = landmark.position.y
						drawPin = true
						break
					end
				end
			--else
			if not drawPin then
				-- taxiNodeData.position.x = mapTaxiX
				-- taxiNodeData.position.y = mapTaxiY
				drawPin = true
			end
			
			if drawPin then
				-- Duplicating all of this from frameXML because we need to raise the frame level of the pins
				local playAnim = taxiNodeData.state ~= Enum.FlightPathState.Unreachable;
				local pin = self:GetMap():AcquirePin("WorldFlightPinTemplate", playAnim);
				
				-- For the sake of having other addons treat our buttons like normal taxi map buttons
				local buttonName = 'TaxiButton' .. taxiNodeData.slotIndex
				-- false 記錄原先沒有按鈕，避免刷新時把自己的圖釘存成原生引用。
				if originalTaxiButtons[buttonName] == nil then
					originalTaxiButtons[buttonName] = _G[buttonName] or false
				end
				_G[buttonName] = pin
				pin:SetID(taxiNodeData.slotIndex)
				
				-- Only show arrows on zone maps
				local arrow = GetArrow(pin)
				if taxiNodeData.textureKit == 'FlightMaster_ProgenitorObelisk' then
					arrow:Hide()
				elseif self.worldMap.mapInfo and self.worldMap.mapInfo.mapType and self.worldMap.mapInfo.mapType > 2 and taxiNodeData.state == Enum.FlightPathState.Reachable then
					-- Restart animation so the arrows move in sync
					ResetAnimation(arrow.group)
					arrow:Show()
				else
					arrow:Hide()
				end
				
				self.slotIndexToPin[taxiNodeData.slotIndex] = pin;

				pin:SetPosition(taxiNodeData.position:GetXY());
				pin.taxiNodeData = taxiNodeData;
				pin.textureKit = taxiNodeData.textureKit;
				pin.isMapLayerTransition = taxiNodeData.isMapLayerTransition;
				pin.owner = self;
				pin.linkedPins = {};
				pin:SetFlightPathStyle(taxiNodeData.state);
				
				pin:UpdatePinSize(taxiNodeData.state);
				
				pin:UseFrameLevelType("PIN_FRAME_LEVEL_TOPMOST")
				
				--pin:SetScalingLimits(1.25, 0.9625, 1.275)
				
				local initialScaleFactor = IconScale * (e ^ -(0.00000619843198095 * self.worldMap.width))
				pin:SetScalingLimits(1.25, initialScaleFactor, initialScaleFactor * 1.25)
				--pin:SetIgnoreGlobalPinScale(true)
				
				pin:SetShown(taxiNodeData.state ~= Enum.FlightPathState.Unreachable or taxiNodeData.isMapLayerTransition); -- Only show if part of a route, handled in the route building functions

				pin:ClearNudgeSettings()
				pin:ApplyCurrentPosition()
			end
		end
	end
end

function WorldFlightMapProvider:RemoveAllData()
	-- 航線先解除端點錨定，再回收圖釘。
	if self.linePool then
		self.linePool:ReleaseAll()
	end
	self.slotIndexToPin = {}
	self:GetMap():RemoveAllPinsByTemplate("WorldFlightPinTemplate")
	self:GetMap():ResetTitleAndPortraitIcon()

	if self.highlightLinePool then
		self.highlightLinePool:ReleaseAll()
	end
	if self.backgroundLinePool then
		self.backgroundLinePool:ReleaseAll()
	end
end

function WorldFlightMapProvider:HighlightRouteToPin(pin)
	if self.playerContinent == 905 then return end -- don't draw lines on argus maps (we could if they're on the same zone map)
	
	if not self.linePool then
		self.linePool = CreateLinePool(self:GetMap():GetCanvas(), 'BACKGROUND', -2)
	end

	local taxiSlotIndex = pin.taxiNodeData.slotIndex
	for routeIndex = 1, GetNumRoutes(taxiSlotIndex) do
		local sourceIndex = TaxiGetNodeSlot(taxiSlotIndex, routeIndex, true)
		local destIndex = TaxiGetNodeSlot(taxiSlotIndex, routeIndex, false)

		local startPin = self.slotIndexToPin[sourceIndex]
		local destPin = self.slotIndexToPin[destIndex]

		if startPin and destPin then
			local Line = self.linePool:Acquire()
			-- Line:SetNonBlocking(true)
			Line:SetAtlas('_UI-Taxi-Line-horizontal')
			Line:SetThickness(32)
			Line:SetStartPoint('CENTER', startPin)
			Line:SetEndPoint('CENTER', destPin)
			Line:Show()

			-- force show all the pins in the route
			startPin:Show()
			destPin:Show()
		end
	end
	self:GetMap():SetPinSuppressionDirty()
end

function WorldFlightMapProvider:RemoveRouteToPin(pin)
	if(self.linePool) then
		self.linePool:ReleaseAll()
	end

	for _, pin in next, self.slotIndexToPin do
		-- update visibility
		pin:SetShown(pin.taxiNodeData.state ~= Enum.FlightPathState.Unreachable or pin.taxiNodeData.isMapLayerTransition)
		--Pin:UpdateState()
	end
	self:GetMap():SetPinSuppressionDirty()
end

function WorldFlightMapProvider:ShowBackgroundRoutesFromCurrent()
	-- todo: show initial hoplines to direct routes
end

function WorldFlightMapProvider:OnHide()
	FlightMap_FlightPathDataProviderMixin.OnHide(self)
	if self:IsTaxiOpen() then
		CloseTaxiMap()
	end
end

function WorldFlightMapProvider:IsTaxiOpen()
	return self.taxiOpen
end

function WorldFlightMapProvider:SetTaxiState(state)
	self.taxiOpen = state
	self.nativeMapButton:SetShown(state)
	if not state then
		self.taxiMapSystem = nil
	end
end

function WorldMapFrame:ResetTitleAndPortraitIcon()
	-- Placeholder for missing mixin method that gets called when the map is opened
end

function WorldMapFrame:UpdateTitleAndPortraitIcon()
	-- Called when map is opened to a zone with a bastion node on it
end

WorldMapFrame:AddDataProvider(WorldFlightMapProvider)

-- use modified pin mixin and template to prevent taint
-- https://github.com/Stanzilla/WoWUIBugs/issues/453
WorldFlightPinMixin = CreateFromMixins(FlightMap_FlightPointPinMixin)
WorldFlightPinMixin.SetPassThroughButtons = function() end

-- 用原生 suppression 在所有 provider 刷新後去重，避免依賴飛行點的建立順序。
function WorldFlightPinMixin:IsPinSuppressor()
	return true
end

function WorldFlightPinMixin:ShouldSuppressPin(pin)
	return self:IsShown() and pin.pinTemplate == 'FlightPointPinTemplate'
		and pin:GetPoiInfo().nodeID == self.taxiNodeData.nodeID
end

function WorldFlightPinMixin:TrackSuppressedPin(pin)
	if not self.suppressedPins then
		self.suppressedPins = {}
	end
	self.suppressedPins[pin] = true
end

function WorldFlightPinMixin:ResetSuppression()
	if self.suppressedPins then
		for pin in pairs(self.suppressedPins) do
			if pin:GetPinSuppressor() == self then
				pin:ClearSuppression()
				-- 已回收的原生圖釘不可因清除 suppression 而重新顯示。
				if pin:GetMap() ~= self:GetMap() then
					pin:Hide()
				end
			end
		end
		self.suppressedPins = nil
	end
end

function WorldFlightPinMixin:FinalizeSuppression()
end

function WorldFlightPinMixin:OnReleased()
	self:ResetSuppression()
	FlightMap_FlightPointPinMixin.OnReleased(self)
end
