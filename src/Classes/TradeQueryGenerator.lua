-- Path of Building
--
-- Module: Trade Query Generator
-- Generates weighted trade queries for item upgrades
--

local dkjson = require "dkjson"
local curl = require("lcurl.safe")
local m_max = math.max
local s_format = string.format
local t_insert = table.insert
local tradeHelpers = LoadModule("Classes/TradeHelpers")
local synthUniqueTrade = LoadModule("Classes/SynthUniqueTrade")
local utils = LoadModule("Modules/Utils")

-- a table which tells us what subtypes each category we can search for
-- contains. the commented out lines are type-subtype combinations which don't
-- exist yet, but might exist in the future
local tradeCategoryNames = {
	["Ring"] = { "Ring" },
	["Amulet"] = { "Amulet" },
	["Belt"] = { "Belt" },
	["Chest"] = { "Body Armour", "Body Armour: Armour", "Body Armour: Armour/Energy Shield", "Body Armour: Armour/Evasion", "Body Armour: Armour/Evasion/Energy Shield", "Body Armour: Energy Shield", "Body Armour: Evasion", "Body Armour: Evasion/Energy Shield",
		-- "Body Armour: Ward"
	},
	["Helmet"] = { "Helmet", "Helmet: Armour", "Helmet: Armour/Energy Shield", "Helmet: Armour/Evasion",
		-- "Helmet: Armour/Evasion/Energy Shield",
		"Helmet: Energy Shield", "Helmet: Evasion", "Helmet: Evasion/Energy Shield", "Helmet: Ward" },
	["Gloves"] = { "Gloves: Armour", "Gloves: Armour/Energy Shield", "Gloves: Armour/Evasion",
		-- "Gloves: Armour/Evasion/Energy Shield",
		"Gloves: Energy Shield", "Gloves: Evasion", "Gloves: Evasion/Energy Shield", "Gloves: Ward" },
	["Boots"] = { "Boots", "Boots: Armour", "Boots: Armour/Energy Shield", "Boots: Armour/Evasion",
		-- "Boots: Armour/Evasion/Energy Shield",
		"Boots: Energy Shield", "Boots: Evasion", "Boots: Evasion/Energy Shield", "Boots: Ward" },
	["Quiver"] = { "Quiver" },
	["Shield"] = { "Shield", "Shield: Armour", "Shield: Armour/Energy Shield", "Shield: Armour/Evasion", "Shield: Energy Shield", "Shield: Evasion", "Shield: Evasion/Energy Shield" },
	["1HWeapon"] = { "Claw", "Dagger", "One Handed Axe", "One Handed Mace", "Wand", "Sceptre", "One Handed Sword", "One Handed Sword: Thrusting" },
	["2HWeapon"] = { "Staff", "Staff: Warstaff", "Two Handed Axe", "Two Handed Mace", "Two Handed Sword", "Bow" },
	["1HAxe"] = { "One Handed Axe" },
	["1HSword"] = { "One Handed Sword", "One Handed Sword: Thrusting" },
	["1HMace"] = { "One Handed Mace" },
	["Sceptre"] = { "Sceptre" },
	["Dagger"] = { "Dagger" },
	["Wand"] = { "Wand" },
	["Claw"] = { "Claw" },
	["Staff"] = { "Staff", "Staff: Warstaff" },
	["Bow"] = { "Bow" },
	["2HAxe"] = { "Two Handed Axe" },
	["2HSword"] = { "Two Handed Sword" },
	["2HMace"] = { "Two Handed Mace" },
	["FishingRod"] = { "Fishing Rod" },
	["BaseJewel"] = { "Jewel" },
	["AbyssJewel"] = { "Jewel: Abyss" },
	["AnyJewel"] = { "Jewel", "Jewel: Abyss" },
	["LifeFlask"] = { "Flask: Life" },
	["ManaFlask"] = { "Flask: Mana" },
	["Flask"] = { "Flask: Utility" },
}

local synthesisItemClassCategories = {
	["Amulet"] = { "Amulet" },
	["Ring"] = { "Ring" },
	["Belt"] = { "Belt" },
	["Body Armour"] = { "Chest" },
	["Helmet"] = { "Helmet" },
	["Gloves"] = { "Gloves" },
	["Boots"] = { "Boots" },
	["Quiver"] = { "Quiver" },
	["Shield"] = { "Shield" },
	["Claw"] = { "1HWeapon", "Claw" },
	["Dagger"] = { "1HWeapon", "Dagger" },
	["Rune Dagger"] = { "1HWeapon", "Dagger" },
	["Wand"] = { "1HWeapon", "Wand" },
	["One Hand Sword"] = { "1HWeapon", "1HSword" },
	["Thrusting One Hand Sword"] = { "1HWeapon", "1HSword" },
	["One Hand Axe"] = { "1HWeapon", "1HAxe" },
	["One Hand Mace"] = { "1HWeapon", "1HMace" },
	["Sceptre"] = { "1HWeapon", "1HMace", "Sceptre" },
	["Staff"] = { "2HWeapon", "Staff" },
	["Warstaff"] = { "2HWeapon", "Staff" },
	["Bow"] = { "2HWeapon", "Bow" },
	["Two Hand Sword"] = { "2HWeapon", "2HSword" },
	["Two Hand Axe"] = { "2HWeapon", "2HAxe" },
	["Two Hand Mace"] = { "2HWeapon", "2HMace" },
	["Fishing Rod"] = { "FishingRod" },
	["Jewel"] = { "BaseJewel", "AnyJewel" },
	["AbyssJewel"] = { "AbyssJewel", "AnyJewel" },
	["LifeFlask"] = { "LifeFlask" },
	["ManaFlask"] = { "ManaFlask" },
	["UtilityFlask"] = { "Flask" },
	["UtilityFlaskCritical"] = { "Flask" },
}
local basesForType
local synthesisCatalogDiagnosticsCache

local function canModSpawnForItemCategory(mod, category)
	-- lazy load type list as it's only required when generating QueryMods.lua
	if not basesForType then
		basesForType = {}
		for _, bases in pairs(data.itemBaseLists) do
			for _, base in ipairs(bases) do
				local base = base.base
				-- gather a table which maps from type: subtype to a list of bases
				if not base.hidden and base.type then
					local type = base.type
					local subType = base.subType
					if not basesForType[type] then
						basesForType[type] = {}
					end
					table.insert(basesForType[type], base)
					if subType then
						if not basesForType[type .. ": " .. subType] then
							basesForType[type .. ": " .. subType] = {}
						end
						table.insert(basesForType[type .. ": " .. subType], base)
					end
				end
			end
		end
	end
	-- mock item
	local itemClass = new("Item"):Item()
	local itemObj = {}
	-- add all influences to fake item
	for _, curInfluenceInfo in ipairs(itemLib.influenceInfo.all) do
		itemObj[curInfluenceInfo.key] = true
	end
	for _, type in ipairs(tradeCategoryNames[category]) do
		-- crafted mod
		if mod.types and mod.types[type] then
			return true
		elseif mod.weightKey then
			-- test if item can spawn for any base of the given type
			for _, base in ipairs(basesForType[type] or error("missing bases for type " .. type)) do
				itemObj.base = base
				if itemClass.GetModSpawnWeight(itemObj, mod) > 0 then
					return true
				end
			end
		end
	end
	return false
end
---@return table[]? category list of entries for the mod type
local function getStatEntries(modType)
	local tradeStats = tradeHelpers.getTradeStats()
	local tradeStatCategoryIndices = {
		["Explicit"] = "explicit",
		["WatchersEye"] = "explicit",
		["PassiveNode"] = "explicit",
		["Implicit"] = "implicit",
		["Synthesis"] = "implicit",
		["Corrupted"] = "implicit",
		["Eater"] = "implicit",
		["Exarch"] = "implicit",
		-- note that in the json the label is augment while the id is rune
		["Rune"] = "rune",
		["HeartOfTheWell"] = "explicit",
		["AgainstTheDarkness"] = "explicit",
		["pseudo"] = "pseudo",
		["Enchant"] = "enchant",
	}
	if tradeStatCategoryIndices[modType] then
		for _, cat in ipairs(tradeStats) do
			if cat.id == tradeStatCategoryIndices[modType] then
				return cat.entries
			end
		end
	end
end

local influenceDropdownNames = { "None" }
local hasInfluenceModIds = { }
for i, curInfluenceInfo in ipairs(itemLib.influenceInfo.default) do
	influenceDropdownNames[i + 1] = curInfluenceInfo.display
	hasInfluenceModIds[i] = "pseudo.pseudo_has_" .. string.lower(curInfluenceInfo.display) .. "_influence"
end

-- slots that allow eldritch mods (non-unique only)
local eldritchModSlots = {
	["Body Armour"] = true,
	["Helmet"] = true,
	["Gloves"] = true,
	["Boots"] = true
}

local MAX_FILTERS = 36

local function logToFile(...)
	ConPrintf(...)
end

---@class TradeQueryGenerator
local TradeQueryGeneratorClass = newClass("TradeQueryGenerator")

function TradeQueryGeneratorClass:TradeQueryGenerator(queryTab)
	self:InitMods()
	self.queryTab = queryTab
	self.itemsTab = queryTab.itemsTab
	self.calcContext = { }
	self.lastMaxPrice = nil
	self.lastMaxPriceTypeIndex = nil
	self.lastMaxLevel = nil
	return self
end

function TradeQueryGeneratorClass.WeightedRatioOutputs(baseOutput, newOutput, statWeights)
	local meanStatDiff = 0

	local function ratioModSums(...)
		local baseModSum = 0
		local newModSum = 0
		for _, mod in ipairs({ ... }) do
			baseModSum = baseModSum + data.powerStatList.GetFromOutput(baseOutput, mod, true)
			newModSum = newModSum + data.powerStatList.GetFromOutput(newOutput, mod, true)
		end

		if baseModSum == math.huge then
			return 0
		else
			if newModSum == math.huge then
				return data.misc.maxStatIncrease
			else
				return math.min(newModSum / ((baseModSum ~= 0) and baseModSum or 1), data.misc.maxStatIncrease)
			end
		end
	end
	for _, statTable in ipairs(statWeights) do
		local modSumRatio
		if statTable.stat == "FullDPS" and not (baseOutput["FullDPS"] and newOutput["FullDPS"]) then
			modSumRatio = ratioModSums({ stat = "TotalDPS" }, { stat = "TotalDotDPS" }, { stat = "CombinedDPS" })
		else
			modSumRatio = ratioModSums(statTable)
		end
		-- some weights, such as damage taken from hit need to be negated as lower is better for them
		if statTable.transform then
			modSumRatio = statTable.transform(modSumRatio)
		end
		meanStatDiff = meanStatDiff + modSumRatio * statTable.weightMult
	end
	return meanStatDiff
end

