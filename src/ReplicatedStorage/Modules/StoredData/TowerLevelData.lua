-- VARIABLES
local TowerLevelData = {}

-- CONSTANTS
TowerLevelData.MAX_LEVEL    = 20
TowerLevelData.LEVEL_SCALE  = 0.08
TowerLevelData.EXP_BASE     = 100
TowerLevelData.EXP_EXPONENT = 1.6

-- FUNCTIONS
function TowerLevelData.getLevelFactor(level: number): number
	level = math.clamp(level or 1, 1, TowerLevelData.MAX_LEVEL)
	return 1 + (level - 1) * TowerLevelData.LEVEL_SCALE
end

function TowerLevelData.expToNextLevel(currentLevel: number): number
	if currentLevel >= TowerLevelData.MAX_LEVEL then return math.huge end
	currentLevel = math.clamp(currentLevel, 1, TowerLevelData.MAX_LEVEL - 1)
	return math.floor(TowerLevelData.EXP_BASE * (currentLevel ^ TowerLevelData.EXP_EXPONENT))
end

function TowerLevelData.computeStats(
	baseDamage:    number,
	baseRange:     number,
	baseCooldown:  number,
	level:         number,
	Damage:   number,
	Range:    number,
	AttackCooldown: number
)
	level         = math.clamp(level or 1, 1, TowerLevelData.MAX_LEVEL)
	Damage   = Damage or 0
	Range    = Range or 0
	AttackCooldown = AttackCooldown or 0

	local lvlFactor = TowerLevelData.getLevelFactor(level)
	local finalDamage = math.round((baseDamage * lvlFactor) + Damage)
	local finalRange = math.round(((baseRange * lvlFactor) + Range) * 100) / 100
	local finalCooldown = math.max(0.1, math.round(((baseCooldown / lvlFactor) - AttackCooldown) * 100) / 100)

	return {
		Damage         = finalDamage,
		Range          = finalRange,
		AttackCooldown = finalCooldown,
	}
end

-- INIT
return TowerLevelData