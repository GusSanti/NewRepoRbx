local NumberFormatter = {}

local ABBREVIATIONS = {
	"K", "M", "B", "T",
	"Qa", "Qi", "Sx", "Sp", "Oc", "No",
	"Dd", "Ud", "Td", "Qad", "Qid",
	"Sxd", "Spd", "Ocd", "Nod",
	"Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg",
	"Sxvg", "Spvg", "Ocvg"
}
local POWERS_OF_1000 = {}
for i = 1, #ABBREVIATIONS do
	POWERS_OF_1000[i] = 1000 ^ i
end

function NumberFormatter.AddCommas(num : number)
	local str = tostring(math.floor(num))
	return (str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function NumberFormatter.Abbreviate(num: number): string
	local absNum = math.abs(num)

	if absNum < 1000 then
		return tostring(num)
	end

	local magnitude = math.min(math.floor(math.log10(absNum) / 3), #ABBREVIATIONS)
	local shortNum = math.floor((absNum / POWERS_OF_1000[magnitude]) * 100) / 100

	if num < 0 then
		shortNum = -shortNum
	end

	return tostring(shortNum) .. ABBREVIATIONS[magnitude]
end

return NumberFormatter