function TradeQueryGeneratorClass:ProcessMod(modId, mod, tradeQueryStatsParsed, itemCategoriesMask, itemCategoriesOverride, diagnostics)
	local function recordDiagnostic(line, reason)
		if diagnostics then
			diagnostics[tostring(modId) .. "\0" .. tostring(line)] = {
				modId = modId,
				line = line,
				reason = reason,
				categories = copyTable(itemCategoriesOverride or itemCategoriesMask or { }),
			}
		end
	end
	if type(modId) == "string" and modId:find("HellscapeDownside") ~= nil then -- skip scourge downsides, they often don't follow standard parsing rules, and should basically never be beneficial anyways
		goto continue
	end

	for index, modLine in ipairs(mod) do
		if modLine:find("Grants Level") or modLine:find("inflict Decay") then -- skip mods that grant skills / decay, as they will often be overwhelmingly powerful but don't actually fit into the build
			goto nextModLine
		end

		local statOrder = modLine:find("Nearby Enemies have %-") ~= nil and mod.statOrder[index + 1] or mod.statOrder[index] -- hack to get minus res mods associated with the correct statOrder
		local modType = (mod.type == "Prefix" or mod.type == "Suffix") and (type(modId) == "string" and modId:find("AfflictionNotable") and "PassiveNode" or "Explicit") or mod.type
		if modType == "ScourgeUpside" then modType = "Scourge" end

		-- Special cases
		local specialCaseData = { }
		if mod.group and (mod.group:find("Local") or mod.group:find("Shield")) and modLine:find("%% Chance to Block$") then
			specialCaseData.overrideModLine = "+#% Chance to Block"
			modLine = modLine .. " (Shields)"
		elseif modLine == "You can apply an additional Curse" then
			specialCaseData.overrideModLineSingular = "You can apply an additional Curse"
			modLine = "You can apply 1 additional Curses"
		elseif modLine == "Bow Attacks fire an additional Arrow" then
			specialCaseData.overrideModLineSingular = "Bow Attacks fire an additional Arrow"
			modLine = "Bow Attacks fire 1 additional Arrows"
		elseif modLine == "Projectiles Pierce an additional Target" then
			specialCaseData.overrideModLineSingular = "Projectiles Pierce an additional Target"
			modLine = "Projectiles Pierce 1 additional Targets"
		elseif modLine == "Has 1 Abyssal Socket" then
			specialCaseData.overrideModLineSingular = "Has 1 Abyssal Socket"
			modLine = "Has 1 Abyssal Sockets"
		elseif modLine == "Flasks gain a Charge every 3 seconds" then
			specialCaseData.overrideModLineSingular = "Flasks gain a Charge every 3 seconds"
			modLine = "Flasks gain 1 Charges every 3 seconds"
		elseif modLine:match("^Utility Flasks gain %d+ Charges every 3 seconds$") then
			specialCaseData.overrideModLine = "Utility Flasks gain # Charges every 3 seconds"
			modLine = modLine:gsub("Charges", "Charge")
		end

		-- If this is the first tier for this mod, find matching trade mod and init the entry
		if not self.modData[modType] then
			logToFile("Unhandled Mod Type: %s %s", modType, modLine)
			recordDiagnostic(modLine, "unsupported modifier type")
			goto continue
		end

		local uniqueIndex = tostring(statOrder).."_"..mod.group
		local inverse = false
		local inverseKey
		::reparseMod::
		if self.modData[modType][uniqueIndex] == nil then
			local tradeMod = nil
			-- Try to match to a local mod fallback to global if no match
			if mod.group:match("Local") then
				local matchLocalStr = (modLine .. " (Local)"):gsub("[#()0-9%-%+%.]","")
				for _, entry in pairs(getStatEntries(modType) or {}) do
					if entry.text:gsub("[#()0-9%-%+%.]","") == matchLocalStr then
						tradeMod = entry
						specialCaseData.overrideModLine = entry.text:sub(1,-9)
						break
					end
				end
			end
			if tradeMod == nil then
				local matchStr = modLine:gsub("[#()0-9%-%+%.]","")
				for _, entry in ipairs(getStatEntries(modType) or {}) do
					if entry.text:gsub("[#()0-9%-%+%.]","") == matchStr then
						tradeMod = entry
						break
					end
				end
			end
			if tradeMod == nil then
				if inverse then
					logToFile("Unable to match %s mod: %s", modType, modLine)
					recordDiagnostic(modLine, "no trade stat mapping")
					goto nextModLine
				else -- try swapping increased / decreased and signed and other similar mods.
					modLine, inverseKey = tradeHelpers.swapInverse(modLine)
					inverse = true
					if inverseKey then
						goto reparseMod
					else
						logToFile("Unable to match %s mod: %s", modType, modLine)
						recordDiagnostic(modLine, "no trade stat mapping")
						goto nextModLine
					end
				end
			end

			self.modData[modType][uniqueIndex] = { tradeMod = tradeMod, specialCaseData = specialCaseData, inverseKey = inverseKey }
		elseif self.modData[modType][uniqueIndex].inverseKey and modLine:match(self.modData[modType][uniqueIndex].inverseKey) then
			inverse = true
			modLine = tradeHelpers.swapInverse(modLine)
		end

		-- tokenize the numerical variables for this mod and store the sign if there is one
		local tokens = { }
		local poundPos, tokenizeOffset = 0, 0
		while true do
			poundPos = self.modData[modType][uniqueIndex].tradeMod.text:find("#", poundPos + 1)
			if poundPos == nil then
				break
			end

			local startPos, endPos, sign, min, max = modLine:find("([%+%-]?)%(?(%d+%.?%d*)%-?(%d*%.?%d*)%)?", poundPos + tokenizeOffset)

			if endPos == nil then
				logToFile("[GMD] Error extracting tokens from '%s' for tradeMod '%s'", modLine, self.modData[modType][uniqueIndex].tradeMod.text)
				recordDiagnostic(modLine, "could not parse numeric values")
				goto nextModLine
			end

			max = #max > 0 and tonumber(max) or tonumber(min)

			tokenizeOffset = tokenizeOffset + (endPos - startPos)
			
			if inverse then
				sign = nil
				min = -min
				max = -max
				if min > max then
					local temp = max
					max = min
					min = temp
				end
			end

			t_insert(tokens, min)
			t_insert(tokens, max)
			if sign ~= nil then
				self.modData[modType][uniqueIndex].sign = sign
			end
		end

		if #tokens ~= 0 and #tokens ~= 2 and #tokens ~= 4 then
			logToFile("Unexpected # of tokens found for mod: %s", mod[index])
			recordDiagnostic(modLine, "unsupported number of numeric values")
			goto nextModLine
		end

		-- Update the min and max values available for each item category
		for category, _ in pairs(itemCategoriesOverride or itemCategoriesMask or tradeCategoryNames) do
			if itemCategoriesOverride or canModSpawnForItemCategory(mod, category) then
				if self.modData[modType][uniqueIndex][category] == nil then
					self.modData[modType][uniqueIndex][category] = { min = 999999, max = -999999 }
				end

				local modRange = self.modData[modType][uniqueIndex][category]
				if #tokens == 0 then
					modRange.min = 1
					modRange.max = 1
				elseif #tokens == 2 then
					modRange.min = math.min(modRange.min, tokens[1])
					modRange.max = math.max(modRange.max, tokens[2])
				elseif #tokens == 4 then
					modRange.min = math.min(modRange.min, (tokens[1] + tokens[3]) / 2)
					modRange.max = math.max(modRange.max, (tokens[2] + tokens[4]) / 2)
				end
			end
		end
		::nextModLine::
	end
	::continue::
end

function TradeQueryGeneratorClass:GenerateModData(mods, tradeQueryStatsParsed, itemCategoriesMask, itemCategoriesOverride)
	for modId, mod in pairsSortByKey(mods) do
		self:ProcessMod(modId, mod, tradeQueryStatsParsed, itemCategoriesMask, itemCategoriesOverride)
	end
end

function TradeQueryGeneratorClass:GenerateSynthesisModData(tradeQueryStatsParsed)
	self.modData.Synthesis = self.modData.Synthesis or { }
	self.synthesisCatalogDiagnostics = { }
	synthesisCatalogDiagnosticsCache = self.synthesisCatalogDiagnostics
	for modId, mod in pairsSortByKey(data.itemMods.Synthesis) do
		local categoryMask = { }
		for itemClassId in pairs(data.synthesisModItemClasses[modId] or { }) do
			for _, category in ipairs(synthesisItemClassCategories[itemClassId] or { }) do
				categoryMask[category] = true
			end
		end
		if next(categoryMask) then
			self:ProcessMod(modId, mod, tradeQueryStatsParsed, nil, categoryMask, self.synthesisCatalogDiagnostics)
		else
			logToFile("Unable to determine Synthesis item categories for mod: %s", modId)
			self.synthesisCatalogDiagnostics[modId] = {
				modId = modId,
				line = table.concat(mod, " / "),
				reason = "unknown item category",
				categories = { },
			}
		end
	end
end

function TradeQueryGeneratorClass:InitMods()
	local queryModFilePath = "Data/QueryMods.lua"

	local file = io.open(queryModFilePath,"r")
	if file then
		file:close()
		---@module "src.Data.QueryMods"
		self.modData = LoadModule(queryModFilePath)
		if not self.modData.Synthesis then
			self:GenerateSynthesisModData()
		else
			self.synthesisCatalogDiagnostics = synthesisCatalogDiagnosticsCache or { }
		end
		return
	end

	-- Download stats JSON from GGG API. Do not use launch:DownloadPage here as it is async, and QueryMods.lua must use the freshly downloaded stats.
	local tradeStats = ""
	local easy = curl.easy()
	easy:setopt_url("https://www.pathofexile.com/api/trade/data/stats")
	easy:setopt_useragent("Path of Building/" .. launch.versionNumber)
	easy:setopt_writefunction(function(data)
		tradeStats = tradeStats .. data
		return true
	end)
	local ok = easy:perform()
	easy:close()
	if not ok or tradeStats == "" then
		error("Error while downloading stats.json")
	end
	local body = dkjson.decode(tradeStats)

	if body.error then
		error("Error received from api/trade/data/stats: " .. body.error.message)
	end

	local f = io.open("./Data/TradeSiteStats.lua", "w")
	if not f then
		error("Could not open file for writing trade stat data")
	end

	for catIdx, _ in ipairs(body.result) do
		table.sort(body.result[catIdx].entries, function(a, b)
			if a.text == b.text then
				return a.id < b.id
			end
			return a.text < b.text
		end)
	end

	local description = "This file contains the trade site data from https://www.pathofexile.com/api/trade/data/stats"
	utils.saveTableToFile("./Data/TradeSiteStats.lua", body.result, description)
	self.modData = {
		["Explicit"] = { },
		["Implicit"] = { },
		["Synthesis"] = { },
		["Enchant"] = {},
		["Corrupted"] = { },
		["Scourge"] = { },
		["Eater"] = { },
		["Exarch"] = {},
		["PassiveNode"] = { },
		["WatchersEye"] = { },
	}

	local tradeQueryStatsParsed = body

	-- Create second table only containing local mods this should speedup generation slightly
	tradeQueryStatsParsed.localResults = { }
	for modTypeId, modType in ipairs(tradeQueryStatsParsed.result) do
		tradeQueryStatsParsed.localResults[modTypeId] = { label = modType.label, entries = { } }
		for modId, mod in ipairs(modType.entries) do
			if mod.text:match("(Local)") then
				tradeQueryStatsParsed.localResults[modTypeId].entries[modId] = mod
			end
		end
	end

	-- explicit, corrupted, scourge, and jewel mods
	local regularItemMask = { }
	for category, _ in pairs(tradeCategoryNames) do
		if category ~= "Flask" and category ~= "AbyssJewel" and category ~= "BaseJewel" and category ~= "AnyJewel" then
			regularItemMask[category] = true
		end
	end
	for _, key in ipairs({ "Explicit", "Corrupted", "Delve", "Eldritch" }) do
		self:GenerateModData(data.itemMods[key], tradeQueryStatsParsed, regularItemMask)
	end
	self:GenerateModData(data.itemMods.Jewel, tradeQueryStatsParsed, { ["BaseJewel"] = true, ["AnyJewel"] = true })
	self:GenerateModData(data.itemMods.JewelAbyss, tradeQueryStatsParsed, { ["AbyssJewel"] = true, ["AnyJewel"] = true },
		{ ["AbyssJewel"] = true })
	self:GenerateModData(data.itemMods.Flask, tradeQueryStatsParsed, { ["Flask"] = true })

	-- Synthesis implicits no longer have spawn weights in Mods.dat. Their item
	-- class restrictions are exported from ItemSynthesisMods.dat instead.
	self:GenerateSynthesisModData(tradeQueryStatsParsed)

	-- Special handling for essences
	for _, essenceItem in pairs(data.essences) do
		for itemType, modId in pairs(essenceItem.mods) do
			local mask = {}
			mask[itemType] = true
			self:ProcessMod(modId, data.itemMods.Item[modId], tradeQueryStatsParsed, regularItemMask, mask)
		end
	end

	regularItemMask.Flask = true -- Update mask as flasks can have crafted mods.
	self:GenerateModData(data.masterMods, tradeQueryStatsParsed, regularItemMask)
	self:GenerateModData(data.veiledMods, tradeQueryStatsParsed, regularItemMask)

	-- megalomaniac
	local clusterNotableMods = {}
	for k, v in pairs(data.itemMods.JewelCluster) do
		if k:find("AfflictionNotable") then
			clusterNotableMods[k] = v
		end
	end
	self:GenerateModData(clusterNotableMods, tradeQueryStatsParsed)

	-- Watcher's Eye
	local watchersEyeMods = {}
	for _,v in pairs(data.uniqueMods["Watcher's Eye"]) do
		if v.Id:find("SublimeVision") or v.Id:find("SummonArbalist") then
			goto continue
		end
		watchersEyeMods[v.Id] = v.mod
		watchersEyeMods[v.Id].type = "WatchersEye"
		::continue::
	end
	self:GenerateModData(watchersEyeMods, tradeQueryStatsParsed, { ["BaseJewel"] = true, ["AnyJewel"] = true },
		{ ["AnyJewel"] = "AnyJewel" })

	-- implicit mods
	local function processBaseMod(baseEntry, modId, modType)
		local mod = copyTable(data.itemMods.ItemExclusive[modId] or error("mod id doesn't exist " .. modId))
		mod.type = modType

		-- create trade type mask for base type
		local maskOverride = {}
		for tradeName, typeNames in pairs(tradeCategoryNames) do
			for _, typeName in ipairs(typeNames) do
				local entryName = baseEntry.type
				if modType == "Implicit" and baseEntry.subType then
					entryName = entryName .. ": " .. baseEntry.subType
				end
				if typeName == entryName then
					maskOverride[tradeName] = true;
					break
				end
			end
		end

		-- A mask avoids processing mods from unimplemented base types
		if next(maskOverride) ~= nil then
			self:ProcessMod("", mod, tradeQueryStatsParsed, regularItemMask, maskOverride)
		end
	end
	for _, entry in pairsSortByKey(data.itemBases) do
		if entry.type == "Graft" then
			goto continue
		end
		for _, modId in ipairs(entry.implicitIds or {}) do
			processBaseMod(entry, modId, "Implicit")
		end
		-- talismans have implicit-like enchants on the bases
		for _, modId in ipairs(entry.enchantIds or {}) do
			processBaseMod(entry, modId, "Enchant")
		end
		::continue::
	end

	local qmDescription = [[This file contains categories of stats, mapped from an unique id to details
relevant for generating search weights.
See TradeSiteStats.lua for a list of all trade site stats.]]
	utils.saveTableToFile(queryModFilePath, self.modData, qmDescription)
