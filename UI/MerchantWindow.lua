local addonName,addonTable = ...
local DA = _G[addonName] -- for DebugAids.lua
--[[
Skillet: A tradeskill window replacement.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--

-- Localization
local L = LibStub("AceLocale-3.0"):GetLocale("Skillet")
local PT = LibStub("LibPeriodicTable-3.1")

local merchant_inventory = {}

--
-- Get the name for the item in the specified merchant slot. Can
-- only be called when the merchant window is open
--
local function get_merchant_item_name(slot)
	--DA.DEBUG(0,"get_merchant_item_name("..tostring(slot)..")")
	local link = GetMerchantItemLink(slot);
	if link then
		local _,_,name = string.find(link, "^.*%[(.*)%].*$");
		return name;
	else
		return nil;
	end
end

local function get_shopping_list()
	local name = nil
	if not Skillet.db.char.include_alts then
		name = Skillet.currentPlayer
	end
	return Skillet:GetShoppingList(name, Skillet.db.char.same_faction, Skillet.db.char.include_guild)
end

--
-- Checks to see if the cached list of items for this merchant
-- included anything we need to buy.
--
local function does_merchant_sell_required_items(list)
	--DA.DEBUG(0,"does_merchant_sell_required_items("..tostring(list)..")")
	--DA.DEBUG(1,"does_merchant_sell_required_items: list= "..DA.DUMP1(list))
	--DA.DEBUG(1,"does_merchant_sell_required_items: merchant = "..DA.DUMP1(merchant_inventory))
	for i=1,#list,1 do
		local id = list[i].id
		if merchant_inventory[id] then
			return true
		end
	end
	return false
end

--
-- Scans everything the merchant has and adds it to a table
-- that we can refer to when looking for items to buy.
--
local function update_merchant_inventory()
	--DA.DEBUG(0,"update_merchant_inventory()")
	if MerchantFrame and MerchantFrame:IsVisible() then
		local count = GetMerchantNumItems()
		for i=1, count, 1 do
			local link = GetMerchantItemLink(i)
			if link then
				local itemCount, itemTexture, itemValue, itemLink, currencyName, currencyID
				local id = Skillet:GetItemIDFromLink(link)
				local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
				if extendedCost then
					itemCount = GetMerchantItemCostInfo(i)
--
-- Loop through all the items for debugging but only use the first.
--
					if itemCount > 0 then
						--DA.DEBUG(2,"For "..tostring(name).." ("..tostring(id)..") itemCount= "..tostring(itemCount))
						for j=itemCount, 1, -1 do
							itemTexture, itemValue, itemLink, currencyName = GetMerchantItemCostItem(i, j)
							--DA.DEBUG(2,"  ["..tostring(j).."]: itemValue= "..tostring(itemValue)..", itemLink= "..tostring(itemLink)..", currencyName= "..tostring(currencyName))
							if currencyName then
								currencyID = -1 * tonumber(Skillet.currencyIDsByName[currencyName] or 0)
							elseif itemLink then
								currencyName = GetItemInfo(itemLink)
								currencyID = Skillet:GetItemIDFromLink(itemLink)
							end
							--DA.DEBUG(2,"  currencyName= "..tostring(currencyName).." ("..tostring(currencyID)..") x "..tostring(itemValue))
						end
					end
				end
--
-- Only check unlimited quantity items.
--
				if numAvailable == -1  then
					merchant_inventory[id] = {}
					merchant_inventory[id].price = price
					merchant_inventory[id].quantity = quantity
					if Skillet.db.global.itemRecipeUsedIn[id] then		-- if this item is used in any recipes we know about
						if not Skillet:VendorSellsReagent(id) then		-- if its not a known vendor item
							if Skillet.db.global.MissingVendorItems[id] then
								DA.DEBUG(1,"updating "..tostring(name).." ("..tostring(id)..")")
							else
								DA.DEBUG(1,"adding "..tostring(name).." ("..tostring(id)..")")
							end
							if itemCount and itemCount > 0 then
								Skillet.db.global.MissingVendorItems[id] = {name or true, quantity, currencyName, currencyID, itemValue}		-- add it to our table
							else
								Skillet.db.global.MissingVendorItems[id] = name or true		-- add it to our table
							end
						else
							--DA.DEBUG(1,"known "..tostring(name).." ("..tostring(id)..")")
							if type(Skillet.db.global.MissingVendorItems[id]) == "table" then
								if #Skillet.db.global.MissingVendorItems[id] ~= 5 then
									Skillet.db.global.MissingVendorItems[id] = "Fix Me"
								end
							end
						end
						if Skillet.db.global.MissingVendorItems[id] then
							if itemCount and itemCount > 0 and type(Skillet.db.global.MissingVendorItems[id]) ~= "table" then
								DA.DEBUG(1,"converting "..tostring(name).." ("..tostring(id)..")")
								Skillet.db.global.MissingVendorItems[id] = {name or true, quantity, currencyName, currencyID, itemValue}		-- convert it
							elseif PT then
								if id~=0 and PT:ItemInSet(id,"Tradeskill.Mat.BySource.Vendor") then
									DA.DEBUG(1,"removing "..tostring(name).." ("..tostring(id)..")")
									Skillet.db.global.MissingVendorItems[id] = nil		-- remove it from our table
								end
							end
						end
					else
						--DA.DEBUG(1,"not used "..tostring(name).." ("..tostring(id)..")")
					end
				end
			else
				--DA.DEBUG(1,"no link "..tostring(i))
			end
		end
	end
end

--
-- Inserts/updates a button in the merchant frame that allows
-- you to automatically buy reagents.
-- returns true if the button is displayed
-- returns false if the button is hidden
--
local function update_merchant_buy_button()
	--DA.DEBUG(0,"update_merchant_buy_button()")
	Skillet:InventoryScan()
	local list = get_shopping_list()
	if not list or #list == 0 then
		--DA.DEBUG(1,"ShoppingList is empty")
		SkilletMerchantBuyFrame:Hide()
		return false
	elseif does_merchant_sell_required_items(list) == false then
		--DA.DEBUG(1,"Merchant does not sell required items")
		SkilletMerchantBuyFrame:Hide()
		return false
	end
	if Skillet.db.profile.display_shopping_list_at_merchant then
		--DA.DEBUG(1,"Shopping List should be displayed")
		Skillet:DisplayShoppingList(false)
	end
	if SkilletMerchantBuyFrame:IsVisible() then
		--DA.DEBUG(1,"Merchant Buy Button should already be there")
		return true		-- already inserted the button
	end
	--DA.DEBUG(1,"Create and show the Merchant Buy Button")
	SkilletMerchantBuyFrameButton:SetText(L["Reagents"])
	SkilletMerchantBuyFrame:SetPoint("TOPLEFT", "MerchantFrame", "TOPLEFT" , 55, -5) -- May need to be adjusted for each WoW build
	SkilletMerchantBuyFrame:SetFrameStrata("HIGH")
	SkilletMerchantBuyFrame:Show()
	return true
end

--
-- Removes the merchant buy button
--
local function remove_merchant_buy_button()
	SkilletMerchantBuyFrame:Hide()
end

--
-- Updates the merchant frame, if it is visible, this method can be called
-- many times
--
function Skillet:UpdateMerchantFrame()
	Skillet:MerchantShow()
end

--
-- Merchant window opened
--
function Skillet:MERCHANT_SHOW()
	DA.TRACE("MERCHANT_SHOW()")
end

--
-- Merchant window updated
--
function Skillet:MERCHANT_UPDATE()
	DA.TRACE("MERCHANT_UPDATE()")
	if Skillet.db.profile.vendor_buy_button or Skillet.db.profile.vendor_auto_buy then
		update_merchant_inventory()
	end
end

--
-- Merchant window closed
--
function Skillet:MERCHANT_CLOSED()
	DA.TRACE("MERCHANT_CLOSED()")
	remove_merchant_buy_button()
	merchant_inventory = {}
	self.autoPurchaseComplete = nil
	self:HideShoppingList()
end

--
-- Merchant window opened. This method can be called multiple
-- times if needed, and it can be called even if a merchant window
-- is not open.
--
function Skillet:MerchantShow()
	--DA.DEBUG(0,"MerchantShow()")
	if MerchantFrame and not MerchantFrame:IsVisible() then
		DA.DEBUG(1,"MerchantFrame= "..tostring(MerchantFrame)..", IsVisible= "..tostring(MerchantFrame:IsVisible()))
		return
	end
	merchant_inventory = {}
	if Skillet.db.profile.vendor_buy_button or Skillet.db.profile.vendor_auto_buy then
		update_merchant_inventory()
	end
	if Skillet.db.profile.vendor_auto_buy then
		if not self.autoPurchaseComplete then
			self.autoPurchaseComplete = true		-- annoying lag causes multiple purchases because merchant frame shows again before our bags update
			self:BuyRequiredReagents()
		else
			update_merchant_buy_button()
		end
	elseif Skillet.db.profile.vendor_buy_button then
		update_merchant_buy_button()
	end
end

--
-- If at a vendor with the window open, buy anything that they
-- sell that is required by any queued recipe.
--
function Skillet:BuyRequiredReagents()
	--DA.DEBUG(0,"BuyRequiredReagents()")
	local list = get_shopping_list()
	if #list == 0 then
		return
	elseif does_merchant_sell_required_items(list) == false then
		return
	elseif not MerchantFrame or MerchantFrame:IsVisible() == false then
		return
	end
	local totalspent = 0
	local purchased = 0
--
-- for each item they sell, see if we need it and if so, buy it.
--
	local numItems = GetMerchantNumItems()
	for i=1, numItems, 1 do
		local link = GetMerchantItemLink(i)
		if link then
			local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
			if numAvailable == -1 then			-- only buy unlimited items automatically.
				local id = self:GetItemIDFromLink(link)
--
-- OK, lets see if we need it.
--
				local count = 0
				for j=1,#list,1 do
					if list[j].id == id then
						count = list[j].count
						break
					end
				end
				if count > 0 then
					purchased = 0;
--					count = math.ceil(count/quantity) * quantity	-- merchant charges us full price for a partial stack, so round up.
					if GetMerchantItemCostInfo(i) > 0 then			-- if not sold for alternate currency, merchant will sell partial stacks.
						count = math.ceil(count/quantity) * quantity 
					end
					local maxStack = GetMerchantItemMaxStack(i)
					DA.DEBUG(0,"count= "..tostring(count)..", name= "..tostring(name)..", price= "..tostring(price)..", quantity= "..tostring(quantity)..
						", maxStack= "..tostring(maxStack)..", extendedCost= "..tostring(extendedCost))
					while count > 0 do				-- if there is not enough currency, a UI_ERROR_MESSAGE event is generated (which Skillet ignores)
						if count <= maxStack then
							BuyMerchantItem(i,count)
							purchased = purchased + count
							count = 0
						else
							BuyMerchantItem(i,maxStack)
							purchased = purchased + maxStack
							count = count - maxStack
						end
					end
					local itemspent = price * purchased / quantity -- spent on this type of item
					totalspent = totalspent + itemspent  -- spent on all items from this merchant
					local message = L["Purchased"]
					local cash = Skillet:FormatMoneyFull(itemspent, true);
					message = message..": "..tostring(purchased).." x "..link.." ("..cash..")"
					self:Print(message);
				end
			end
		end
	end
	if totalspent > 0 and purchased > 1 then
		local message = L["Total spent"]
		local cash = Skillet:FormatMoneyFull(totalspent, true)
		message = message..": "..cash
		self:Print(message)
	end
	self:InventoryScan()
	update_merchant_buy_button()
end

function Skillet:MerchantBuyButton_OnEnter(button)
	--DA.DEBUG(0,"BuyRequiredReagents("..tostring(button)..")")
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(L["Buy Reagents"])
	local needList = get_shopping_list()
	local totalCost = 0
	for i=1,#needList,1 do
		local itemID = needList[i].id
		if merchant_inventory[itemID] then
			local cost = merchant_inventory[itemID].price * math.ceil(needList[i].count / merchant_inventory[itemID].quantity)
			totalCost = totalCost + cost
			GameTooltip:AddDoubleLine((GetItemInfo(itemID)).." x "..needList[i].count, Skillet:FormatMoneyFull(cost, true),1,1,0)
		end
	end
	if #needList > 1 then
		GameTooltip:AddDoubleLine(L["Total Cost:"], Skillet:FormatMoneyFull(totalCost, true),0,1,0)
	end
	GameTooltip:Show()
end

function Skillet:MerchantBuyButton_OnLeave(button)
	--DA.DEBUG(0,"TradeButtonAdditional_OnEnter("..tostring(button)..")")
	--DA.DEBUG(0,"MerchantBuyButton_OnLeave("..tostring(button)..")")
	GameTooltip:Hide()
end
