describe("SynthUniqueTrade", function()
	local synthUniqueTrade = LoadModule("Classes/SynthUniqueTrade")

	local function makeDatabaseItem()
		return new("Item"):Item([[
Test Synthesis Unique
Ruby Ring
League: Synthesis
Implicits: 1
+(20-30)% to Fire Resistance
+(50-80) to maximum Life
(10-20)% increased Attack Speed
Adds (20-25) to (26-35) Fire Damage
Life Flasks gain (0-3) Charges every 3 seconds
5% increased Damage
]], "UNIQUE", true)
	end

	local function findModifier(modifiers, text)
		for _, modifier in ipairs(modifiers) do
			if modifier.line:find(text, 1, true) then
				return modifier
			end
		end
	end

	local function findLine(item, text)
		for _, modLine in ipairs(item.explicitModLines) do
			if modLine.line:find(text, 1, true) then
				return modLine.line
			end
		end
	end

	describe("unique selection", function()
		it("lists only slot-valid mechanically synthesised uniques in name order", function()
			local validSecond = { title = "Circle of Guilt", league = "Synthesis", rarity = "UNIQUE", slot = "Ring" }
			local wrongLeague = { title = "Alpha", league = "Ritual", rarity = "UNIQUE", slot = "Ring" }
			local wrongSlot = { title = "Mask of the Tribunal", league = "Synthesis", rarity = "UNIQUE", slot = "Helmet" }
			local validFirst = { title = "Circle of Ambition", rarity = "UNIQUE", slot = "Ring" }
			local leagueOnly = { title = "Bottled Faith", league = "Synthesis", rarity = "UNIQUE", slot = "Flask" }
			local explicitSynth = { title = "Explicit Synth", rarity = "UNIQUE", slot = "Ring", synthesised = true }
			local relic = { title = "Circle of Fear", league = "Synthesis", rarity = "RELIC", slot = "Ring" }

			local result = synthUniqueTrade.listSynthesisUniques({ list = {
				validSecond, wrongLeague, wrongSlot, validFirst, leagueOnly, explicitSynth, relic,
			} }, function(item)
				return item.slot == "Ring"
			end)

			assert.are.same({ validFirst, explicitSynth, validSecond }, result)
			assert.is_false(synthUniqueTrade.isSynthesisUnique(leagueOnly))
			assert.is_true(synthUniqueTrade.isSynthesisUnique(validFirst))
			assert.is_true(synthUniqueTrade.isSynthesisUnique(explicitSynth))
			assert.is_true(synthUniqueTrade.isSynthesisUnique({ title = "Rational Doctrine", rarity = "UNIQUE" }))
		end)
	end)

	describe("modifier assumptions", function()
		it("extracts each ranged component and defaults to minimum rolls", function()
			local modifiers = synthUniqueTrade.extractVariableModifiers(makeDatabaseItem())
			local life = assert(findModifier(modifiers, "maximum Life"))
			local damage = assert(findModifier(modifiers, "Adds"))
			local charges = assert(findModifier(modifiers, "Charges"))

			assert.are.same({ 50 }, life.values)
			assert.are.equal(50, life.ranges[1].min)
			assert.are.equal(80, life.ranges[1].max)
			assert.are.same({ 20, 26 }, damage.values)
			assert.are.same({ 1, 2 }, {
				damage.ranges[1].valueIndex,
				damage.ranges[2].valueIndex,
			})
			assert.are.equal(1, charges.ranges[1].valueIndex)
			assert.are.equal(0, charges.values[1])
			assert.is_false(life.selected)
		end)

		it("configures multiple assumptions and validates their ranges", function()
			local modifiers = synthUniqueTrade.extractVariableModifiers(makeDatabaseItem())
			local life = assert(findModifier(modifiers, "maximum Life"))
			local damage = assert(findModifier(modifiers, "Adds"))
			local configured, errors = synthUniqueTrade.configureModifiers(modifiers, {
				[life.key] = { selected = true, value = 75 },
				[damage.key] = { selected = true, values = { 23, 32 } },
			})

			assert.are.equal(0, #errors)
			assert.are.same({ 75 }, findModifier(configured, "maximum Life").values)
			assert.are.same({ 23, 32 }, findModifier(configured, "Adds").values)
			assert.is_true(findModifier(configured, "maximum Life").selected)

			local _, invalidErrors = synthUniqueTrade.configureModifiers(modifiers, {
				[life.key] = { selected = true, value = 100 },
			})
			assert.are.equal(1, #invalidErrors)
			assert.is_truthy(invalidErrors[1]:find("outside", 1, true))
		end)

		it("exposes current alternate modifiers and activates multiple selected choices", function()
			local source = new("Item"):Item([[
Alternate Synthesis Unique
Ruby Ring
League: Synthesis
Has Alt Variant: true
Variant: Reservation (Pre 3.11.0)
Variant: Reservation (Current)
Variant: Fire Damage
Implicits: 1
+(20-30)% to Fire Resistance
{variant:1}(60-80)% reduced Mana Reservation Efficiency
{variant:2}(30-40)% increased Mana Reservation Efficiency
{variant:3}(40-60)% increased Fire Damage
]], "UNIQUE", true)
			local modifiers = synthUniqueTrade.extractVariableModifiers(source)
			local currentReservation = assert(findModifier(modifiers, "increased Mana Reservation"))
			local fireDamage = assert(findModifier(modifiers, "Fire Damage"))

			assert.are.equal(2, #modifiers)
			assert.are.same({ 2 }, currentReservation.variantIds)
			assert.are.same({ 3 }, fireDamage.variantIds)
			assert.is_false(currentReservation.active)
			assert.is_true(fireDamage.active)

			local configured = synthUniqueTrade.configureModifiers(modifiers, {
				[currentReservation.key] = { selected = true, value = 38 },
				[fireDamage.key] = { selected = true, value = 55 },
			})
			local baseline, missing = synthUniqueTrade.buildBaseline(source, configured)

			assert.are.equal(0, #missing)
			assert.are.equal(2, baseline.variant)
			assert.are.equal(3, baseline.variantAlt)
			assert.are.equal("38% increased Mana Reservation Efficiency",
				findLine(baseline, "increased Mana Reservation"))
			assert.are.equal("55% increased Fire Damage", findLine(baseline, "Fire Damage"))
		end)
	end)

	describe("calculation baseline", function()
		it("clones the unique, removes its implicit, and applies assumptions and minimums", function()
			local source = makeDatabaseItem()
			local modifiers = synthUniqueTrade.extractVariableModifiers(source)
			local life = assert(findModifier(modifiers, "maximum Life"))
			local damage = assert(findModifier(modifiers, "Adds"))
			local configured = synthUniqueTrade.configureModifiers(modifiers, {
				[life.key] = { selected = true, value = 75 },
				[damage.key] = { selected = true, values = { 23, 32 } },
			})

			local baseline, missing = synthUniqueTrade.buildBaseline(source, configured)

			assert.are.equal(0, #missing)
			assert.is_true(baseline.synthesised)
			assert.are.equal(0, #baseline.implicitModLines)
			assert.are.equal("+75 to maximum Life", findLine(baseline, "maximum Life"))
			assert.are.equal("10% increased Attack Speed", findLine(baseline, "Attack Speed"))
			assert.are.equal("Adds 23 to 32 Fire Damage", findLine(baseline, "Adds"))
			assert.are.equal("Life Flasks gain 0 Charges every 3 seconds", findLine(baseline, "Charges"))
			assert.are.equal("5% increased Damage", findLine(baseline, "increased Damage"))
			assert.are.equal(1, #source.implicitModLines)
			assert.is_truthy(findLine(source, "(50-80)"))
		end)
	end)

	describe("fetched item clamping", function()
		it("clamps only worse selected rolls and reports every override", function()
			local modifiers = synthUniqueTrade.extractVariableModifiers(makeDatabaseItem())
			local life = assert(findModifier(modifiers, "maximum Life"))
			local attackSpeed = assert(findModifier(modifiers, "Attack Speed"))
			local damage = assert(findModifier(modifiers, "Adds"))
			local charges = assert(findModifier(modifiers, "Charges"))
			local configured = synthUniqueTrade.configureModifiers(modifiers, {
				[life.key] = { selected = true, value = 75 },
				[attackSpeed.key] = { selected = true, value = 18 },
				[damage.key] = { selected = true, values = { 23, 32 } },
				[charges.key] = { selected = true, value = 1, invert = true },
			})
			local fetched = new("Item"):Item([[
Rarity: Unique
Test Synthesis Unique
Ruby Ring
Synthesised Item
Implicits: 0
+60 to maximum Life
20% increased Attack Speed
Adds 21 to 34 Fire Damage
Life Flasks gain 2 Charges every 3 seconds
5% increased Damage
]])

			local adjusted, overrides, missing = synthUniqueTrade.clampFetchedItem(fetched, configured)

			assert.are.equal(0, #missing)
			assert.are.equal(3, #overrides)
			assert.are.equal("+75 to maximum Life", findLine(adjusted, "maximum Life"))
			assert.are.equal("20% increased Attack Speed", findLine(adjusted, "Attack Speed"))
			assert.are.equal("Adds 23 to 34 Fire Damage", findLine(adjusted, "Adds"))
			assert.are.equal("Life Flasks gain 1 Charges every 3 seconds", findLine(adjusted, "Charges"))
			assert.are.same({ 60 }, overrides[1].actualValues)
			assert.are.same({ 75 }, overrides[1].assumedValues)
			assert.are.equal("+60 to maximum Life", findLine(fetched, "maximum Life"))
			assert.is_true(adjusted.synthesised)
		end)

		it("reports a selected modifier that is absent from the fetched item", function()
			local modifiers = synthUniqueTrade.extractVariableModifiers(makeDatabaseItem())
			local life = assert(findModifier(modifiers, "maximum Life"))
			local configured = synthUniqueTrade.configureModifiers(modifiers, {
				[life.key] = { selected = true, value = 75 },
			})
			local fetched = new("Item"):Item([[
Rarity: Unique
Test Synthesis Unique
Ruby Ring
Synthesised Item
Implicits: 0
5% increased Damage
]])

			local _, overrides, missing = synthUniqueTrade.clampFetchedItem(fetched, configured)

			assert.are.equal(0, #overrides)
			assert.are.same({ life.key }, missing)
		end)
	end)
end)