end

function TradeQueryGeneratorClass:GenerateModWeights(modsToTest)
	local start = GetTime()
	for _, entry in pairs(modsToTest) do
		if entry[self.calcContext.itemCategory] ~= nil then
			if self.alreadyWeightedMods[entry.tradeMod.id] ~= nil then -- Don't calculate the same thing twice (can happen with corrupted vs implicit)
				goto continue
			elseif self.calcContext.options.includeTalisman == false and entry[self.calcContext.itemCategory].subType == "Talisman" then -- Talisman implicits take up a lot of query slots, so we have an option to skip them
				goto continue
			end

			-- Test with a value halfway (or configured default Item Affix Quality) between the min and max available for this mod in this slot. Note that this can generate slightly different values for the same mod as implicit vs explicit.
			local modValue = math.ceil((entry[self.calcContext.itemCategory].max - entry[self.calcContext.itemCategory].min) * ( main.defaultItemAffixQuality or 0.5 ) + entry[self.calcContext.itemCategory].min)
			local modValueStr = (entry.sign and entry.sign or "") .. tostring(modValue)

			-- Apply override text for special cases
			local modLine
			if modValue == 1 and entry.specialCaseData.overrideModLineSingular ~= nil then
				modLine = entry.specialCaseData.overrideModLineSingular
			elseif entry.specialCaseData.overrideModLine ~= nil then
				modLine = entry.specialCaseData.overrideModLine
			else
				modLine = entry.tradeMod.text
			end
			modLine = modLine:gsub("#",modValueStr)

			if self.calcContext.synthUnique then
				self.calcContext.testItem.implicitModLines[1] = {
					line = modLine,
					custom = true,
					implicit = true,
					synthesis = true,
				}
			else
				self.calcContext.testItem.explicitModLines[1] = { line = modLine, custom = true }
			end
			self.calcContext.testItem:BuildAndParseRaw()

			local testedImplicit = self.calcContext.synthUnique and self.calcContext.testItem.implicitModLines[1]
			local failedToParse = self.calcContext.synthUnique and (not testedImplicit or testedImplicit.extra
				or not testedImplicit.modList or #testedImplicit.modList == 0)
				or not self.calcContext.synthUnique and ((self.calcContext.testItem.modList ~= nil and #self.calcContext.testItem.modList == 0)
					or (self.calcContext.testItem.slotModList ~= nil and #self.calcContext.testItem.slotModList[1] == 0 and #self.calcContext.testItem.slotModList[2] == 0))
			if failedToParse then
				logToFile("Failed to test %s mod: %s", self.calcContext.itemCategory, modLine)
				if self.calcContext.synthUnique then
					t_insert(self.calcContext.synthUnique.omittedImplicits, {
						line = modLine,
						reason = "could not be parsed for calculation",
					})
					goto continue
				end
			end

			local output = self.calcContext.calcFunc({ repSlotName = self.calcContext.slot.slotName, repItem = self.calcContext.testItem })
			local meanStatDiff = TradeQueryGeneratorClass.WeightedRatioOutputs(self.calcContext.baseOutput, output, self.calcContext.options.statWeights) * 1000 - (self.calcContext.baseStatValue or 0)
			if meanStatDiff > 0.01 then
				t_insert(self.modWeights, { tradeModId = entry.tradeMod.id, weight = meanStatDiff / modValue, meanStatDiff = meanStatDiff, invert = entry.sign == "-" and true or false })
			end
			self.alreadyWeightedMods[entry.tradeMod.id] = true

			local now = GetTime()
			if now - start > 50 then
				-- Would be nice to update x/y progress on the popup here, but getting y ahead of time has a cost, and the visual seems to update on a significant delay anyways so it's not very useful
				coroutine.yield()
				start = now
			end
		end
		::continue::
	end
end

function TradeQueryGeneratorClass:GeneratePassiveNodeWeights(nodesToTest)
	local start = GetTime()
	for _, entry in pairs(nodesToTest) do
		if self.alreadyWeightedMods[entry.tradeMod.id] ~= nil then
			goto continue
		end
		
		local nodeName = entry.tradeMod.text:match("1 Added Passive Skill is (.*)") or entry.tradeMod.text:match("Allocates (.*)")
		if not nodeName then
			goto continue
		end
		local node = self.itemsTab.build.spec.tree.clusterNodeMap[nodeName] or self.itemsTab.build.spec.tree.notableMap[nodeName]

		local baseOutput = self.calcContext.baseOutput
		local output = self.calcContext.calcFunc({ addNodes = { [node] = true } })
		local meanStatDiff = TradeQueryGeneratorClass.WeightedRatioOutputs(baseOutput, output, self.calcContext.options.statWeights) * 1000 - (self.calcContext.baseStatValue or 0)
		if meanStatDiff > 0.01 then
			t_insert(self.modWeights, { tradeModId = entry.tradeMod.id, weight = meanStatDiff, meanStatDiff = meanStatDiff, invert = false })
		end
		self.alreadyWeightedMods[entry.tradeMod.id] = true

		local now = GetTime()
		if now - start > 50 then
			-- Would be nice to update x/y progress on the popup here, but getting y ahead of time has a cost, and the visual seems to update on a significant delay anyways so it's not very useful
			coroutine.yield()
			start = now
		end
		::continue::
	end
end

function TradeQueryGeneratorClass:OnFrame()
	if self.calcContext.co == nil then
		return
	end

	local res, errMsg = coroutine.resume(self.calcContext.co, self)
	if launch.devMode and not res then
		error(errMsg)
	end
	if coroutine.status(self.calcContext.co) == "dead" then
		self.calcContext.co = nil
		self:FinishQuery()
	end
end

local currencyTable = {
	{ name = "Chaos Orb Equivalent", id = nil },
	{ name = "Chaos Orb", id = "chaos" },
	{ name = "Divine Orb", id = "divine" },
	{ name = "Orb of Alchemy", id = "alch" },
	{ name = "Orb of Alteration", id = "alt" },
	{ name = "Chromatic Orb", id = "chrome" },
	{ name = "Exalted Orb", id = "exalted" },
	{ name = "Blessed Orb", id = "blessed" },
	{ name = "Cartographer's Chisel", id = "chisel" },
	{ name = "Gemcutter's Prism", id = "gcp" },
	{ name = "Jeweller's Orb", id = "jewellers" },
	{ name = "Orb of Scouring", id = "scour" },
	{ name = "Orb of Regret", id = "regret" },
	{ name = "Orb of Fusing", id = "fusing" },
	{ name = "Orb of Chance", id = "chance" },
	{ name = "Regal Orb", id = "regal" },
	{ name = "Vaal Orb", id = "vaal" }
}

local function getTradeStatIdSet(categoryId)
	local result = { }
	for _, category in ipairs(tradeHelpers.getTradeStats() or { }) do
		if category.id == categoryId then
			for _, entry in ipairs(category.entries or { }) do
				local tradeId = entry.id:match("^(.-)|") or entry.id
				result[tradeId] = true
			end
			break
		end
	end
	return result
end

local function findConfiguredModLine(item, modifier)
	local direct = item.explicitModLines and item.explicitModLines[modifier.lineIndex]
	if direct and item:CheckModLineVariant(direct)
		and synthUniqueTrade.modLineTemplate(direct.line) == modifier.template then
		return direct.line
	end
	local occurrence = 0
	for _, modLine in ipairs(item.explicitModLines or { }) do
		if item:CheckModLineVariant(modLine)
			and synthUniqueTrade.modLineTemplate(modLine.line) == modifier.template then
			occurrence = occurrence + 1
			if occurrence == modifier.occurrence then
				return modLine.line
			end
		end
	end
end

local uniqueModTradeHashMap
local function getUniqueModTradeIds(modifier, explicitStatIds)
	if not uniqueModTradeHashMap then
		uniqueModTradeHashMap = { }
		for modId, mod in pairs(data.itemMods.ItemExclusive) do
			for _, line in ipairs(mod) do
				local key = line:gsub("\n", " "):lower()
				uniqueModTradeHashMap[key] = uniqueModTradeHashMap[key] or { }
				for hash, hashLines in pairs(mod.tradeHashes or { }) do
					for _, hashLine in ipairs(hashLines) do
						if hashLine:gsub("\n", " "):lower() == key then
							t_insert(uniqueModTradeHashMap[key], {
								tradeId = "explicit.stat_" .. tostring(hash),
								modId = modId,
								group = mod.group,
							})
							break
						end
					end
				end
			end
		end
	end
	local candidates = uniqueModTradeHashMap[modifier.line:gsub("\n", " "):lower()] or { }
	local preferReservationEfficiency = modifier.line:find("Mana Reservation Efficiency", 1, true)
	local result = { }
	local seen = { }
	for _, candidate in ipairs(candidates) do
		local preferred = not preferReservationEfficiency
			or tostring(candidate.modId):find("ReservationEfficiency", 1, true)
			or tostring(candidate.group):find("ReservationEfficiency", 1, true)
		if preferred and explicitStatIds[candidate.tradeId] and not seen[candidate.tradeId] then
			seen[candidate.tradeId] = true
			t_insert(result, candidate.tradeId)
		end
	end
	return result
end

-- Resolve enabled unique modifier assumptions to unambiguous explicit trade
-- filters. This also records the beneficial direction used when fetched rolls
-- are compared with their assumptions.
---@param baseline Item
---@param modifiers table[]
---@return table[] requiredMods
---@return string[] errors
function TradeQueryGeneratorClass:ResolveSynthUniqueRequirements(baseline, modifiers)
	local requiredMods = { }
	local errors = { }
	local explicitStatIds = getTradeStatIdSet("explicit")
	for _, modifier in ipairs(modifiers or { }) do
		if modifier.selected then
			local resolvedLine = findConfiguredModLine(baseline, modifier)
			if not resolvedLine then
				t_insert(errors, s_format("Selected modifier is not active on this unique: %s", modifier.line))
				goto continue
			end
			if #modifier.ranges > 1 and not resolvedLine:match("^Adds .+ to .+") then
				t_insert(errors, s_format("Selected modifier has an ambiguous multi-value trade mapping: %s", modifier.line))
				goto continue
			end
			local optionTradeId = tradeHelpers.findTradeIdOption(resolvedLine, "explicit")
			if optionTradeId then
				t_insert(errors, s_format("Selected modifier maps to an option rather than a numeric threshold: %s", modifier.line))
				goto continue
			end
			local hashes, value, invert = tradeHelpers.findTradeHash(resolvedLine)
			local tradeIds = getUniqueModTradeIds(modifier, explicitStatIds)
			if #tradeIds == 0 then
				local seen = { }
				for _, hash in ipairs(hashes or { }) do
					local tradeId = "explicit.stat_" .. tostring(hash)
					if explicitStatIds[tradeId] and not seen[tradeId] then
						seen[tradeId] = true
						t_insert(tradeIds, tradeId)
					end
				end
			end
			value = value or tradeHelpers.modLineValue(resolvedLine)
			if #tradeIds ~= 1 or value == nil then
				t_insert(errors, s_format("Selected modifier could not be mapped to one numeric trade stat: %s", modifier.line))
				goto continue
			end
			modifier.tradeId = tradeIds[1]
			modifier.invert = invert == true
			modifier.tradeValue = invert and -value or value
			t_insert(requiredMods, {
				tradeId = modifier.tradeId,
				value = modifier.tradeValue,
				filterValue = { min = modifier.tradeValue },
			})
		end
		::continue::
	end
	return requiredMods, errors
end

function TradeQueryGeneratorClass:StartQuery(slot, options)
	if self.lastMaxPrice then
		options.maxPrice = self.lastMaxPrice
	end
	if self.lastMaxPriceTypeIndex then
		options.maxPriceType = currencyTable[self.lastMaxPriceTypeIndex].id
	end
	if self.lastMaxLevel then
		options.maxLevel = self.lastMaxLevel
	end

	-- Figure out what type of item we're searching for
	local synthUnique = options.synthUnique
	local existingItem = synthUnique and synthUnique.baseline or slot and self.itemsTab.items[slot.selItemId]
	local testItemType = existingItem and existingItem.baseName or "Unset Amulet"
	local itemCategoryQueryStr
	local itemCategory
	local special = { }
	if synthUnique then
		synthUnique.omittedImplicits = synthUnique.omittedImplicits or { }
		itemCategoryQueryStr, itemCategory = tradeHelpers.getTradeCategory(slot.slotName, existingItem)
		if existingItem.type == "Jewel" then
			itemCategory = existingItem.base and existingItem.base.subType == "Abyss" and "AbyssJewel" or "BaseJewel"
			itemCategoryQueryStr = existingItem.base and existingItem.base.subType == "Abyss" and "jewel.abyss" or "jewel.base"
		end
		local seenDiagnostics = { }
		for _, diagnostic in pairs(self.synthesisCatalogDiagnostics or { }) do
			if diagnostic.categories[itemCategory] and not seenDiagnostics[diagnostic.line] then
				seenDiagnostics[diagnostic.line] = true
				t_insert(synthUnique.omittedImplicits, copyTable(diagnostic))
			end
		end
		special = {
			queryExtra = {
				name = synthUnique.item.title or synthUnique.item.name,
				type = synthUnique.item.baseName,
			},
			queryFilters = {
				type_filters = {
					filters = {
						category = { option = itemCategoryQueryStr },
						rarity = { option = "unique" },
					}
				}
			},
		}
	elseif options.special then
		if options.special.itemName == "Megalomaniac" then
			special = {
				queryFilters = {},
				queryExtra = {
					name = "Megalomaniac",
					type = "Medium Cluster Jewel"
				},
				calcNodesInsteadOfMods = true,
			}
		end
		if options.special.itemName == "Watcher's Eye" then
			special = {
				queryExtra = {
					name = "Watcher's Eye"
				},
				queryFilters = {
					type_filters = {
						filters = {
							category = {
								option = "jewel"
							},
							rarity = {
								option = "unique"
							}
						}
					}
				},
				watchersEye = true
			}
			itemCategory = "AnyJewel"
			itemCategoryQueryStr = "jewel"
		end
	else
		itemCategoryQueryStr, itemCategory = tradeHelpers.getTradeCategory(slot.slotName, existingItem)

		-- Generic Jewel slot: caller selects the jewel subtype.
		if slot.slotName:find("Jewel") ~= nil and not slot.slotName:find("Abyssal") then
			itemCategory = options.jewelType .. "Jewel"
			if itemCategory == "AbyssJewel" then
				itemCategoryQueryStr = "jewel.abyss"
			elseif itemCategory == "BaseJewel" then
				itemCategoryQueryStr = "jewel.base"
			else
				itemCategoryQueryStr = "jewel"
			end
		end

		if not itemCategoryQueryStr then
			logToFile("'%s' is not supported for weighted trade query generation", existingItem and existingItem.type or "n/a")
			return
		end
	end

	-- Create a temp item for the slot with no mods
	local itemRawStr = "Rarity: RARE\nStat Tester\n" .. testItemType
	local testItem = synthUnique and new("Item"):Item(synthUnique.baseline:BuildRaw()) or new("Item"):Item(itemRawStr)

	-- Apply any requests influences
	if not synthUnique and options.influence1 > 1 then
		testItem[itemLib.influenceInfo.default[options.influence1 - 1].key] = true
	end
	if not synthUnique and options.influence2 > 1 then
		testItem[itemLib.influenceInfo.default[options.influence2 - 1].key] = true
	end

	-- Calculate base output with a blank item
	local calcFunc, baseOutput = self.itemsTab.build.calcsTab:GetMiscCalculator()
	local baseItemOutput = slot and calcFunc({ repSlotName = slot.slotName, repItem = testItem }) or baseOutput
	-- make weights more human readable
	local compStatValue = TradeQueryGeneratorClass.WeightedRatioOutputs(baseOutput, baseItemOutput, options.statWeights) * 1000

	-- Test each mod one at a time and cache the normalized Stat (configured earlier) diff to use as weight
	self.modWeights = { }
	self.alreadyWeightedMods = { }

	self.calcContext = {
		itemCategoryQueryStr = itemCategoryQueryStr,
		itemCategory = itemCategory,
		special = special,
		testItem = testItem,
		baseOutput = baseOutput,
		baseStatValue = compStatValue,
		calcFunc = calcFunc,
		options = options,
		slot = slot,
		requiredMods = options.requiredMods,
		synthUnique = synthUnique,
	}

	-- OnFrame will pick this up and begin the work
	self.calcContext.co = coroutine.create(self.ExecuteQuery)

	-- Open progress tracking blocker popup
	local controls = { }
	controls.progressText = new("LabelControl"):LabelControl({"TOP",nil,"TOP"}, {0, 30, 0, 16}, string.format("Calculating Mod Weights..."))
	self.calcContext.popup = main:OpenPopup(280, 65, "Please Wait", controls)
end

function TradeQueryGeneratorClass:ExecuteQuery()
	if self.calcContext.synthUnique then
		self:GenerateModWeights(self.modData.Synthesis)
		return
	end
	if self.calcContext.special.calcNodesInsteadOfMods then
		self:GeneratePassiveNodeWeights(self.modData.PassiveNode)
		return
	end
	if self.calcContext.special.watchersEye then
		self:GenerateModWeights(self.modData.WatchersEye)
		if self.calcContext.options.includeCorrupted then
			self:GenerateModWeights(self.modData["Corrupted"])
		end
		return
	end
	self:GenerateModWeights(self.modData["Explicit"])
	self:GenerateModWeights(self.modData["Implicit"])
	if self.calcContext.options.includeCorrupted then
		self:GenerateModWeights(self.modData["Corrupted"])
	end
	if self.calcContext.options.includeTalisman then
		self:GenerateModWeights(self.modData["Enchant"])
	end
	if self.calcContext.options.includeScourge then
		self:GenerateModWeights(self.modData["Scourge"])
	end
	local eldritchOption = self.calcContext.options.includeEldritch
	if eldritchOption and eldritchOption:find("^Keep") and
		-- skip weights if we need an influenced item as they can produce really
		-- bad results due to the filter limit
		self.calcContext.options.influence1 == 1 and
		self.calcContext.options.influence2 == 1 then
		local omitConditional = eldritchOption == "Keep regular"
		local eaterMods = self.modData["Eater"]
		local exarchMods = self.modData["Exarch"]
		if omitConditional then
			local function filterMods(mods)
				local filtered = {}
				for name, mod in pairs(mods) do
					-- the user might want to skip these because they're generally
					-- not used much, but there are a lot of them and the higher
					-- power causes them to take up a lot of filter slots
					if not name:match(".*PinnaclePresence$") and not name:match(".*UniquePresence$") then
						filtered[name] = mod
					end
				end
				return filtered
			end
			eaterMods = filterMods(self.modData["Eater"])
			exarchMods = filterMods(self.modData["Exarch"])
		end
		self:GenerateModWeights(eaterMods)
		self:GenerateModWeights(exarchMods)
	end
end

function TradeQueryGeneratorClass:addMoreWEMods()
	local function getTableOfTradeModIds(tbl)
		local tmpTable={}
		for _,val in ipairs(tbl) do
			table.insert(tmpTable,val.tradeModId)
		end
		return tmpTable
	end
	for _,skillGroup in ipairs(self.itemsTab.build.skillsTab.socketGroupList) do
		for _,gem in ipairs(skillGroup.gemList) do
			local tmpAura=""
			if not gem.enabled then
				goto continue
			elseif gem.nameSpec:find("Vaal") and gem.enableGlobal2 then
				tmpAura=gem.nameSpec:gsub("Vaal ",""):gsub("Impurity","Purity"):gsub("of","Of"):gsub(" ","")
			elseif gem.gemData and gem.gemData.tags.aura or gem.fromItem then
				tmpAura=gem.nameSpec:gsub("of","Of"):gsub(" ","")
			else
				goto continue
			end
			for id,mod in pairs(self.modData.WatchersEye) do
				if id:find(tmpAura) and not isValueInTable(getTableOfTradeModIds(self.modWeights),mod.tradeMod.id) then
					table.insert(self.modWeights,{invert=false,meanStatDiff=0,weight=0,tradeModId=mod.tradeMod.id})
				end
			end
			::continue::
		end
	end
end

function TradeQueryGeneratorClass:FinishQuery()
	-- Calc original item Stats without anoint or enchant, and use that diff as a basis for default min sum.
	local originalItem = self.calcContext.slot and self.itemsTab.items[self.calcContext.slot.selItemId]
	if self.calcContext.synthUnique then
		self.calcContext.testItem = new("Item"):Item(self.calcContext.synthUnique.baseline:BuildRaw())
	else
		self.calcContext.testItem.explicitModLines = { }
	end
	if originalItem and not self.calcContext.synthUnique then
		for _, modLine in ipairs(originalItem.explicitModLines) do
			t_insert(self.calcContext.testItem.explicitModLines, modLine)
		end
		for _, modLine in ipairs(originalItem.scourgeModLines) do
			t_insert(self.calcContext.testItem.explicitModLines, modLine)
		end
		for _, modLine in ipairs(originalItem.implicitModLines) do
			t_insert(self.calcContext.testItem.explicitModLines, modLine)
		end
		for _, modLine in ipairs(originalItem.crucibleModLines) do
			t_insert(self.calcContext.testItem.explicitModLines, modLine)
		end
	end
	self.calcContext.testItem:BuildAndParseRaw()

	local originalOutput = (originalItem or self.calcContext.synthUnique) and self.calcContext.calcFunc({ repSlotName = self.calcContext.slot.slotName, repItem = self.calcContext.testItem }) or self.calcContext.baseOutput
	local currentStatDiff = self.calcContext.synthUnique and 0 or TradeQueryGeneratorClass.WeightedRatioOutputs(self.calcContext.baseOutput, originalOutput, self.calcContext.options.statWeights) * 1000 - (self.calcContext.baseStatValue or 0)
	
	if self.calcContext.options.includeAllWEMods then
		self:addMoreWEMods()
	end

	-- Sort by mean Stat diff rather than weight to more accurately prioritize stats that can contribute more
	table.sort(self.modWeights, function(a, b)
		if a.meanStatDiff == b.meanStatDiff then
			return math.abs(a.weight) > math.abs(b.weight)
		end
		return a.meanStatDiff > b.meanStatDiff
	end)

	-- A megalomaniac is not being compared to anything and the currentStatDiff will be 0, so just go for an arbitrary min weight - in this case triple the weight of the worst evaluated node.
	local megalomaniacSpecialMinWeight = self.calcContext.special.itemName == "Megalomaniac" and self.modWeights[#self.modWeights] * 3
	-- This Stat diff value will generally be higher than the weighted sum of the same item, because the stats are all applied at once and can thus multiply off each other.
	-- So apply a modifier to get a reasonable min and hopefully approximate that the query will start out with small upgrades.
	local minWeight = megalomaniacSpecialMinWeight or currentStatDiff * 0.5

	-- what the trade site API uses for instant buyout etc.
	self.tradeTypes = {
		"securable",
		"available",
		"onlineleague",
		"online",
		"any",
	}
	local selectedTradeType = self.tradeTypes[self.tradeTypeIndex]
	-- Generate trade query str and open in browser
	local filters = 0
	local requiredMods = self.calcContext.requiredMods or {}
	local queryTable = {
		query = {
			filters = self.calcContext.special.queryFilters or {
				type_filters = {
					filters = {
						category = { option = self.calcContext.itemCategoryQueryStr },
						rarity = { option = "nonunique" }
					}
				}
			},
			status = { option = selectedTradeType },
			stats = {
				{
					type = "weight",
					value = { min = minWeight },
					filters = { }
				}
			}
		},
		sort = { ["statgroup.0"] = "desc" },
		engine = "new"
	}
	local requiredModFilters
	if #requiredMods > 0 then
		requiredModFilters = {
			type = "and",
			filters = {}
		}
		t_insert(queryTable.query.stats, requiredModFilters)
	end

	local options = self.calcContext.options

	local num_extra = 2
	if not options.includeMirrored then
		num_extra = num_extra + 1
	end
	if options.maxPrice and options.maxPrice > 0 then
		num_extra = num_extra + 1
	end
	if options.maxLevel and options.maxLevel > 0 then
		num_extra = num_extra + 1
	end
	if options.sockets and options.sockets > 0 then
		num_extra = num_extra + 1
	end
	if options.links and options.links > 0 then
		num_extra = num_extra + 1
	end

	local effective_max = MAX_FILTERS - num_extra - #requiredMods
	if effective_max < 1 then
		local errMsg = "Could not generate search: required filters exceed the trade site's filter limit"
		self.requesterCallback(self.requesterContext, nil, errMsg)
		main:ClosePopup()
		return
	end

	local pseudoMap = {
		["3372524247"] = "pseudo.pseudo_total_fire_resistance",
		["4220027924"] = "pseudo.pseudo_total_cold_resistance",
		["1671376347"] = "pseudo.pseudo_total_lightning_resistance",
		["2923486259"] = "pseudo.pseudo_total_chaos_resistance",
		["4080418644"] = "pseudo.pseudo_total_strength",
		["3261801346"] = "pseudo.pseudo_total_dexterity",
		["328541901"] = "pseudo.pseudo_total_intelligence",
	}
	local ignoredStats = {
		-- % all resistances
		["2901986750"] = true,
		-- all attributes
		["1379411836"] = true,
		["2897413282"] = true,
	}
	-- block all hybrid resistance stats
	local resElements = { "fire", "cold", "lightning", "chaos" }
	for _, elem1 in ipairs(resElements) do
		for _, elem2 in ipairs(resElements) do
			local stats = { string.format("%s_and_%s_damage_resistance_%%", elem1, elem2) }
			ignoredStats[tostring(HashStats(stats))] = true
		end
	end
	-- block all hybrid attribute stats
	local attributeElements = { "dexterity", "strength", "intelligence" }
	for _, elem1 in ipairs(attributeElements) do
		for _, elem2 in ipairs(attributeElements) do
			local stats = { string.format("base_%s_and_%s", elem1, elem2) }
			ignoredStats[tostring(HashStats(stats))] = true
			stats = { string.format("additional_%s_and_%s", elem1, elem2) }
			ignoredStats[tostring(HashStats(stats))] = true
		end
	end
	local statFilters = {}
	local pseudoMods = {}
	for _, entry in ipairs(self.modWeights) do
		local hash = entry.tradeModId:match("stat_(%d+)")
		local filterEntry = { id = entry.tradeModId, value = { weight = (entry.invert == true and entry.weight * -1 or entry.weight) } }
		-- avoid adding hybrid stats since we get the weight for them from
		-- individual stats
		if ignoredStats[hash] then
			goto weightContinue
		elseif pseudoMap[hash] then
			local tradeId = pseudoMap[hash]
			filterEntry.id = tradeId
			-- avoid adding duplicate pseudo filters: update existing
			if pseudoMods[tradeId] then
				pseudoMods[tradeId].value.weight = math.max(filterEntry.value.weight, pseudoMods[tradeId].value.weight)
			else
				pseudoMods[tradeId] = filterEntry
				table.insert(statFilters, filterEntry)
			end
		else
			table.insert(statFilters, filterEntry)
		end

		::weightContinue::
	end

	for k, v in pairs(self.calcContext.special.queryExtra or {}) do
		queryTable.query[k] = v
	end

	local andFilters = { type = "and", filters = { } }
	local options = self.calcContext.options
	if options.influence1 > 1 then
		t_insert(andFilters.filters, { id = hasInfluenceModIds[options.influence1 - 1] })
		filters = filters + 1
	end
	if options.influence2 > 1 then
		t_insert(andFilters.filters, { id = hasInfluenceModIds[options.influence2 - 1] })
		filters = filters + 1
	end

	if #andFilters.filters > 0 then
		t_insert(queryTable.query.stats, andFilters)
	end
	
	for _, entry in ipairs(statFilters) do
		t_insert(queryTable.query.stats[1].filters, entry)
		filters = filters + 1
		if filters == effective_max then
			break
		end
	end
	for _, entry in ipairs(requiredMods) do
		t_insert(requiredModFilters.filters, { id = entry.tradeId, value = entry.filterValue or { min = entry.value } })
	end
	if not options.includeMirrored or self.calcContext.synthUnique then
		queryTable.query.filters.misc_filters = queryTable.query.filters.misc_filters or {
			disabled = false,
			filters = { },
		}
		if not options.includeMirrored then
			queryTable.query.filters.misc_filters.filters.mirrored = false
		end
		if self.calcContext.synthUnique then
			queryTable.query.filters.misc_filters.filters.synthesised_item = { option = "true" }
			queryTable.query.filters.misc_filters.filters.corrupted = { option = "false" }
		end
	end

	if options.maxPrice and options.maxPrice > 0 then
		queryTable.query.filters.trade_filters = {
			filters = {
				price = {
					option = options.maxPriceType,
					max = options.maxPrice
				}
			}
		}
	end

	if options.account then
		queryTable.query.filters.trade_filters.filters.account = {input = options.account}
	end

	if options.maxLevel and options.maxLevel > 0 then
		queryTable.query.filters.req_filters = {
			disabled = false,
			filters = {
				lvl = {
					max = options.maxLevel
				}
			}
		}
	end

	if options.sockets and options.sockets > 0 then
		queryTable.query.filters.socket_filters = {
			disabled = false,
			filters = {
				sockets = {
					max = options.sockets,
					min = options.sockets
				}
			}
		}
	end

	if options.links and options.links > 0 then
		if not queryTable.query.filters.socket_filters then
			queryTable.query.filters.socket_filters = {
				disabled = false,
				filters = {
					links = {
						max = options.links,
						min = options.links
					}
				}
			}
		else -- do not overwrite options.sockets
			queryTable.query.filters.socket_filters.filters["links"] = {
				max = options.links,
				min = options.links
			}
		end
	end

	local errMsg = nil
	if #queryTable.query.stats[1].filters == 0 then
		-- No mods to filter
		errMsg = "Could not generate search, found no mods to search for"
	end
	if self.calcContext.synthUnique and #self.calcContext.synthUnique.omittedImplicits > 0 then
		local uniqueOmissions = { }
		local details = { }
		for _, omission in ipairs(self.calcContext.synthUnique.omittedImplicits) do
			local key = tostring(omission.line) .. "\0" .. tostring(omission.reason)
			if not uniqueOmissions[key] then
				uniqueOmissions[key] = true
				t_insert(details, s_format("%s (%s)", omission.line, omission.reason))
			end
		end
		self.calcContext.synthUnique.warning = s_format(
			"Omitted %d synthesis implicit%s that could not be parsed or mapped.",
			#details, #details == 1 and "" or "s")
		self.calcContext.synthUnique.warningDetails = details
	end

	local queryJson = dkjson.encode(queryTable)
	self.requesterCallback(self.requesterContext, queryJson, errMsg)

	-- Close blocker popup
	main:ClosePopup()
end

function TradeQueryGeneratorClass:RequestSynthUniqueQuery(slot, context, statWeights, callback)
	local uniqueItems = synthUniqueTrade.listSynthesisUniques(main.uniqueDB, function(item)
		return slot and self.itemsTab:IsItemValidForSlot(item, slot.slotName)
	end)
	if #uniqueItems == 0 then
		callback(context, nil, "No synthesised uniques are available for this slot")
		return
	end

	self.requesterCallback = callback
	self.requesterContext = context
	local controls = { }
	local popupWidth = 680
	local maxModifierRows = 8
	local selectedRows = { }
	local modifierList = { }
	local uniqueList = { }
	for _, item in ipairs(uniqueItems) do
		t_insert(uniqueList, {
			label = colorCodes.UNIQUE .. (item.title or item.name),
			item = item,
		})
	end

	controls.unique = new("DropDownControl"):DropDownControl({ "TOPLEFT", nil, "TOPLEFT" },
		{ 145, 30, 500, 20 }, uniqueList, nil, "Select the mechanically synthesised unique to search for.", true)
	controls.uniqueLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.unique, "LEFT" },
		{ -8, 0, 130, 16 }, "^7Unique item:")
	controls.implicitCount = new("DropDownControl"):DropDownControl({ "TOPLEFT", nil, "TOPLEFT" },
		{ 145, 58, 80, 20 }, { 1, 2, 3 }, nil,
		"Requires exactly this many implicits. Corrupted items are excluded so the count is exact.")
	controls.implicitCount.selIndex = self.lastSynthImplicitCount or 3
	controls.implicitCountLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.implicitCount, "LEFT" },
		{ -8, 0, 130, 16 }, "^7Synthesis implicits:")
	controls.corruptionNotice = new("LabelControl"):LabelControl({ "LEFT", controls.implicitCount, "RIGHT" },
		{ 12, 0, 400, 16 }, "^xF0C674Corrupted results are excluded to preserve the exact implicit count.")
	controls.modifierHeader = new("LabelControl"):LabelControl({ "TOPLEFT", nil, "TOPLEFT" },
		{ 20, 88, 620, 16 }, "^7Unique modifier assumptions (also required trade thresholds):")

	local function resetModifierRows()
		selectedRows = { }
		modifierList = { { label = "^7+ Add unique modifier" } }
		local selectedUnique = controls.unique:GetSelValue()
		for _, modifier in ipairs(selectedUnique and synthUniqueTrade.extractVariableModifiers(selectedUnique.item) or { }) do
			t_insert(modifierList, {
				label = "^7" .. modifier.line,
				modifier = modifier,
			})
		end
		for row = 1, maxModifierRows do
			local selector = controls["modifier" .. row]
			if selector then
				selector:SetList(modifierList)
				selector:SetSel(1, true)
				for component = 1, 2 do
					controls["modifierValue" .. row .. "_" .. component].buf = ""
				end
			end
		end
	end

	for row = 1, maxModifierRows do
		local y = 110 + (row - 1) * 25
		local selector = new("DropDownControl"):DropDownControl({ "TOPLEFT", nil, "TOPLEFT" },
			{ 20, y, 500, 20 }, modifierList, function(index, value)
				if index == 1 then
					for clearRow = row, maxModifierRows do
						selectedRows[clearRow] = nil
						local laterSelector = controls["modifier" .. clearRow]
						if laterSelector and clearRow ~= row then
							laterSelector:SetSel(1, true)
						end
						for component = 1, 2 do
							local laterValue = controls["modifierValue" .. clearRow .. "_" .. component]
							if laterValue then laterValue.buf = "" end
						end
					end
				else
					selectedRows[row] = {
						modifier = value.modifier,
						values = copyTable(value.modifier.values),
					}
					for component, componentValue in ipairs(value.modifier.values) do
						controls["modifierValue" .. row .. "_" .. component].buf = tostring(componentValue)
					end
				end
			end, nil, true)
		selector.shown = function()
			return row == 1 or selectedRows[row - 1] ~= nil
		end
		controls["modifier" .. row] = selector
		for component = 1, 2 do
			local valueControl = tradeHelpers.newPlainNumericEdit({ "TOPLEFT", nil, "TOPLEFT" },
				{ 525 + (component - 1) * 67, y, 62, 20 }, "", component == 1 and "Roll" or "Roll 2", 8, false,
				function(value)
					if selectedRows[row] then
						selectedRows[row].values[component] = tonumber(value)
					end
				end)
			valueControl.shown = function()
				return selectedRows[row] ~= nil and selectedRows[row].modifier.ranges[component] ~= nil
			end
			controls["modifierValue" .. row .. "_" .. component] = valueControl
		end
	end
	controls.unique.selFunc = function()
		resetModifierRows()
	end
	resetModifierRows()

	local isAmuletSlot = slot and slot.slotName == "Amulet"
	local isBeltSlot = slot and slot.slotName == "Belt"
	local isWeaponSlot = slot and (slot.slotName == "Weapon 1" or slot.slotName == "Weapon 2"
		or slot.slotName == "Weapon 1 Swap" or slot.slotName == "Weapon 2 Swap")
	local optionY = 318
	if isAmuletSlot or isBeltSlot or isWeaponSlot then
		local term = isWeaponSlot and "enchants" or "anoints"
		local enchantTooltip = s_format([[Keep: %s will be unchanged on the search results.
Copy Current: current %s will be applied to the search result items.
Remove: %s will be removed from the search results.]], term, term, term)
		controls.copyEnchantMode = new("DropDownControl"):DropDownControl({ "TOPLEFT", nil, "TOPLEFT" },
			{ 145, optionY, 120, 18 }, { "Keep", "Copy Current", "Remove" }, function() end, enchantTooltip)
		controls.copyEnchantMode:SelByValue(self.lastCopyEnchantMode or "Keep")
		local labelText = isWeaponSlot and "^7Enchant Behaviour:" or "^7Anoint Behaviour:"
		controls.copyEnchantModeLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.copyEnchantMode, "LEFT" },
			{ -8, 0, 120, 16 }, labelText)
		optionY = optionY + 28
	end
	controls.includeMirrored = new("CheckBoxControl"):CheckBoxControl({ "TOPLEFT", nil, "TOPLEFT" },
		{ 20, optionY, 18 }, "Mirrored Items:", function() end)
	controls.includeMirrored.state = self.lastIncludeMirrored == nil or self.lastIncludeMirrored == true

	local currencyDropdownNames = { }
	for _, currency in ipairs(currencyTable) do
		t_insert(currencyDropdownNames, currency.name)
	end
	controls.maxPrice = new("EditControl"):EditControl({ "TOPLEFT", nil, "TOPLEFT" },
		{ 145, optionY + 30, 70, 18 }, nil, nil, "%D")
	controls.maxPrice.buf = self.lastMaxPrice and tostring(self.lastMaxPrice) or ""
	controls.maxPriceType = new("DropDownControl"):DropDownControl({ "LEFT", controls.maxPrice, "RIGHT" },
		{ 5, 0, 170, 18 }, currencyDropdownNames, nil)
	controls.maxPriceType.selIndex = self.lastMaxPriceTypeIndex or 1
	controls.maxPriceLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.maxPrice, "LEFT" },
		{ -8, 0, 120, 16 }, "^7Max Price:")
	controls.maxLevel = new("EditControl"):EditControl({ "TOPLEFT", nil, "TOPLEFT" },
		{ 145, optionY + 58, 70, 18 }, nil, nil, "%D")
	controls.maxLevel.buf = self.lastMaxLevel and tostring(self.lastMaxLevel) or ""
	controls.maxLevelLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.maxLevel, "LEFT" },
		{ -8, 0, 120, 16 }, "^7Max Level:")

	local supportsSockets = slot and not slot.slotName:find("Jewel") and not slot.slotName:find("Flask")
	if supportsSockets then
		controls.sockets = new("EditControl"):EditControl({ "TOPLEFT", nil, "TOPLEFT" },
			{ 485, optionY + 30, 70, 18 }, nil, nil, "%D")
		controls.sockets.buf = self.lastSockets and tostring(self.lastSockets) or ""
		controls.socketsLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.sockets, "LEFT" },
			{ -8, 0, 150, 16 }, "^7# of Empty Sockets:")
		if not slot.slotName:find("Belt") and not slot.slotName:find("Ring") and not slot.slotName:find("Amulet") then
			controls.links = new("EditControl"):EditControl({ "TOPLEFT", nil, "TOPLEFT" },
				{ 485, optionY + 58, 70, 18 }, nil, nil, "%D")
			controls.links.buf = self.lastLinks and tostring(self.lastLinks) or ""
			controls.linksLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.links, "LEFT" },
				{ -8, 0, 150, 16 }, "^7# of Links:")
		end
	end

	controls.generateQuery = new("ButtonControl"):ButtonControl({ "BOTTOM", nil, "BOTTOM" },
		{ -45, -10, 80, 20 }, "Execute", function()
			local assumptions = { }
			local seenModifiers = { }
			local errors = { }
			for row = 1, maxModifierRows do
				local selected = selectedRows[row]
				if selected then
					if seenModifiers[selected.modifier.key] then
						t_insert(errors, "The same unique modifier was selected more than once")
					else
						seenModifiers[selected.modifier.key] = true
						local values = { }
						for component = 1, #selected.modifier.ranges do
							values[component] = tonumber(controls["modifierValue" .. row .. "_" .. component].buf)
							if values[component] == nil then
								t_insert(errors, s_format("Enter every roll for %s", selected.modifier.line))
							end
						end
						assumptions[selected.modifier.key] = { selected = true, values = values }
					end
				end
			end
			local selectedUnique = controls.unique:GetSelValue().item
			local modifiers = synthUniqueTrade.extractVariableModifiers(selectedUnique)
			local configured, configureErrors = synthUniqueTrade.configureModifiers(modifiers, assumptions)
			for _, message in ipairs(configureErrors) do t_insert(errors, message) end
			local baseline, missing = synthUniqueTrade.buildBaseline(selectedUnique, configured)
			for _, key in ipairs(missing) do
				t_insert(errors, "Selected unique modifiers cannot coexist: " .. key)
			end
			local requiredMods, mappingErrors = self:ResolveSynthUniqueRequirements(baseline, configured)
			for _, message in ipairs(mappingErrors) do t_insert(errors, message) end
			if #errors > 0 then
				main:ClosePopup()
				callback(context, nil, table.concat(errors, "\n"))
				return
			end

			local implicitCount = controls.implicitCount:GetSelValue()
			t_insert(requiredMods, 1, {
				tradeId = "pseudo.pseudo_number_of_implicit_mods",
				filterValue = { min = implicitCount, max = implicitCount },
			})
			local options = {
				includeMirrored = controls.includeMirrored.state,
				includeCorrupted = false,
				includeTalisman = false,
				includeScourge = false,
				influence1 = 1,
				influence2 = 1,
				maxPrice = tonumber(controls.maxPrice.buf),
				maxPriceType = currencyTable[controls.maxPriceType.selIndex].id,
				maxLevel = tonumber(controls.maxLevel.buf),
				sockets = controls.sockets and tonumber(controls.sockets.buf),
				links = controls.links and tonumber(controls.links.buf),
				requiredMods = requiredMods,
				statWeights = statWeights,
				synthUnique = {
					item = selectedUnique,
					baseline = baseline,
					modifiers = configured,
					implicitCount = implicitCount,
					copyEnchantMode = controls.copyEnchantMode and controls.copyEnchantMode:GetSelValue(),
					omittedImplicits = { },
				},
			}
			self.lastSynthImplicitCount = controls.implicitCount.selIndex
			if controls.copyEnchantMode then
				self.lastCopyEnchantMode = options.synthUnique.copyEnchantMode
			end
			self.lastIncludeMirrored = options.includeMirrored
			self.lastMaxPrice = options.maxPrice
			self.lastMaxPriceTypeIndex = controls.maxPriceType.selIndex
			self.lastMaxLevel = options.maxLevel
			self.lastSockets = options.sockets
			self.lastLinks = options.links
			self.tradeTypeIndex = context.controls.tradeTypeSelection.selIndex
			context.synthUnique = options.synthUnique
			main:ClosePopup()
			self:StartQuery(slot, options)
		end)
	controls.cancel = new("ButtonControl"):ButtonControl({ "BOTTOM", nil, "BOTTOM" },
		{ 45, -10, 80, 20 }, "Cancel", function() main:ClosePopup() end)
	main:OpenPopup(popupWidth, 455 + (controls.copyEnchantMode and 28 or 0), "Synthesised Unique Query Options", controls)
