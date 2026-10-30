-- Delirium Roads - the work orders window: customer hall, price, contractor
-- hall and progress of every order. Buttons depend on who looks at the
-- selected one: staff of another hall accept it, the contractor reports it
-- done (paid at once) or gives it back, the customer's mayor deletes it;
-- anyone may show its area on the ground and on the world map. New orders
-- are marked from the world context menu (two corners).

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "DR_Client"
require "DR_Track"

DelRoadsOrdersUI = ISCollapsableWindow:derive("DelRoadsOrdersUI")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10
local GAP = 16
local SCROLLBAR = 16
local BUTTON_HGT = FONT_HGT_SMALL + 6
local ROW_HGT = FONT_HGT_SMALL + 6
local MIN_WIDTH = 640
local HEIGHT = 440

-- Widths are measured from the header and the rows on every refresh;
-- max caps the long free-text ones (cut with "...").
local COLUMNS = {
	{ title = "IGUI_DelRoads_Col_Id", field = "id" },
	{ title = "IGUI_DelRoads_Col_Customer", field = "customer", max = 170 },
	{ title = "IGUI_DelRoads_Col_Title", field = "title", max = 240 },
	{ title = "IGUI_DelRoads_Col_Price", field = "price" },
	{ title = "IGUI_DelRoads_Col_Contractor", field = "contractor", max = 170 },
	{ title = "IGUI_DelRoads_Col_Done", field = "done" },
	{ title = "IGUI_DelRoads_Col_Status", field = "status" },
}

local STATUS_KEY = {
	open = "IGUI_DelRoads_StatusOpen",
	accepted = "IGUI_DelRoads_StatusAccepted",
	done = "IGUI_DelRoads_StatusDone",
}

local function measure(text)
	return getTextManager():MeasureStringX(UIFont.Small, text)
end

