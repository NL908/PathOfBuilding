-- Path of Building
--
-- Module: Synthesised Unique Trade
-- Stateless helpers for selecting and normalising synthesised unique items
--

local m_max = math.max
local m_min = math.min
local s_format = string.format
local t_insert = table.insert
local t_remove = table.remove
local synthesisedUniques = LoadModule("Data/SynthesisedUniques")

local M = { }

local numberPattern = "[+-]?%d+%.?%d*"
local rangePattern = "([+-]?)%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)"

local function displayName(item)
	return item.title or item.name or ""
end

--- Whether a unique database entry represents a mechanically synthesised unique,
--- rather than merely an item introduced during Synthesis league.
--- @param item Item|table
--- @return boolean
function M.isSynthesisUnique(item)
	if type(item) ~= "table" or item.rarity and item.rarity ~= "UNIQUE" then
		return false
	end
	if item.synthesised then
		return true
	end
	return synthesisedUniques[displayName(item)] == true
end

local function isModLineActive(item, modLine)
	return not item.CheckModLineVariant or item:CheckModLineVariant(modLine)
end

local function copyValues(values)
	local copy = { }
	for index, value in ipairs(values or { }) do
		copy[index] = value
	end
	return copy
end

local function dedupeValues(values)
	local result = { }
	local seen = { }
	for _, value in ipairs(values) do
		if not seen[value] then
			seen[value] = true
			t_insert(result, value)
		end
	end
	return result
end

-- Converts both a database range line and an imported, rolled line into the same key.
-- A leading plus is retained because it is often meaningful to the stat text; a minus
-- is part of the value and is discarded.
local function modLineTemplate(line)
	return line:lower()
		:gsub(rangePattern, function(sign)
			return sign == "+" and "+#" or "#"
		end)
		:gsub("([+-]?)%d+%.?%d*", function(sign)
			return sign == "+" and "+#" or "#"
		end)
		:gsub("%s+", " ")
		:match("^%s*(.-)%s*$")
end

local function inverseTemplate(template)
	local antonym = {
		increased = "reduced",
		reduced = "increased",
		more = "less",
		less = "more",
	}
	local changed
	local result = template:gsub("(%a+)", function(word)
		if not changed and antonym[word] then
			changed = true
			return antonym[word]
		end
		return word
	end)
	return changed and result or nil
end

-- Find the ordinal occupied by each ranged component among the values in the
-- rolled form of the line. This lets a line such as "(10-20)% ... for 4 seconds"
-- change the first value without changing the fixed 4.
local function extractRanges(line)
	local ranges = { }
	local valueIndex = 0
	local position = 1
	while position <= #line do
		local rangeStart, rangeEnd, sign, first, second = line:find(rangePattern, position)
		local numberStart, numberEnd = line:find(numberPattern, position)
		if rangeStart and (not numberStart or rangeStart < numberStart) then
			valueIndex = valueIndex + 1
			local firstValue = tonumber(first)
			local secondValue = tonumber(second)
			if sign == "-" then
				firstValue = -firstValue
				secondValue = -secondValue
			end
			t_insert(ranges, {
				min = m_min(firstValue, secondValue),
				max = m_max(firstValue, secondValue),
				first = firstValue,
				second = secondValue,
				valueIndex = valueIndex,
			})
			position = rangeEnd + 1
		elseif numberStart then
			valueIndex = valueIndex + 1
			position = numberEnd + 1
		else
			break
		end
	end
	return ranges
end

local function extractNumbers(line)
	local values = { }
	for value in line:gmatch(numberPattern) do
		t_insert(values, tonumber(value))
	end
	return values
end

