-- Delirium Roads - the work orders window: every order with its City Hall,
-- area and how many tiles were mended in it; the hall's mayor (or an admin)
-- closes, reopens or deletes the selected one. New orders are marked from
-- the world context menu (two corners).

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "DR_Client"

DelRoadsOrdersUI = ISCollapsableWindow:derive("DelRoadsOrdersUI")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local ROW_HGT = FONT_HGT_SMALL + 6
local WIDTH = 720
local HEIGHT = 420

local COLUMNS = {
	{ title = "IGUI_DelRoads_Col_Id", x = 0, field = "id" },
	{ title = "IGUI_DelRoads_Col_Hall", x = 40, field = "hall", trim = 20 },
	{ title = "IGUI_DelRoads_Col_Title", x = 200, field = "title", trim = 28 },
	{ title = "IGUI_DelRoads_Col_Area", x = 410, field = "area" },
	{ title = "IGUI_DelRoads_Col_Done", x = 570, field = "done" },
	{ title = "IGUI_DelRoads_Col_Status", x = 630, field = "status" },
}

function DelRoadsOrdersUI.open(player)
	local old = DelRoads.windows.orders
	if old then old:close() end
	local x = (getCore():getScreenWidth() - WIDTH) / 2
	local y = (getCore():getScreenHeight() - HEIGHT) / 2
	local ui = DelRoadsOrdersUI:new(x, y, WIDTH, HEIGHT, player)
	ui:initialise()
	ui:instantiate()
	ui.pinButton:setVisible(false)
	ui.collapseButton:setVisible(false)
	ui:addToUIManager()
	DelRoads.windows.orders = ui
	ui:refresh()
	return ui
end

local function drawRow(list, y, item, alt)
	local row = item.item
	if list.selected == item.index then
		list:drawRect(0, y, list:getWidth(), list.itemheight, 0.3, 0.7, 0.35, 0.15)
	elseif alt then
		list:drawRect(0, y, list:getWidth(), list.itemheight, 0.15, 0.3, 0.3, 0.3)
	end
	local ty = y + (list.itemheight - FONT_HGT_SMALL) / 2
	local shade = row.closed and 0.55 or 1
	for _, column in ipairs(COLUMNS) do
		local text = DelShops.trimString(tostring(row[column.field] or ""), column.trim or 40)
		list:drawText(text, column.x + 4, ty, shade, shade, shade, 1, UIFont.Small)
	end
	return y + list.itemheight
end

local function addButton(self, x, y, key, handler)
	local title = getText(key)
	local w = getTextManager():MeasureStringX(UIFont.Small, title) + 20
	local button = ISButton:new(x, y, w, BUTTON_HGT, title, self, handler)
	button:initialise()
	button:instantiate()
	button.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
	self:addChild(button)
	return button
end

function DelRoadsOrdersUI:createChildren()
	ISCollapsableWindow.createChildren(self)
	local x = PAD
	local y = self:titleBarHeight() + PAD
	self.headerY = y
	y = y + ROW_HGT
	local listH = self.height - y - PAD * 3 - BUTTON_HGT - ROW_HGT
	self.list = ISScrollingListBox:new(x, y, self.width - PAD * 2, listH)
	self.list:initialise()
	self.list:instantiate()
	self.list.itemheight = ROW_HGT
	self.list.font = UIFont.Small
	self.list.drawBorder = true
	self.list.doDrawItem = drawRow
	self:addChild(self.list)
	self.infoY = self.list:getBottom() + PAD / 2

	local by = self.height - PAD - BUTTON_HGT
	self.toggleBtn = addButton(self, PAD, by, "IGUI_DelRoads_CloseOrder", DelRoadsOrdersUI.onToggle)
	self.deleteBtn = addButton(self, self.toggleBtn:getRight() + PAD, by, "IGUI_DelRoads_DeleteOrder",
		DelRoadsOrdersUI.onDelete)
end

function DelRoadsOrdersUI:selectedRow()
	local item = self.list.items[self.list.selected]
	return item and item.item
end

function DelRoadsOrdersUI:refresh()
	local keep = self:selectedRow()
	keep = keep and keep.id
	self.list:clear()
	local orders = DelRoads.getOrders()
	local state = DelEcon.getState()
	for _, id in ipairs(DelRoads.orderIds(orders)) do
		local order = orders.list[id]
		local row = {
			id = id,
			hall = DelEcon.hallName(DelEcon.getHall(state, order.hall) or { name = "?" }),
			hallId = order.hall,
			title = order.title or "",
			area = string.format("%d,%d - %d,%d", order.x1, order.y1, order.x2, order.y2),
			done = tostring(order.done or 0),
			status = getText(order.closed and "IGUI_DelRoads_Closed" or "IGUI_DelRoads_Open"),
			closed = order.closed == true,
			order = order,
		}
		self.list:addItem("", row)
		if keep == id then self.list.selected = #self.list.items end
	end
	if not self.list.selected or self.list.selected > #self.list.items then self.list.selected = 1 end
end

function DelRoadsOrdersUI:canManage(row)
	if not row then return false end
	return DelShops.hasAdminRights(self.player)
		or DelEcon.canManage(DelEcon.getHall(DelEcon.getState(), row.hallId), self.player)
end

function DelRoadsOrdersUI:onToggle()
	local row = self:selectedRow()
	if not self:canManage(row) then return end
	DelRoads.send("setOrderClosed", { id = row.id, closed = not row.closed })
end

function DelRoadsOrdersUI:onDelete()
	local row = self:selectedRow()
	if not self:canManage(row) then return end
	DelRoads.send("deleteOrder", { id = row.id })
end

function DelRoadsOrdersUI:prerender()
	ISCollapsableWindow.prerender(self)
	local row = self:selectedRow()
	local manage = self:canManage(row)
	self.toggleBtn:setVisible(manage)
	self.deleteBtn:setVisible(manage)
	if row then
		self.toggleBtn:setTitle(getText(row.closed and "IGUI_DelRoads_ReopenOrder" or "IGUI_DelRoads_CloseOrder"))
	end
end

function DelRoadsOrdersUI:render()
	ISCollapsableWindow.render(self)
	local hy = self.headerY + (ROW_HGT - FONT_HGT_SMALL) / 2
	for _, column in ipairs(COLUMNS) do
		self:drawText(getText(column.title), self.list.x + column.x + 4, hy, 0.8, 0.8, 0.8, 1, UIFont.Small)
	end
	local info
	local row = self:selectedRow()
	if #self.list.items == 0 then
		info = getText("IGUI_DelRoads_NoOrders")
	elseif row then
		local order = row.order
		local px, py = self.player:getX(), self.player:getY()
		local dx = math.max(order.x1 - px, 0, px - order.x2 - 1)
		local dy = math.max(order.y1 - py, 0, py - order.y2 - 1)
		local distance = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
		if distance == 0 then
			info = getText("IGUI_DelRoads_InsideOrder", tostring(order.by or ""))
		else
			info = getText("IGUI_DelRoads_OrderDistance", tostring(distance), tostring(order.by or ""))
		end
	end
	if info then self:drawText(info, PAD, self.infoY, 0.7, 0.7, 0.7, 1, UIFont.Small) end
end

function DelRoadsOrdersUI:close()
	ISCollapsableWindow.close(self)
	self:removeFromUIManager()
	if DelRoads.windows.orders == self then DelRoads.windows.orders = nil end
end

function DelRoadsOrdersUI:new(x, y, width, height, player)
	local o = ISCollapsableWindow:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.player = player
	o.title = getText("IGUI_DelRoads_Orders")
	o.resizable = false
	return o
end