local function fitText(text, width)
	if measure(text) <= width then return text end
	local cut = text
	while #cut > 0 and measure(cut .. "...") > width do
		cut = string.sub(cut, 1, #cut - 1)
	end
	return cut .. "..."
end

-- Compass direction from the player to a point, map north up (north = -y).
local DIRECTIONS = { "E", "SE", "S", "SW", "W", "NW", "N", "NE" }

local function direction(dx, dy)
	local angle = math.atan2(dy, dx)
	local sector = (math.floor(angle / (math.pi / 4) + 0.5) + 8) % 8
	return getText("IGUI_DelRoads_Dir_" .. DIRECTIONS[sector + 1])
end

function DelRoadsOrdersUI.open(player)
	local old = DelRoads.windows.orders
	if old then old:close() end
	local x = (getCore():getScreenWidth() - MIN_WIDTH) / 2
	local y = (getCore():getScreenHeight() - HEIGHT) / 2
	local ui = DelRoadsOrdersUI:new(x, y, MIN_WIDTH, HEIGHT, player)
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
	local ui = list.ordersUI
	local row = item.item
	if list.selected == item.index then
		list:drawRect(0, y, list:getWidth(), list.itemheight, 0.3, 0.7, 0.35, 0.15)
	elseif alt then
		list:drawRect(0, y, list:getWidth(), list.itemheight, 0.15, 0.3, 0.3, 0.3)
	end
	local ty = y + (list.itemheight - FONT_HGT_SMALL) / 2
	local shade = row.status == DelRoads.DONE and 0.55 or 1
	for _, column in ipairs(COLUMNS) do
		local text = row.cells[column.field] or ""
		list:drawText(text, ui.columnX[column.field] + 4, ty, shade, shade, shade, 1, UIFont.Small)
	end
	if DelRoads.isTracked(row.id) then
		list:drawRect(0, y + 2, 3, list.itemheight - 4, 1, 1.0, 0.75, 0.1)
	end
	return y + list.itemheight
end

local function addButton(self, key, handler)
	local button = ISButton:new(0, 0, 10, BUTTON_HGT, getText(key), self, handler)
	button:initialise()
	button:instantiate()
	button.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
	self:addChild(button)
	table.insert(self.buttons, button)
	return button
end

function DelRoadsOrdersUI:createChildren()
	ISCollapsableWindow.createChildren(self)
	local y = self:titleBarHeight() + PAD
	self.headerY = y
	y = y + ROW_HGT
	local listH = self.height - y - PAD * 3 - BUTTON_HGT - FONT_HGT_SMALL * 2 - 4
	self.list = ISScrollingListBox:new(PAD, y, self.width - PAD * 2, listH)
	self.list:initialise()
	self.list:instantiate()
	self.list.itemheight = ROW_HGT
	self.list.font = UIFont.Small
	self.list.drawBorder = true
	self.list.doDrawItem = drawRow
	self.list.ordersUI = self
	self:addChild(self.list)
	self.infoY = self.list:getBottom() + PAD / 2

	self.buttons = {}
	self.acceptBtn = addButton(self, "IGUI_DelRoads_Accept", DelRoadsOrdersUI.onAccept)
	self.doneBtn = addButton(self, "IGUI_DelRoads_Complete", DelRoadsOrdersUI.onComplete)
	self.refuseBtn = addButton(self, "IGUI_DelRoads_Refuse", DelRoadsOrdersUI.onRefuse)
	self.deleteBtn = addButton(self, "IGUI_DelRoads_DeleteOrder", DelRoadsOrdersUI.onDelete)
	self.trackBtn = addButton(self, "IGUI_DelRoads_ShowArea", DelRoadsOrdersUI.onTrack)
	self.mapBtn = addButton(self, "IGUI_DelRoads_ShowMap", DelRoadsOrdersUI.onMap)
end

function DelRoadsOrdersUI:selectedRow()
	local item = self.list.items[self.list.selected]
	return item and item.item
end

-- Columns sized to what they hold, the window to the columns.
function DelRoadsOrdersUI:layoutColumns(rows)
	local x = 0
	self.columnX = {}
	for _, column in ipairs(COLUMNS) do
		local width = measure(getText(column.title))
		for _, row in ipairs(rows) do
			width = math.max(width, measure(row.cells[column.field] or ""))
		end
		if column.max then width = math.min(width, column.max) end
		for _, row in ipairs(rows) do
			row.cells[column.field] = fitText(row.cells[column.field] or "", width)
		end
		self.columnX[column.field] = x
		x = x + width + GAP
	end
	local wanted = math.max(MIN_WIDTH, x + PAD * 2 + SCROLLBAR)
	wanted = math.min(wanted, getCore():getScreenWidth() - 40)
	if wanted ~= self.width then
		self:setWidth(wanted)
		self.list:setWidth(wanted - PAD * 2)
	end
end

function DelRoadsOrdersUI:refresh()
	local keep = self:selectedRow()
	keep = keep and keep.id
	local orders = DelRoads.getOrders()
	local state = DelEcon.getState()
	local rows = {}
	for _, id in ipairs(DelRoads.orderIds(orders)) do
		local order = orders.list[id]
		local contractor = order.contractor and DelEcon.getHall(state, order.contractor)
		table.insert(rows, {
			id = id,
			order = order,
			status = order.status,
			cells = {
				id = id,
				customer = DelEcon.hallName(DelEcon.getHall(state, order.hall) or { name = "?" }),
				title = order.title or "",
				price = Currency.format(order.price or 0),
				contractor = contractor and DelEcon.hallName(contractor) or "-",
				done = tostring(order.done or 0),
				status = getText(STATUS_KEY[order.status] or "IGUI_DelRoads_StatusOpen"),
			},
		})
	end
	self:layoutColumns(rows)
	self.list:clear()
	for _, row in ipairs(rows) do
		self.list:addItem("", row)
		if keep == row.id then self.list.selected = #self.list.items end
	end
	if not self.list.selected or self.list.selected > #self.list.items then self.list.selected = 1 end
end

-- ---------------------------------------------------------------------------
-- Who may do what with the selected order (the server checks again)
-- ---------------------------------------------------------------------------

function DelRoadsOrdersUI:acceptHall(row)
	if not row or row.order.status ~= DelRoads.OPEN then return nil end
	return DelRoads.contractorHalls(row.order, self.player)[1]
end

function DelRoadsOrdersUI:isContractor(row)
	return row ~= nil and DelRoads.isContractor(row.order, self.player)
end

function DelRoadsOrdersUI:isCustomer(row)
	return row ~= nil and DelEcon.canManage(DelEcon.getHall(DelEcon.getState(), row.order.hall), self.player)
end

function DelRoadsOrdersUI:onAccept()
	local row = self:selectedRow()
	local hallId = self:acceptHall(row)
	if hallId then DelRoads.send("acceptOrder", { id = row.id, hall = hallId }) end
end

local function confirm(self, text, command, id)
	local w, h = 380, 150
	local dialog = ISModalDialog:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h,
		text, true, self, function(target, button)
			if button.internal == "YES" then DelRoads.send(command, { id = id }) end
		end, self.player:getPlayerNum())
	dialog:initialise()
	dialog:addToUIManager()