local function renderRangeLine(line, ranges, values)
	local rangeValues = { }
	for index, range in ipairs(ranges) do
		local delta = range.second - range.first
		rangeValues[index] = delta == 0 and 0.5 or (values[index] - range.first) / delta
	end
	return itemLib.applyRange(line, #rangeValues == 1 and rangeValues[1] or rangeValues)
end

local function resolvedModLine(modLine)
	if modLine.range and modLine.line:find(rangePattern) then
		return itemLib.applyRange(modLine.line, modLine.range, modLine.valueScalar, modLine.corruptedRange)
	end
	return modLine.line
end

local function cloneItem(item)
	local clone = new("Item"):Item(item:BuildRaw())
	-- Preserve the marker defensively for older Item:BuildRaw implementations.
	clone.synthesised = item.synthesised
	return clone
end

local function buildActiveModMap(item)
	local map = { }
	for _, modLine in ipairs(item.explicitModLines or { }) do
		if isModLineActive(item, modLine) then
			local template = modLineTemplate(modLine.line)
			map[template] = map[template] or { }
			t_insert(map[template], modLine)
		end
	end
	return map
end

local function currentVariantIds(item, modLine)
	local variantIds = { }
	if not modLine.variantList then
		return variantIds
	end
	for variantId in pairs(modLine.variantList) do
		local eligible = true
		if item.usesVariantGroups then
			eligible = false
			for groupId in pairs(modLine.variantGroupList or { }) do
				if item.IsVariantGroupOptionEligible and item:IsVariantGroupOptionEligible(groupId, variantId) then
					eligible = true
					break
				end
			end
		else
			local label = item.variantList and item.variantList[variantId] or ""
			local lowerLabel = label:lower()
			-- Legacy unique data represents historical and current rolls as sibling
			-- variants. Historical variants are not purchasable for this search.
			eligible = not lowerLabel:find("pre ", 1, true)
				and not lowerLabel:find("legacy", 1, true)
		end
		if eligible then
			t_insert(variantIds, variantId)
		end
	end
	table.sort(variantIds)
	return variantIds
end

local function variantGroupIds(modLine)
	local groupIds = { }
	for groupId in pairs(modLine.variantGroupList or { }) do
		t_insert(groupIds, groupId)
	end
	table.sort(groupIds)
	return groupIds
end

local function addUniqueValue(list, used, value)
	if value and not used[value] then
		t_insert(list, value)
		used[value] = true
	end
end

-- Activate selected alternate modifiers on a cloned database item. Legacy items
-- use variant/variantAlt fields; newer items use independent variant groups.
local function activateSelectedVariants(item, modifiers)
	local missing = { }
	if item.usesVariantGroups then
		local assignedGroups = { }
		local assignedVariants = { }
		for _, modifier in ipairs(modifiers or { }) do
			if modifier.selected and #modifier.variantIds > 0 then
				local assigned
				for _, groupId in ipairs(modifier.variantGroupIds) do
					if not assignedGroups[groupId] then
						for _, variantId in ipairs(modifier.variantIds) do
							if not assignedVariants[variantId]
								and item:IsVariantGroupOptionEligible(groupId, variantId) then
								item.variantGroupSelections[groupId] = variantId
								assignedGroups[groupId] = true
								assignedVariants[variantId] = true
								assigned = true
								break
							end
						end
					end
					if assigned then break end
				end
				if not assigned then
					t_insert(missing, modifier.key)
				end
			end
		end
		if item.NormaliseVariantSelections then
			item:NormaliseVariantSelections()
		end
		return missing
	end

	if not item.variantList then
		return missing
	end
	local fields = { "variant" }
	for index = 1, 5 do
		local suffix = index == 1 and "" or index
		if item["hasAltVariant" .. suffix] then
			t_insert(fields, "variantAlt" .. suffix)
		end
	end
	local selections = { }
	local used = { }
	for _, modifier in ipairs(modifiers or { }) do
		if modifier.selected and #modifier.variantIds > 0 then
			addUniqueValue(selections, used, modifier.variantIds[1])
			if #selections > #fields then
				t_remove(selections)
				t_insert(missing, modifier.key)
			end
		end
	end
	for _, field in ipairs(fields) do
		addUniqueValue(selections, used, item[field])
	end
	for _, modifier in ipairs(modifiers or { }) do
		for _, variantId in ipairs(modifier.variantIds) do
			addUniqueValue(selections, used, variantId)
		end
	end
	for index, field in ipairs(fields) do
		if selections[index] then
			item[field] = selections[index]
		end
	end
	return missing
end

--- Return Synthesis-league unique items accepted by a caller-provided slot predicate.
--- Accepts main.uniqueDB, main.uniqueDB.list, or any array/map of Item objects.
--- @param uniqueDB table
--- @param slotValid? fun(item: Item): boolean
--- @return Item[]
function M.listSynthesisUniques(uniqueDB, slotValid)
	local result = { }
	local list = uniqueDB and uniqueDB.list or uniqueDB or { }
	for _, item in pairs(list) do
		if M.isSynthesisUnique(item)
			and (not slotValid or slotValid(item)) then
			t_insert(result, item)
		end
	end
	table.sort(result, function(first, second)
		local firstName = displayName(first):lower()
		local secondName = displayName(second):lower()
		if firstName ~= secondName then
			return firstName < secondName
		end
		local firstVariant = first.variant and first.variantList and first.variantList[first.variant] or ""
		local secondVariant = second.variant and second.variantList and second.variantList[second.variant] or ""
		return tostring(firstVariant) < tostring(secondVariant)
	end)
	return result
end

--- Extract current-version explicit modifiers that contain one or more roll ranges.
--- Alternate modifier choices are included even when the database item's default
--- variant selection does not currently activate them.
--- The key is stable across database-range and imported rolled representations.
--- @param item Item
--- @return table[] modifiers
function M.extractVariableModifiers(item)
	local modifiers = { }
	local occurrenceByTemplate = { }
	for lineIndex, modLine in ipairs(item.explicitModLines or { }) do
		local variantIds = currentVariantIds(item, modLine)
		local selectable = not modLine.variantList or #variantIds > 0
		if selectable and (not modLine.versionList
			or not item.selectedVersion or modLine.versionList[item.selectedVersion]) then
			local ranges = extractRanges(modLine.line)
			if #ranges > 0 then
				local template = modLineTemplate(modLine.line)
				local occurrence = (occurrenceByTemplate[template] or 0) + 1
				occurrenceByTemplate[template] = occurrence
				local values = { }
				for index, range in ipairs(ranges) do
					values[index] = range.min
				end
				t_insert(modifiers, {
					key = template .. "\0" .. occurrence,
					line = modLine.line,
					lineIndex = lineIndex,
					template = template,
					inverseTemplate = inverseTemplate(template),
					occurrence = occurrence,
					ranges = ranges,
					values = values,
					selected = false,
					active = isModLineActive(item, modLine),
					variantIds = variantIds,
					variantGroupIds = variantGroupIds(modLine),
				})
			end
		end
	end
	return modifiers
end

--- Apply user settings to extracted modifiers. Unconfigured modifiers retain their
--- minimum numeric roll and do not become trade constraints.
--- Settings are keyed by modifier key and may contain selected, value/values, and
--- invert (boolean or one boolean per component).
--- @param modifiers table[]
--- @param assumptions? table<string, table>
--- @return table[] configured
--- @return string[] errors
function M.configureModifiers(modifiers, assumptions)
	local configured = { }
	local errors = { }
	assumptions = assumptions or { }
	for _, modifier in ipairs(modifiers or { }) do
		local copy = copyTable(modifier)
		local setting = assumptions[modifier.key]
		copy.selected = setting and setting.selected == true or false
		copy.invert = setting and setting.invert or false
		if setting then
			local values = setting.values or (setting.value ~= nil and { setting.value }) or copy.values
			if #values ~= #copy.ranges then
				t_insert(errors, s_format("%s expects %d roll value(s)", modifier.line, #copy.ranges))
			else
				for index, range in ipairs(copy.ranges) do
					local value = tonumber(values[index])
					if not value then
						t_insert(errors, s_format("%s has a non-numeric roll value", modifier.line))
					elseif value < range.min or value > range.max then
						t_insert(errors, s_format("%s roll %s is outside %s-%s", modifier.line,
							tostring(value), tostring(range.min), tostring(range.max)))
					else
						copy.values[index] = value
					end
				end
			end
		end
		t_insert(configured, copy)
	end
	return configured, errors
end

--- Clone a selected unique, remove its normal implicits, mark it synthesised, and
--- place selected assumptions/unselected minimum rolls on all variable modifiers.
--- @param item Item
--- @param modifiers table[] configured output from configureModifiers
--- @return Item baseline
--- @return string[] missingModifiers
function M.buildBaseline(item, modifiers)
	local baseline = cloneItem(item)
	baseline.implicitModLines = { }
	baseline.synthesised = true
	local missing = activateSelectedVariants(baseline, modifiers)
	local activeMods = buildActiveModMap(baseline)
	for _, modifier in ipairs(modifiers or { }) do
		local sourceModLine = baseline.explicitModLines[modifier.lineIndex]
		local modLine = sourceModLine and isModLineActive(baseline, sourceModLine) and sourceModLine
			or activeMods[modifier.template] and activeMods[modifier.template][modifier.occurrence]
		if modLine then
			modLine.line = renderRangeLine(modifier.line, modifier.ranges, modifier.values)
			modLine.range = nil
			modLine.corruptedRange = nil
		elseif modifier.selected then
			t_insert(missing, modifier.key)
		end
	end
	baseline:BuildAndParseRaw()
	-- Preserve the marker defensively for older Item:BuildRaw implementations.
	baseline.synthesised = true
	return baseline, dedupeValues(missing)
end

local function componentIsInverted(modifier, index)
	if type(modifier.invert) == "table" then
		return modifier.invert[index] == true
	end
	return modifier.invert == true
end

--- Clone a fetched item and clamp selected modifier rolls that are worse than the
--- configured assumptions. The original item is never mutated.
--- @param item Item
--- @param modifiers table[] configured output from configureModifiers
--- @return Item adjusted
--- @return table[] overrides
--- @return string[] missingModifiers
function M.clampFetchedItem(item, modifiers)
	local adjusted = cloneItem(item)
	local activeMods = buildActiveModMap(adjusted)
	local overrides = { }
	local missing = { }
	local changed = false
	for _, modifier in ipairs(modifiers or { }) do
		if modifier.selected then
			local modLine = activeMods[modifier.template] and activeMods[modifier.template][modifier.occurrence]
			local matchedInverse
			if not modLine and modifier.inverseTemplate then
				modLine = activeMods[modifier.inverseTemplate]
					and activeMods[modifier.inverseTemplate][modifier.occurrence]
				matchedInverse = modLine ~= nil
			end
			if not modLine then
				t_insert(missing, modifier.key)
			else
				local actualLine = resolvedModLine(modLine)
				local lineValues = extractNumbers(actualLine)
				local actualValues = { }
				local adjustedValues = { }
				local overridden = false
				for index, range in ipairs(modifier.ranges) do
					local actual = lineValues[range.valueIndex]
					if actual and matchedInverse then
						actual = -actual
					end
					local assumed = modifier.values[index]
					actualValues[index] = actual
					adjustedValues[index] = actual
					if actual == nil then
						overridden = false
						break
					end
					local worse
					if componentIsInverted(modifier, index) then
						worse = actual > assumed
					else
						worse = actual < assumed
					end
					if worse then
						adjustedValues[index] = assumed
						overridden = true
					end
				end
				if #actualValues ~= #modifier.ranges then
					t_insert(missing, modifier.key)
				elseif overridden then
					local adjustedLine = renderRangeLine(modifier.line, modifier.ranges, adjustedValues)
					modLine.line = adjustedLine
					modLine.range = nil
					modLine.corruptedRange = nil
					t_insert(overrides, {
						key = modifier.key,
						line = modifier.line,
						actualLine = actualLine,
						adjustedLine = adjustedLine,
						actualValues = actualValues,
						assumedValues = copyValues(modifier.values),
					})
					changed = true
				end
			end
		end
	end
	if changed then
		adjusted:BuildAndParseRaw()
		adjusted.synthesised = item.synthesised
	end
	return adjusted, overrides, missing
end

M.modLineTemplate = modLineTemplate

return M
