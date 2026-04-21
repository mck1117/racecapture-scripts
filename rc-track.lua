setTickRate(25)

function onTick()
	local lat,lon = getGpsPos()
	local latInt = math.floor(lat*10000000)
	local lonInt = -math.floor(lon*10000000)

	local lat1 = bit.band(latInt, 255);
	latInt = bit.rshift(latInt, 8);
	local lat2 = bit.band(latInt, 255);
	latInt = bit.rshift(latInt, 8);
	local lat3 = bit.band(latInt, 255);
	latInt = bit.rshift(latInt, 8);
	local lat4 = bit.band(latInt, 255);

	local lon1 = bit.band(lonInt, 255);
	lonInt = bit.rshift(lonInt, 8);
	local lon2 = bit.band(lonInt, 255);
	lonInt = bit.rshift(lonInt, 8);
	local lon3 = bit.band(lonInt, 255);
	lonInt = bit.rshift(lonInt, 8);
	local lon4 = bit.band(lonInt, 255);

	txCAN(0, 100, 0, {lat1, lat2, lat3, lat4, lon1, lon2, lon3, lon4}) 

	local gx = math.floor(50*getImu(0))
	local gy = math.floor(50*getImu(1))
	local gz = math.floor(50*getImu(2))
	local rz = math.floor(50*getImu(3))
	local speed = getGpsSpeed()

	if (gx < 0) then gx=256+gx end
	if (gy < 0) then gy=256+gy end
	if (gz < 0) then gz=256+gz end
	if (rz < 0) then rz=256+rz end

	txCAN(0, 101, 0, {gx, gy, gz, rz, speed, getGpsQuality(), getGpsSats()})
end
