describe("Synth unique trade results", function()
	local synthUniqueTrade = LoadModule("Classes/SynthUniqueTrade")

	local function makeSelection()
		local selectedUnique = new("Item"):Item([[
Test Synthesis Unique
Ruby Ring
League: Synthesis
Implicits: 1
+(20-30)% to Fire Resistance
+(50-80) to maximum Life
(10-20)% increased Attack Speed
]], "UNIQUE", true)
		local modifiers = synthUniqueTrade.extractVariableModifiers(selectedUnique)
		local assumptions = { }
		for _, modifier in ipairs(modifiers) do
			if modifier.line:find("maximum Life", 1, true) then
				assumptions[modifier.key] = { selected = true, value = 75 }
			elseif modifier.line:find("Attack Speed", 1, true) then
				assumptions[modifier.key] = { selected = true, value = 18 }
			end
		end
		local configured, errors = synthUniqueTrade.configureModifiers(modifiers, assumptions)
		assert.are.equal(0, #errors)
		return {
			item = selectedUnique,
			modifiers = configured,
			implicitCount = 3,
		}
	end

	local function findExplicitLine(item, text)
		for _, modLine in ipairs(item.explicitModLines) do
			if modLine.line:find(text, 1, true) then
				return modLine.line
			end
		end
	end

	it("retains listing data, clamps present assumptions, and keeps results with missing modifiers", function()
		local tradeQuery = new("TradeQuery"):TradeQuery({ })
		local original = [[
Rarity: Unique
Test Synthesis Unique
Ruby Ring
Synthesised Item
Implicits: 2
{enchant}Quality does not increase Physical Damage
{synthesis}+1 to Maximum Frenzy Charges
+60 to maximum Life
15% increased Attack Speed
]]
		local missingLife = [[
Rarity: Unique
Test Synthesis Unique
Ruby Ring
Synthesised Item
Implicits: 1
+1 to Maximum Frenzy Charges
15% increased Attack Speed
]]
		local results = tradeQuery:ApplySynthUniqueAssumptions({
			{ item_string = original, amount = 2, currency = "divine", listingId = "kept" },
			{ item_string = missingLife, amount = 1, currency = "divine", listingId = "missing" },
		}, makeSelection())

		assert.are.equal(2, #results)
		assert.are.equal("kept", results[1].listingId)
		assert.are.equal(original, results[1].original_item_string)
		assert.are.equal(2, #results[1].assumptionOverrides)
		local adjusted = new("Item"):Item(results[1].item_string)
		assert.is_true(adjusted.synthesised)
		assert.are.equal("+75 to maximum Life", findExplicitLine(adjusted, "maximum Life"))
		assert.are.equal("18% increased Attack Speed", findExplicitLine(adjusted, "Attack Speed"))
		assert.are.equal("Quality does not increase Physical Damage", adjusted.enchantModLines[1].line)

		tradeQuery:ApplyQueryResultItemOptions(adjusted, "Weapon 1", "Keep", nil)
		local imported = new("Item"):Item(adjusted:BuildRaw())
		assert.are.equal("Quality does not increase Physical Damage", imported.enchantModLines[1].line)

		assert.are.equal("missing", results[2].listingId)
		assert.are.equal(1, #results[2].assumptionOverrides)
		assert.are.equal(1, #results[2].missingAssumptions)
		assert.is_truthy(results[2].missingAssumptions[1]:find("maximum Life", 1, true))
		local missingAdjusted = new("Item"):Item(results[2].item_string)
		assert.is_nil(findExplicitLine(missingAdjusted, "maximum Life"))
		assert.are.equal("18% increased Attack Speed", findExplicitLine(missingAdjusted, "Attack Speed"))
	end)

	it("describes applied assumptions in result and import tooltips", function()
		local tradeQuery = new("TradeQuery"):TradeQuery({ })
		local tooltip = new("Tooltip"):Tooltip()
		tradeQuery:AddAssumptionOverridesToTooltip(tooltip, {
			synthesisWarnings = {
				"Unsupported synthesis line (no trade stat mapping)",
			},
			missingAssumptions = {
				"+(50-80) to maximum Life",
			},
			assumptionOverrides = {
				{
					actualLine = "+60 to maximum Life",
					adjustedLine = "+75 to maximum Life",
				},
			},
		})

		local text = { }
		for _, line in ipairs(tooltip.lines) do
			if line.text then
				table.insert(text, line.text)
			end
		end
		local tooltipText = table.concat(text, "\n")
		assert.is_truthy(tooltipText:find("Omitted synthesis implicits", 1, true))
		assert.is_truthy(tooltipText:find("Unsupported synthesis line", 1, true))
		assert.is_truthy(tooltipText:find("Unique modifier assumptions not applied", 1, true))
		assert.is_truthy(tooltipText:find("modifier absent", 1, true))
		assert.is_truthy(tooltipText:find("Assumed unique modifier rolls applied", 1, true))
		assert.is_truthy(tooltipText:find("+60 to maximum Life", 1, true))
		assert.is_truthy(tooltipText:find("+75 to maximum Life", 1, true))
	end)

	it("applies enchant behavior without changing synthesis implicits", function()
		local copiedEldritch
		local tradeQuery = new("TradeQuery"):TradeQuery({
			CopyAnointsAndEldritchImplicits = function(_, item, copyEldritchImplicits)
				copiedEldritch = copyEldritchImplicits
				item.enchantModLines = { { line = "Copied enchant" } }
			end,
		})
		local item = {
			implicitModLines = { { line = "+1 to Maximum Power Charges" } },
			enchantModLines = { { line = "Fetched enchant" } },
		}

		tradeQuery:ApplyQueryResultItemOptions(item, "Weapon 1", "Copy Current", nil)
		assert.is_false(copiedEldritch)
		assert.are.equal("+1 to Maximum Power Charges", item.implicitModLines[1].line)
		assert.are.equal("Copied enchant", item.enchantModLines[1].line)

		tradeQuery:ApplyQueryResultItemOptions(item, "Weapon 1", "Remove", nil)
		assert.are.equal(1, #item.implicitModLines)
		assert.are.equal(0, #item.enchantModLines)
	end)

	it("shows the normal enchant behavior control for synthesised swap weapons", function()
		local oldUniqueDB = main.uniqueDB
		local oldOpenPopup = main.OpenPopup
		local oldClosePopup = main.ClosePopup
		local popup
		local ok, err = pcall(function()
			main.uniqueDB = { list = {
				new("Item"):Item([[
Nebulis
Void Sceptre
League: Synthesis
Implicits: 0
(15-20)% increased Cast Speed
]], "UNIQUE", true),
				new("Item"):Item([[
Circle of Guilt
Iron Ring
League: Synthesis
Implicits: 0
(10-20)% increased Damage
]], "UNIQUE", true),
			} }
			main.OpenPopup = function(_, width, height, title, controls)
				popup = { width = width, height = height, title = title, controls = controls }
			end
			main.ClosePopup = function() end
			local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({
				itemsTab = {
					IsItemValidForSlot = function(_, item, slotName)
						return item.title == "Nebulis" and slotName == "Weapon 1 Swap"
							or item.title == "Circle of Guilt" and slotName == "Ring 1"
					end,
				},
			})
			queryGen.lastCopyEnchantMode = "Remove"
			queryGen:RequestSynthUniqueQuery({ slotName = "Weapon 1 Swap" }, {
				controls = { tradeTypeSelection = { selIndex = 1 } },
			}, { }, function() end)
			assert.are.equal("Synthesised Unique Query Options", popup.title)
			assert.are.equal(483, popup.height)
			assert.is_not_nil(popup.controls.copyEnchantMode)
			assert.are.equal("Remove", popup.controls.copyEnchantMode:GetSelValue())
			assert.are.equal("^7Enchant Behaviour:", popup.controls.copyEnchantModeLabel.label)
			assert.is_false(popup.controls.useImplicitCount.state)
			assert.is_false(popup.controls.implicitCount:IsShown())
			assert.is_true(popup.controls.corruptionNotice:IsShown())
			assert.are.equal(145, popup.controls.includeMirrored.x)
			assert.are.equal(560, popup.controls.sockets.x)
			assert.are.equal(560, popup.controls.links.x)
			local currencyX = popup.controls.maxPriceType:GetPos()
			local currencyWidth = popup.controls.maxPriceType:GetSize()
			local socketsLabelX = popup.controls.socketsLabel:GetPos()
			assert.is_true(currencyX + currencyWidth < socketsLabelX)

			local startedOptions
			queryGen.StartQuery = function(_, _, options)
				startedOptions = options
			end
			queryGen:RequestSynthUniqueQuery({ slotName = "Ring 1" }, {
				controls = { tradeTypeSelection = { selIndex = 1 } },
			}, { }, function(_, _, queryErr)
				assert.is_nil(queryErr)
			end)
			assert.is_nil(popup.controls.copyEnchantMode)
			popup.controls.modifier1:SetSel(2)
			popup.controls.modifierValue1_1.buf = "17"
			popup.controls.generateQuery.onClick()
			assert.are.equal("Remove", queryGen.lastCopyEnchantMode)
			assert.are.equal(0, #startedOptions.requiredMods)
			assert.is_nil(startedOptions.synthUnique.implicitCount)
			assert.is_true(startedOptions.synthUnique.modifiers[1].selected)
			assert.is_truthy(startedOptions.synthUnique.baseline:BuildRaw():find("17%% increased Damage"))

			startedOptions = nil
			queryGen:RequestSynthUniqueQuery({ slotName = "Ring 1" }, {
				controls = { tradeTypeSelection = { selIndex = 1 } },
			}, { }, function(_, _, queryErr)
				assert.is_nil(queryErr)
			end)
			popup.controls.useImplicitCount.state = true
			assert.is_true(popup.controls.implicitCount:IsShown())
			popup.controls.implicitCount:SetSel(2)
			popup.controls.generateQuery.onClick()
			assert.are.equal(1, #startedOptions.requiredMods)
			assert.are.equal("pseudo.pseudo_number_of_implicit_mods", startedOptions.requiredMods[1].tradeId)
			assert.are.equal(2, startedOptions.requiredMods[1].filterValue.min)
			assert.are.equal(2, startedOptions.requiredMods[1].filterValue.max)
			assert.are.equal(2, startedOptions.synthUnique.implicitCount)
		end)
		main.uniqueDB = oldUniqueDB
		main.OpenPopup = oldOpenPopup
		main.ClosePopup = oldClosePopup
		assert(ok, err)
	end)

	it("shows Find synth only for slots with a valid mechanically synthesised unique", function()
		local oldUniqueDB = main.uniqueDB
		local tradeQuery
		local requested
		local ok, err = pcall(function()
			main.uniqueDB = { list = {
				{
					title = "Circle of Guilt",
					league = "Synthesis",
					rarity = "UNIQUE",
					source = "Drops from unique{Altered/Augmented/Rewritten/Twisted Synthete}",
				},
			} }
			local ringSlot = { slotName = "Ring 1" }
			local itemsTab = {
				activeItemSet = { ["Ring 1"] = { } },
				slots = { ["Ring 1"] = ringSlot },
				sockets = { },
				IsItemValidForSlot = function(_, _, slotName)
					return slotName == "Ring 1"
				end,
			}
			tradeQuery = new("TradeQuery"):TradeQuery(itemsTab)
			tradeQuery.pbLeague = "Standard"
			tradeQuery.statSortSelectionList = { { stat = "FullDPS", weightMult = 1 } }
			tradeQuery.slotTables[1] = { slotName = "Ring 1" }
			tradeQuery.tradeQueryGenerator = {
				RequestSynthUniqueQuery = function(_, activeSlot, context, statWeights, callback)
					requested = {
						activeSlot = activeSlot,
						context = context,
						statWeights = statWeights,
						callback = callback,
					}
				end,
			}
			tradeQuery:PriceItemRowDisplay(1, nil, 0, 20)
		end)
		main.uniqueDB = oldUniqueDB
		assert(ok, err)

		assert.is_true(tradeQuery.controls.synthButton1:GetProperty("shown"))
		assert.is_truthy(tradeQuery.controls.synthButton1:GetProperty("enabled"))
		assert.is_true(tradeQuery.controls.uri1:IsShown())
		assert.are.equal(tradeQuery.controls.synthButton1, tradeQuery.controls.uri1.anchor.other)
		local bestX, _ = tradeQuery.controls.bestButton1:GetPos()
		local uriX, _ = tradeQuery.controls.uri1:GetPos()
		assert.are.equal(bestX + 176, uriX)
		tradeQuery.controls.name1.shown = false
		assert.is_false(tradeQuery.controls.uri1:IsShown())
		tradeQuery.controls.name1.shown = true
		tradeQuery.controls.synthButton1.onClick()
		assert.are.equal(tradeQuery.itemsTab.slots["Ring 1"], requested.activeSlot)
		assert.are.equal(1, requested.context.row_idx)
		assert.are.equal(tradeQuery.statSortSelectionList, requested.statWeights)
		assert.are.equal("function", type(requested.callback))
		tradeQuery.resultTbl[1] = { }
		assert.is_false(tradeQuery.controls.uri1:IsShown())
		assert.is_true(tradeQuery.controls.resultDropdown1:IsShown())
		tradeQuery.resultTbl[1] = nil

		tradeQuery.synthUniqueContexts[1] = { copyEnchantMode = "Remove" }
		tradeQuery.controls.uri1:SetText("https://www.pathofexile.com/trade/search/Standard/unrelated", true)
		assert.is_nil(tradeQuery.synthUniqueContexts[1])
	end)
end)
