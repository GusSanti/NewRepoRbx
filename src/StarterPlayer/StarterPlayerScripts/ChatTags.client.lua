local MarketplaceService = game:GetService("MarketplaceService")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	if message.TextSource then
		local player = Players:GetPlayerByUserId(message.TextSource.UserId)
		if player and MarketplaceService:UserOwnsGamePassAsync(player.UserId, 1529258503) then
			props.PrefixText = "<font color='#ffd700'>[👑 VIP] </font>" .. (message.PrefixText or "")
		elseif player and player.Name == "astro_shadow"	 then
			props.PrefixText = "<font color='#00FFFF'>[DEV] </font>" .. (message.PrefixText or "")
		end
	end
	return props
end
