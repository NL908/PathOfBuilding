describe("Synthesised unique trade implicit catalog", function()
	local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = { } })

	it("loads synthesis item classes exported from game data", function()
		assert.is_true(data.synthesisModItemClasses.SynthesisImplicitGlobalCritQuiver1.Quiver)
		assert.is_nil(data.synthesisModItemClasses.SynthesisImplicitGlobalCritQuiver1.Ring)
		assert.is_true(data.synthesisModItemClasses.SynthesisImplicitLifeJewel1.Jewel)
		assert.is_true(data.synthesisModItemClasses.SynthesisImplicitLifeJewel1.AbyssJewel)
	end)

	it("maps synthesis implicits to implicit trade stats", function()
		local mod = queryGen.modData.Synthesis["1485_CriticalStrikeChance"]

		assert.is_not_nil(mod)
		assert.are.equals("implicit.stat_587431675", mod.tradeMod.id)
		assert.is_not_nil(mod.Quiver)
		assert.is_nil(mod.Ring)
		assert.is_nil(mod["1HWeapon"])
	end)

	it("preserves specialised and aggregate weapon category masks", function()
		local mod = queryGen.modData.Synthesis["1217_AllDamage"]

		assert.is_not_nil(mod)
		assert.is_not_nil(mod["1HWeapon"])
		assert.is_not_nil(mod["1HMace"])
		assert.is_not_nil(mod.Claw)
		assert.is_not_nil(mod["2HWeapon"])
		assert.is_not_nil(mod.Bow)
		assert.is_nil(mod.Quiver)
	end)

	it("distinguishes base and abyss jewel synthesis pools", function()
		local abyssOnlyMod = queryGen.modData.Synthesis["8328_AddedManaRegenWithShield"]

		assert.is_not_nil(abyssOnlyMod)
		assert.is_not_nil(abyssOnlyMod.AbyssJewel)
		assert.is_not_nil(abyssOnlyMod.AnyJewel)
		assert.is_nil(abyssOnlyMod.BaseJewel)
	end)
end)
