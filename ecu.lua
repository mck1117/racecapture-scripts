function wakeMk60()
	-- Wake up the mk60
	txCan(1, 0x610, 0, { 0x20, 0x08, 0x29, 0x54, 0x4a, 0x00, 0x00, 0x00 })
	-- txCan(1, 0x316, 0, { 0x05, 0x36, 0x00, 0x00, 0x00, 0x12, 0x00, 0x00 });
	txCan(1, 0x329, 0, { 0x11, 0x8e, 0xc5, 0x08, 0x00, 0x00, 0x00, 0x00 });
	-- txCan(1, 0x613, 0, { 0x01, 0x5f, 0x39, 0x03, 0x00, 0x00, 0x00, 0x00 });
	-- txCan(1, 0x615, 0, { 0x00, 0x00, 0x00, 0x0d, 0x03, 0x00, 0x00, 0x00 });
end

function sendExtraCanData()
	local coolantPressure = getSensor('AuxLinear1')
	if coolantPressure == nil then coolantPressure = 0 end

	local gear = getSensor('DetectedGear')
	if gear == nil then gear = -1 end

	-- float switch indicates ~0 for "not low" and ~100 for "low"
	local fuelSensor = getSensor('AuxLinear2')
	if fuelSensor == nil then fuelSensor = -1 end

	txCan(1, 0x210, 0, { coolantPressure, gear, fuelSensor })
end

-- "alive" message from pump
canRxAdd(0x1B200002)

local pumpAlive = Timer.new()
local pumpRestart = Timer.new()

function onCanRx(bus, id, dlc, data)
	if id == 0x1B200002 then
		if pumpAlive:getElapsedSeconds() > 1 then
			pumpRestart:reset()
		end

		pumpAlive:reset()
	end
end

local data_0x1ae0092c = { 0x00, 0x00, 0x22, 0xe0, 0x41, 0x90, 0x00, 0x00 }
local data_0x02104136 = { 0xbb, 0x00, 0x3f, 0xff, 0x06, 0xe0, 0x00, 0x00 }

local slowCounter = 0
local slowRoll = 0

local slowRollTable = { 0x00, 0x40, 0x80, 0xC0 }

-- car stopped is 0
-- car "moving fast" is 6000 (whatever that means?)
local speedVal = 6000

local wakemk60counter = 0

local canDataCounter = 0

function onTick()
	if pumpAlive:getElapsedSeconds() < 1 then
		-- Ignition on frame: sends every 30th speed frame
		if slowCounter == 0 then
			-- cycle through 0, 40, 80, c0
			slowRoll = (slowRoll + 1) & 3
			data_0x1ae0092c[1] = slowRollTable[slowRoll + 1]

			txCan(1, 0x1ae0092c, 1, data_0x1ae0092c)

			slowCounter = 30
		end

		slowCounter = slowCounter - 1

		local speed = speedVal

		if pumpRestart:getElapsedSeconds() < 5 then
			speed = 0
		end

		data_0x02104136[7] = (speed >> 8) & 0xFF
		data_0x02104136[8] = speed & 0xFF

		-- pump speed frame
		txCan(1, 0x02104136, 1, data_0x02104136)
	end

	-- Send mk60 wakeup every 2 seconds (don't clog the bus)
	if wakemk60counter == 0 then
		wakeMk60()
		wakemk60counter = 142
	end
	wakemk60counter = wakemk60counter - 1

	-- Send extra ECU data at 10hz
	if canDataCounter == 0 then
		sendExtraCanData()
		canDataCounter = 7
	end
	canDataCounter = canDataCounter - 1
end

setTickRate(71)