end

function TradeQueryGeneratorClass:RequestQuery(slot, context, statWeights, callback)
	self.requesterCallback = callback
	self.requesterContext = context

	local controls = { }
	local options = { }
	local popupHeight = 110
	local popupWidth = 400

	local isJewelSlot = slot and slot.slotName:find("Jewel") ~= nil
	local isAbyssalJewelSlot = slot and slot.slotName:find("Abyssal") ~= nil
	local isAmuletSlot = slot and slot.slotName == "Amulet"
	local isBeltSlot = slot and slot.slotName == "Belt"
	local isWeaponSlot = slot and (slot.slotName == "Weapon 1" or slot.slotName == "Weapon 2"
		or slot.slotName == "Weapon 1 Swap" or slot.slotName == "Weapon 2 Swap")
	local isEldritchModSlot = slot and eldritchModSlots[slot.slotName] == true

	local lastItemAnchor
	local function updateLastAnchor(anchor, height)
		lastItemAnchor = anchor
		popupHeight = popupHeight + (height or 23)
	end
	controls.includeCorrupted = new("CheckBoxControl"):CheckBoxControl({ "TOP", nil, "TOP" }, { -40, 30, 18 }, "Corrupted Mods:", function(state) end, "Includes corruption implicit modifiers in the weighted sum.\nNote that there is a maximum search filter count which means this might cause other weights to not be included.")
	controls.includeCorrupted.state = not context.slotTbl.alreadyCorrupted and (self.lastIncludeCorrupted == nil or self.lastIncludeCorrupted == true)
	controls.includeCorrupted.enabled = not context.slotTbl.alreadyCorrupted
	updateLastAnchor(controls.includeCorrupted)

	local includeScourge = self.queryTab.pbLeague == "Standard" or self.queryTab.pbLeague == "Hardcore"

	if context.slotTbl.unique then
		options.special = { itemName = context.slotTbl.slotName }
	end

	if context.slotTbl.slotName == "Watcher's Eye" then
		local activeSocketList = {}
		for nodeId, jewelSlot in pairs(self.itemsTab.sockets) do
			if not jewelSlot.inactive and not self.itemsTab.build.spec.nodes[nodeId].containJewelSocket then
				t_insert(activeSocketList, jewelSlot)
			end
		end
		table.sort(activeSocketList, function(a, b)
			return a.label < b.label
		end)
		controls.jewelSlot = new("DropDownControl"):DropDownControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" }, { 0, 5, 100, 18 }, activeSocketList, function(idx, value) end)
		controls.jewelSlotLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.jewelSlot, "LEFT" }, { -5, 0, 0, 16 }, "Jewel Slot:")
		for index, jewelSlot in ipairs(activeSocketList) do
			if jewelSlot.nodeId == context.slotTbl.selectedJewelNodeId then
				controls.jewelSlot.selIndex = index
				break
			end
		end
		updateLastAnchor(controls.jewelSlot)
	end
	-- these unique items cannot be mirrored
	if not context.slotTbl.unique then
		controls.includeMirrored = new("CheckBoxControl"):CheckBoxControl({"TOPRIGHT",lastItemAnchor,"BOTTOMRIGHT"}, {0, 5, 18}, "Mirrored Items:", function(state) end)
		controls.includeMirrored.state = (self.lastIncludeMirrored == nil or self.lastIncludeMirrored == true)
		updateLastAnchor(controls.includeMirrored)
	end

	if not isJewelSlot and not isAbyssalJewelSlot and includeScourge then
		controls.includeScourge = new("CheckBoxControl"):CheckBoxControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" }, { 0, 5, 18 }, "Scourge Mods:", function(state) end)
		controls.includeScourge.state = (self.lastIncludeScourge == nil or self.lastIncludeScourge == true)
		updateLastAnchor(controls.includeScourge)
	end

	if isAmuletSlot then
		controls.includeTalisman = new("CheckBoxControl"):CheckBoxControl({ "TOPRIGHT", lastItemAnchor, "BOTTOMRIGHT" }, { 0, 5, 18 }, "Talisman Mods:", function(state) end, "Whether talisman enchant mods should be included. Disabled by default due to the maximum filter limit.")
		controls.includeTalisman.state = not not self.lastIncludeTalisman
		updateLastAnchor(controls.includeTalisman)
	end

	-- Implicit mod and enchant behaviour in searching and sorting
	if isEldritchModSlot then
		local eldritchTooltip =
		[[Controls the inclusion of eldritch mod weights in the weighted sum.
Copy Current: implicits in weights are skipped and augments are replaced with the
current implicits when possible. Usually the best opinion as this ensures the
augments make sense for your build.

Keep regular: weights are generated and implicits are kept, but conditional
"while unique/atlas boss" modifiers are removed from the items.

Keep regular + presence: weights are generated and implicits are kept. Not
recommended as many of these implicits are impractical and appear powerful
with default PoB enemy configs.

Remove: eldritch implicits are removed and ignored in the search.]]
		controls.includeEldritch = new("DropDownControl"):DropDownControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" }, { 0, 5, 140, 18 },
			{ "Copy Current", "Keep regular", "Keep regular+presence", "Remove" }, function(_state) end, eldritchTooltip)
		controls.includeEldritchLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.includeEldritch, "LEFT" },
			{ -4, 0, 80, 16 }, "Eldritch Mods:")
		controls.includeEldritch:SelByValue(self.lastIncludeEldritch)
		updateLastAnchor(controls.includeEldritch)
	end
	if isAmuletSlot or isBeltSlot or isWeaponSlot then
		local term = isWeaponSlot and "enchants" or "anoints"
		local enchantTooltip = s_format([[Keep: %s will be unchanged on the search results.
Copy Current: current %s will be applied to the search result items.
Remove: %s will be removed from the search results.]], term, term, term)
		local copyEnchantList = { "Keep", "Copy Current", "Remove" }
		controls.copyEnchantMode = new("DropDownControl"):DropDownControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" },
			{ 0, 5, 120, 18 },
			copyEnchantList, function(state) end, enchantTooltip)
		controls.copyEnchantMode:SelByValue(self.lastCopyEnchantMode or "Keep")
		local labelText = isWeaponSlot and "^7Enchant Behaviour:" or "^7Anoint Behaviour:"
		controls.copyEnchantModeLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.copyEnchantMode, "LEFT" },
			{ -4, 0, 80, 16 }, labelText)
		updateLastAnchor(controls.copyEnchantMode)
	end
	-- forward declarations for functions interacting with mod filter selectors
	---@type fun(): table
	local getModList
	---@type fun(controls: any, modList: any)
	local setModSelectors
	-- jewel type selector
	if isJewelSlot and not context.slotTbl.unique then
		controls.jewelType = new("DropDownControl"):DropDownControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" }, { 0, 5, 100, 18 }, { "Base", "Abyss" }, function(index, value)
			-- update mod list for selectors
			local mods = getModList()
			setModSelectors(controls, mods)
		end)
		controls.jewelType.selIndex = self.lastJewelType or 1
		controls.jewelTypeLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.jewelType, "LEFT" }, { -5, 0, 0, 16 }, "Jewel Type:")
		updateLastAnchor(controls.jewelType)
	elseif slot and not isAbyssalJewelSlot and context.slotTbl.slotName ~= "Watcher's Eye" then
		local selFunc = function()
			-- influenced items can't have eldritch implicits
			if controls.includeEldritch and isEldritchModSlot then
				local hasInfluence1 = controls.influence1 and controls.influence1:GetSelValue() ~= "None"
				local hasInfluence2 = controls.influence2 and controls.influence2:GetSelValue() ~= "None"
				controls.includeEldritch.enabled = not hasInfluence1 and not hasInfluence2
			end
		end
		controls.influence1 = new("DropDownControl"):DropDownControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" }, { 0, 5, 100, 18 },
			influenceDropdownNames, selFunc)
		controls.influence1:SetSel(self.lastInfluence1 or 1)
		controls.influence1Label = new("LabelControl"):LabelControl({"RIGHT",controls.influence1,"LEFT"}, {-5, 0, 0, 16}, "^7Influence 1:")

		controls.influence2 = new("DropDownControl"):DropDownControl({ "TOPLEFT", controls.influence1, "BOTTOMLEFT" }, { 0, 5, 100, 18 },
			influenceDropdownNames, selFunc)
		controls.influence2:SetSel(self.lastInfluence2 or 1)
		selFunc()
		controls.influence2Label = new("LabelControl"):LabelControl({ "RIGHT", controls.influence2, "LEFT" }, { -5, 0, 0, 16 },
			"^7Influence 2:")
		updateLastAnchor(controls.influence2, 46)
	elseif isAbyssalJewelSlot then
		controls.jewelType = new("DropDownControl"):DropDownControl({"TOPLEFT",lastItemAnchor,"BOTTOMLEFT"}, {0, 5, 100, 18}, { "Abyss" }, nil)
		controls.jewelType.selIndex = 1
		controls.jewelTypeLabel = new("LabelControl"):LabelControl({"RIGHT",controls.jewelType,"LEFT"}, {-5, 0, 0, 16}, "Jewel Type:")
		updateLastAnchor(controls.jewelType)
	end
	-- Add max price limit selection dropbox
	local currencyDropdownNames = { }
	for _, currency in ipairs(currencyTable) do
		t_insert(currencyDropdownNames, currency.name)
	end
	controls.maxPrice = new("EditControl"):EditControl({"TOPLEFT",lastItemAnchor,"BOTTOMLEFT"}, {0, 5, 70, 18}, nil, nil, "%D")
	controls.maxPrice.buf = self.lastMaxPrice and tostring(self.lastMaxPrice) or ""
	controls.maxPriceType = new("DropDownControl"):DropDownControl({ "LEFT", controls.maxPrice, "RIGHT" }, { 5, 0, 150, 18 }, currencyDropdownNames, nil, "^7The trade site will filter out listings with other currencies,\nif anything other than \"Chaos Orb Equivalent\" is chosen and a maximum is specified.")
	controls.maxPriceType.selIndex = self.lastMaxPriceTypeIndex or 1
	controls.maxPriceLabel = new("LabelControl"):LabelControl({"RIGHT",controls.maxPrice,"LEFT"}, {-5, 0, 0, 16}, "^7Max Price:")
	updateLastAnchor(controls.maxPrice)

	controls.maxLevel = new("EditControl"):EditControl({"TOPLEFT",lastItemAnchor,"BOTTOMLEFT"}, {0, 5, 100, 18}, nil, nil, "%D")
	controls.maxLevel.buf = self.lastMaxLevel and tostring(self.lastMaxLevel) or ""
	controls.maxLevelLabel = new("LabelControl"):LabelControl({ "RIGHT", controls.maxLevel, "LEFT" }, { -5, 0, 0, 16 }, "^7Max Level:")
	updateLastAnchor(controls.maxLevel)

	-- basic filtering by slot for sockets and links, Megalomaniac does not have slot and Sockets use "Jewel nodeId"
	if slot and not isJewelSlot and not isAbyssalJewelSlot and not slot.slotName:find("Flask") then
		controls.sockets = new("EditControl"):EditControl({"TOPLEFT",lastItemAnchor,"BOTTOMLEFT"}, {0, 5, 70, 18}, nil, nil, "%D")
		controls.sockets.buf = self.lastSockets and tostring(self.lastSockets) or ""
		controls.socketsLabel = new("LabelControl"):LabelControl({"RIGHT",controls.sockets,"LEFT"}, {-5, 0, 0, 16}, "^7# of Empty Sockets:")
		updateLastAnchor(controls.sockets)

		if not slot.slotName:find("Belt") and not slot.slotName:find("Ring") and not slot.slotName:find("Amulet") then
			controls.links = new("EditControl"):EditControl({"TOPLEFT",lastItemAnchor,"BOTTOMLEFT"}, {0, 5, 70, 18}, nil, nil, "%D")
			controls.linksLabel = new("LabelControl"):LabelControl({"RIGHT",controls.links,"LEFT"}, {-5, 0, 0, 16}, "^7# of Links:")
			updateLastAnchor(controls.links)
		end
	end

	for i, stat in ipairs(statWeights) do
		controls["sortStatType"..tostring(i)] = new("LabelControl"):LabelControl({"TOPLEFT",lastItemAnchor,"BOTTOMLEFT"}, {0, i == 1 and 5 or 3, 70, 16}, i < (#statWeights < 6 and 10 or 5) and s_format("^7%.2f: %s", stat.weightMult, stat.label) or ("+ "..tostring(#statWeights - 4).." Additional Stats"))
		lastItemAnchor = controls["sortStatType"..tostring(i)]
		popupHeight = popupHeight + 19
		if i == 1 then
			controls.sortStatLabel = new("LabelControl"):LabelControl({"RIGHT",lastItemAnchor,"LEFT"}, {-5, 0, 0, 16}, "^7Stat to Sort By:")
		elseif i == 5 then
			-- tooltips do not actually work for labels
			lastItemAnchor.tooltipFunc = function(tooltip)
				tooltip:Clear()
				tooltip:AddLine(16, "Sorts the weights by the stats selected multiplied by a value")
				tooltip:AddLine(16, "Currently sorting by:")
				for i, stat in ipairs(statWeights) do
					if i > 4 then
						tooltip:AddLine(16, s_format("%s: %.2f", stat.label, stat.weightMult))
					end
				end
			end
			break
		end
	end
	popupHeight = popupHeight + 4

	local selectedMods = {}
	if context.slotTbl.slotName == "Watcher's Eye" then
		controls.includeAllWEMods = new("CheckBoxControl"):CheckBoxControl({"TOPRIGHT",lastItemAnchor,"BOTTOMRIGHT"}, {0, 5, 18}, "Include all Watcher's Eye mods:", function(state) end)
		controls.includeAllWEMods.tooltipText = "Include mods that could not have a weight calculated for them at weight 0."
		lastItemAnchor = controls.includeAllWEMods
		popupHeight = popupHeight + 23
	end

	controls.generateQuery = new("ButtonControl"):ButtonControl({ "BOTTOM", nil, "BOTTOM" }, {-45, -10, 80, 20}, "Execute", function()
		main:ClosePopup()

		self.tradeTypeIndex = context.controls.tradeTypeSelection.selIndex

		if controls.copyEnchantMode then
			self.lastCopyEnchantMode = controls.copyEnchantMode:GetSelValue()
		end

		if controls.includeMirrored then
			self.lastIncludeMirrored, options.includeMirrored = controls.includeMirrored.state, controls.includeMirrored.state
		end
		if controls.includeCorrupted then
			self.lastIncludeCorrupted, options.includeCorrupted = controls.includeCorrupted.state, controls.includeCorrupted.state
		end
		if controls.includeEldritch then
			self.lastIncludeEldritch, options.includeEldritch = controls.includeEldritch:GetSelValue(),
				controls.includeEldritch:GetSelValue()
		end
		if controls.includeScourge then
			self.lastIncludeScourge, options.includeScourge = controls.includeScourge.state, controls.includeScourge.state
		end
		if controls.includeTalisman then
			self.lastIncludeTalisman, options.includeTalisman = controls.includeTalisman.state, controls.includeTalisman.state
		end
		if controls.influence1 then
			self.lastInfluence1, options.influence1 = controls.influence1.selIndex, controls.influence1.selIndex
		else
			options.influence1 = 1
		end
		if controls.influence2 then
			self.lastInfluence2, options.influence2 = controls.influence2.selIndex, controls.influence2.selIndex
		else
			options.influence2 = 1
		end
		if controls.jewelType then
			self.lastJewelType = controls.jewelType.selIndex
			options.jewelType = controls.jewelType.list[controls.jewelType.selIndex]
		end
		if controls.maxPrice.buf then
			options.maxPrice = tonumber(controls.maxPrice.buf)
			self.lastMaxPrice = options.maxPrice
			options.maxPriceType = currencyTable[controls.maxPriceType.selIndex].id
			self.lastMaxPriceTypeIndex = controls.maxPriceType.selIndex
		end
		if controls.maxLevel.buf then
			options.maxLevel = tonumber(controls.maxLevel.buf)
			self.lastMaxLevel = options.maxLevel
		end
		if controls.sockets and controls.sockets.buf then
			options.sockets = tonumber(controls.sockets.buf)
			self.lastSockets = options.sockets
		end
		if controls.links and controls.links.buf then
			options.links = tonumber(controls.links.buf)
		end
		if controls.includeAllWEMods then
			options.includeAllWEMods = controls.includeAllWEMods.state
		end
		if #selectedMods > 0 then
			options.requiredMods = copyTable(selectedMods)
		end
		options.statWeights = statWeights
		if controls.jewelSlot then
			slot = controls.jewelSlot:GetSelValue()
			context.slotTbl.selectedJewelNodeId = slot.nodeId
		end

		self:StartQuery(slot, options)
	end)
	controls.generateQuery.enabled = function()
		return not controls.jewelSlot or controls.jewelSlot:GetSelValue() ~= nil
	end
	controls.generateQuery.tooltipText = controls.jewelSlot and "Requires an active Jewel Socket." or nil
	controls.cancel = new("ButtonControl"):ButtonControl({ "BOTTOM", nil, "BOTTOM" }, {45, -10, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	if context.slotTbl.unique then
		main:OpenPopup(popupWidth, popupHeight, "Query Options", controls)
		return
	end

	-- intended width of the whole row, including dropdown and aux controls
	local totalWidth = 340
	-- size of min value input
	local fieldWidth = 60
	-- size of clear button
	local buttonSize = 20
	-- gap between controls
	local xSpacing = 4
	local auxControlWidth = buttonSize + fieldWidth + 2 * xSpacing

	local _, lastItemY = lastItemAnchor:GetPos()
	local _, lastItemH = lastItemAnchor:GetSize()
	controls.modSelectorHeaderAnchor = new("Control"):Control({ "TOPLEFT", nil, "TOPLEFT" },
		-- position right below last item, centered horizontally
		{ (popupWidth - totalWidth) / 2, lastItemH + lastItemY, 0, 0 },
		"")
	updateLastAnchor(controls.modSelectorHeaderAnchor)
	-- get mod selector list
	getModList = function()
		local _, itemCategory = tradeHelpers.getTradeCategory(slot.slotName, slot and self.itemsTab.items[slot.selItemId])
		-- add radius/base as they have different mods
		if controls.jewelType and itemCategory == "Jewel" then
			itemCategory = controls.jewelType:GetSelValue() .. itemCategory
		end
		local mods = { { label = "^7+ Add Required Stat" } }
		-- pob1 uses ids in QueryMods.lua which are based on mod names and stat
		-- orders. these result in duplicates
		local includedIds = {}
		for _, modType in ipairs({ "Explicit", "Implicit", "Corrupted" }) do
			for idStr, modData in pairs(self.modData[modType]) do
				if modData[itemCategory] ~= nil and not includedIds[modData.tradeMod.id] then
					local text = "^7" .. modData.tradeMod.text:gsub("(%a+) Passive Skills in Radius also grant ", "%1: ")
					includedIds[modData.tradeMod.id] = true
					if modType ~= "Explicit" then
						-- dim-ish red or the greenish yellow trade site uses for implicits slightly brightened
						local colour = modType == "Corrupted" and "^x9E3E38" or "^x989654"
						text = text .. string.format(" %s(%s)", colour, modType)
					end
					t_insert(mods, { label = text, tradeId = modData.tradeMod.id })
				end
			end
		end
		local pseudoStats = getStatEntries("pseudo")
		-- map stats and such which are clearly not relevant here
		local ignoredStats = {
			"^pseudo.lake",
			"^pseudo.pseudo_lake",
			"^pseudo.pseudo_logbook",
			"^pseudo.pseudo_temple",
			"^pseudo.pseudo_map",
			"^pseudo.pseudo_ritual",
		}
		for _, entry in ipairs(pseudoStats or {}) do
			for _, ignored in ipairs(ignoredStats) do
				if entry.id:find(ignored) then
					goto pseudoContinue
				end
			end
			t_insert(mods, { label = s_format("^7%s (Pseudo)", entry.text), tradeId = entry.id })
			::pseudoContinue::
		end
		return mods
	end
	-- amount of mod selectors: technically we could have 40, but the more we have the fewer
	-- stats fit in the weighted sum, and this means a static popup size is ok
	local maxSelectors = 3
	-- set mod selector dropdown labels, adjust width, and possibly change the mod list
	setModSelectors = function(controls, modList)
		-- reset selections
		if modList then
			selectedMods = {}
		end
		for i = 1, maxSelectors do
			local mod = selectedMods[i]
			local selector = controls["modSelector" .. i]
			local minimumBox = controls["modSelectorMin" .. i]
			if modList then
				selector:SetList(modList)
			end
			if mod then
				selector:SelByValue(mod.label, "label")
				selector.width = totalWidth - auxControlWidth
				minimumBox.buf = mod.value and tostring(mod.value) or ""
			else
				selector.selIndex = 1
				selector.width = totalWidth
			end
			selector:CheckDroppedWidth(true)
		end
	end
	-- mod filter dropdown and aux controls
	for i = 1, maxSelectors do
		-- dropdown which lists all mods that fit
		local dropdown = new("DropDownControl"):DropDownControl({ "TOPLEFT", lastItemAnchor, "BOTTOMLEFT" },
			{ 0, 4, totalWidth, 20 }, nil,
			function(idx, val)
				if idx == 1 then
					table.remove(selectedMods, i)
				else
					selectedMods[i] = copyTable(val)
				end
				setModSelectors(controls)
			end, nil, true)
		dropdown.shown = function()
			return not not selectedMods[i - 1] or i == 1
		end
		updateLastAnchor(dropdown)
		dropdown:SetList({})
		controls["modSelector" .. i] = dropdown

		-- box that sets minimum value for filter
		local minimumBox = tradeHelpers.newPlainNumericEdit({ "LEFT", lastItemAnchor, "RIGHT" },
			{ xSpacing, 0, fieldWidth, buttonSize }, "", "Min", 6, false, function(val)
				selectedMods[i].value = tonumber(val)
			end)
		minimumBox.shown = function()
			return not not selectedMods[i]
		end
		controls["modSelectorMin" .. i] = minimumBox

		-- button which removes the mod row
		local clearButton = new("ButtonControl"):ButtonControl({ "LEFT", minimumBox, "RIGHT" }, { xSpacing, 0, buttonSize, buttonSize },
			"x", function()
				table.remove(selectedMods, i)
				setModSelectors(controls)
			end)
		clearButton.shown = function()
			return not not selectedMods[i]
		end
		controls["modSelectorClear" .. i] = clearButton
	end
	setModSelectors(controls, getModList())

	main:OpenPopup(popupWidth, popupHeight, "Query Options", controls)
end
