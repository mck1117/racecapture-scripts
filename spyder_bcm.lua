-- PWM0: ABS fault light
startPwm(0, 0, 0)
-- PWM1: EHPAS fault light
startPwm(1, 0, 0)

-- "alive" message from pump
canRxAdd(0x1B200002)
canRxAdd(0x1a0)

local pumpAlive = Timer.new()
local pumpRestart = Timer.new()

local vssSensor = Sensor.new("VehicleSpeed")
vssSensor:setTimeout(100)

function onCanRx(bus, id, dlc, data)
	if id == 0x1B200002 then
		if pumpAlive:getElapsedSeconds() > 1 then
			pumpRestart:reset()
		end

		pumpAlive:reset()
	end

	if id == 0x1a0 then
		local vss = 0.1 * (data[1] + ((data[2] & 0x0F) << 8))
		vssSensor:set(vss)
	end
end

local data_0x1ae0092c = { 0x00, 0x00, 0x22, 0xe0, 0x41, 0x90, 0x00, 0x00 }
local data_0x02104136 = { 0xbb, 0x00, 0x3f, 0xff, 0x06, 0xe0, 0x00, 0x00 }

local slowCounter = 0
local slowRoll = 0

local slowRollTable = { 0x00, 0x40, 0x80, 0xC0 }

-- car stopped is 0
-- car "moving fast" is 6000 (whatever that means?)
local speedVal = 13000

function updatePowerSteering()
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

		-- Turn off the fault light
		setPwmDuty(1, 1)
	else
		-- Turn on the fault light
		setPwmDuty(1, 0)
	end
end

function onTick()
	updatePowerSteering()
end

setTickRate(71)

-- start with both fault lights on
setPwmDuty(0, 0)
setPwmDuty(1, 0)