end

function DelRoadsOrdersUI:onComplete()
	local row = self:selectedRow()
	if not self:isContractor(row) then return end
	confirm(self, getText("IGUI_DelRoads_ConfirmComplete", row.cells.title, Currency.format(row.order.price or 0)),
		"completeOrder", row.id)
end

function DelRoadsOrdersUI:onRefuse()
	local row = self:selectedRow()
	if self:isContractor(row) then DelRoads.send("refuseOrder", { id = row.id }) end
end

function DelRoadsOrdersUI:onDelete()
	local row = self:selectedRow()
	if not self:isCustomer(row) then return end
	confirm(self, getText("IGUI_DelRoads_ConfirmDelete", row.cells.title), "deleteOrder", row.id)
end

function DelRoadsOrdersUI:onTrack()
	local row = self:selectedRow()
	if row then DelRoads.setTracked(row.id, not DelRoads.isTracked(row.id)) end
end

function DelRoadsOrdersUI:onMap()
	local row = self:selectedRow()
	if row then DelRoads.showOnMap(self.player, row.id) end
end

function DelRoadsOrdersUI:prerender()
	ISCollapsableWindow.prerender(self)
	local row = self:selectedRow()
	local active = row ~= nil and row.order.status ~= DelRoads.DONE
	local acceptHall = self:acceptHall(row)
	if acceptHall then
		self.acceptBtn:setTitle(getText("IGUI_DelRoads_AcceptFor",
			DelEcon.hallName(DelEcon.getHall(DelEcon.getState(), acceptHall))))
	end
	self.acceptBtn:setVisible(acceptHall ~= nil)
	self.doneBtn:setVisible(self:isContractor(row))
	self.refuseBtn:setVisible(self:isContractor(row))
	self.deleteBtn:setVisible(self:isCustomer(row))
	self.trackBtn:setVisible(active)
	self.mapBtn:setVisible(active)
	if active then
		self.trackBtn:setTitle(getText(DelRoads.isTracked(row.id) and "IGUI_DelRoads_HideArea" or "IGUI_DelRoads_ShowArea"))
	end
	local x = PAD
	local y = self.height - PAD - BUTTON_HGT
	for _, button in ipairs(self.buttons) do
		if button:isVisible() then
			button:setWidth(measure(button.title) + 20)
			button:setX(x)
			button:setY(y)
			x = x + button:getWidth() + PAD / 2
		end
	end
end

function DelRoadsOrdersUI:render()
	ISCollapsableWindow.render(self)
	local hy = self.headerY + (ROW_HGT - FONT_HGT_SMALL) / 2
	for _, column in ipairs(COLUMNS) do
		self:drawText(getText(column.title), self.list.x + self.columnX[column.field] + 4, hy, 0.8, 0.8, 0.8, 1,
			UIFont.Small)
	end
	local row = self:selectedRow()
	if #self.list.items == 0 then
		self:drawText(getText("IGUI_DelRoads_NoOrders"), PAD, self.infoY, 0.7, 0.7, 0.7, 1, UIFont.Small)
		return
	end
	if not row then return end
	local order = row.order
	local area = string.format("%d,%d - %d,%d", order.x1, order.y1, order.x2, order.y2)
	local where
	local px, py = self.player:getX(), self.player:getY()
	local nx = math.max(order.x1, math.min(px, order.x2 + 1))
	local ny = math.max(order.y1, math.min(py, order.y2 + 1))
	local distance = math.floor(math.sqrt((nx - px) * (nx - px) + (ny - py) * (ny - py)) + 0.5)
	if distance == 0 then
		where = getText("IGUI_DelRoads_Inside", area)
	else
		where = getText("IGUI_DelRoads_Distance", area, tostring(distance), direction(nx - px, ny - py))
	end
	self:drawText(where, PAD, self.infoY, 0.8, 0.8, 0.8, 1, UIFont.Small)
	local who = getText("IGUI_DelRoads_GivenBy", tostring(order.by or ""))
	if order.acceptedBy then who = who .. "   " .. getText("IGUI_DelRoads_AcceptedBy", order.acceptedBy) end
	if order.doneBy then who = who .. "   " .. getText("IGUI_DelRoads_DoneBy", order.doneBy) end
	self:drawText(who, PAD, self.infoY + FONT_HGT_SMALL + 2, 0.6, 0.6, 0.6, 1, UIFont.Small)
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
	o.columnX = {}
	return o
end
