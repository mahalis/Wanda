require "vectors"

local world

local leftWall, rightWall, floor, bot, anchor

local targets = {}

local elapsedTime = 0
local started = false

WALL_THICKNESS = 20
TARGET_SIZE = 20
TARGET_DIE_TIME = 0.4
NEW_TARGET_MIN_DISTANCE_FROM_PLAYER = 2 * TARGET_SIZE
TARGET_GROW_TIME = 0.2

local score = 0
local scoreChangedTime = -1

local backgroundImage, wandaImage
local ringImages = {}

local scoreBigFont, scoreLittleFont

-- need to keep track of fixtures for world callback collisions

local function contactBegan(fixture1, fixture2, contact)
	local botFixture = bot.fixture
	if fixture1 == botFixture or fixture2 == botFixture then
		for i = 1, #targets do
			local target = targets[i]
			local targetFixture = target.fixture
			if target.lastTouchTime < 0 and (fixture1 == targetFixture or fixture2 == targetFixture) then
				-- contacted this target
				adjustScore(3)
				target.lastTouchTime = elapsedTime -- we’ll remove it in update() later — not safe to do that in physics callback
				break
			end
		end

		if fixture1 == floor.fixture or fixture2 == floor.fixture then
			-- what happens when you hit the floor?
		end
	end
end

function slerp(a, b, f)
	f = math.max(math.min(f, 1), 0)

	return a + (b - a) * (1 - math.cos(f * math.pi)) / 2
end

function love.load()
	love.graphics.setBackgroundColor(56, 60, 64)
	love.graphics.setLineStyle("smooth")

	backgroundImage = love.graphics.newImage("graphics/background.jpg")
	wandaImage = love.graphics.newImage("graphics/wanda.png")
	for i = 1, 3 do
		ringImages[i] = love.graphics.newImage("graphics/ring" .. tostring(i) .. ".png")
	end

	scoreBigFont = love.graphics.newFont(30)
	scoreLittleFont = love.graphics.newFont(20)

	local w, h = love.window.getDimensions()
	world = love.physics.newWorld(0, 400) -- second parameter is Y gravity
	world:setCallbacks(contactBegan, nil, nil, nil)

	leftWall = {}
	leftWall.shape = love.physics.newRectangleShape(WALL_THICKNESS, h * 1.5)
	leftWall.body = love.physics.newBody(world, WALL_THICKNESS / 2, h / 2)
	leftWall.fixture = love.physics.newFixture(leftWall.body, leftWall.shape)
	leftWall.fixture:setRestitution(1)

	rightWall = {}
	rightWall.shape = love.physics.newRectangleShape(WALL_THICKNESS, h * 1.5)
	rightWall.body = love.physics.newBody(world, w - WALL_THICKNESS / 2, h / 2)
	rightWall.fixture = love.physics.newFixture(rightWall.body, rightWall.shape)
	rightWall.fixture:setRestitution(1)

	floor = {}
	floor.shape = love.physics.newRectangleShape(w - 2 * WALL_THICKNESS, WALL_THICKNESS)
	floor.body = love.physics.newBody(world, w / 2, h * 1.25)
	floor.fixture = love.physics.newFixture(floor.body, floor.shape)
	floor.fixture:setRestitution(1)

	ceiling = {}
	ceiling.shape = love.physics.newRectangleShape(w - 2 * WALL_THICKNESS, WALL_THICKNESS)
	ceiling.body = love.physics.newBody(world, w / 2, WALL_THICKNESS / 2)
	ceiling.fixture = love.physics.newFixture(ceiling.body, ceiling.shape)
	ceiling.fixture:setRestitution(1)

	bot = {}
	bot.shape = love.physics.newCircleShape(30)
	bot.body = love.physics.newBody(world, 0, 0, "dynamic") -- 0,0 for now — reset() is responsible for the actual starting position
	bot.fixture = love.physics.newFixture(bot.body, bot.shape)
	bot.fixture:setRestitution(0.9)

	anchor = {}
	anchor.body = love.physics.newBody(world, 0, 0, "static")

	reset()
end

function love.draw()
	love.graphics.setColor(255, 255, 255, 255)
	local w, h = love.window.getDimensions()
	
	love.graphics.draw(backgroundImage, 0, 0)

	local ringW, ringH = ringImages[1]:getDimensions()
	for i = 1, #targets do
		local target = targets[i]
		local x = target.body:getX()
		local y = target.body:getY()
		local deathTime = (elapsedTime - target.lastTouchTime) / TARGET_DIE_TIME

		local growthTime = (elapsedTime - target.spawnTime) / TARGET_GROW_TIME
		local scale = 1
		if growthTime < 1 then
			if growthTime < 0.5 then
				scale = slerp(0, 1.2, growthTime / 0.5)
			else
				scale = slerp(1.2, 1, (growthTime - 0.5) / 0.5)
			end
		elseif target.lastTouchTime > 0 then
			if deathTime < 0.3 then
				scale = slerp(1, 1.2, deathTime / 0.3)
			else
				scale = slerp(1.2, 0, (deathTime - 0.3) / 0.7)
			end
		end
		love.graphics.draw(ringImages[1 + (math.floor((elapsedTime + target.random * 3) * 10) % 3)], x, y, 0, scale, scale, ringW / 2, ringH / 2)
	end

	
	love.graphics.setColor(0, 0, 0, 255)
	if anchor.joint then
		love.graphics.circle("fill", anchor.body:getX(), anchor.body:getY(), 4, 20)
		local mouthX, mouthY = bot.body:getWorldPoint(0, 0)
		love.graphics.line(anchor.body:getX(), anchor.body:getY(), mouthX, mouthY)
	end

	love.graphics.setColor(255, 255, 255, 255)
	local wandaW, wandaH = wandaImage:getDimensions()
	love.graphics.draw(wandaImage, bot.body:getX(), bot.body:getY(), bot.body:getAngle(), 1, 1, wandaW / 2, wandaH / 2)

	love.graphics.setColor(60, 80, 100, 255)
	love.graphics.setFont(scoreBigFont)
	love.graphics.printf(string.format("%03d", score), 18, h - 48, 60, "left")
	love.graphics.setColor(60, 80, 100, 128)
	love.graphics.setFont(scoreLittleFont)
	love.graphics.printf("score", 80, h - 38, 60, "left")
end

function adjustScore(value)
	local lastScore = score
	score = math.max(0, score + value)
	if score ~= lastScore then
		scoreChangedTime = elapsedTime
	end
end

function makeTarget(x, y)
	target = {}
	target.shape = love.physics.newCircleShape(TARGET_SIZE)
	target.body = love.physics.newBody(world, x, y, "static")
	target.fixture = love.physics.newFixture(target.body, target.shape)
	target.fixture:setSensor(true)
	target.spawnTime = elapsedTime
	target.lastTouchTime = -1
	target.random = math.random()
	return target
end

function clearTargets()
	for i = 1, #targets do
		local target = targets[i]
		target.fixture:destroy()
		target.body:destroy()
	end
	targets = {}
end

function breakAnchor()
	if anchor.joint then
		anchor.joint:destroy()
	end
	anchor.joint = nil
end

function makeAnchor(x, y)
	breakAnchor()
	anchor.body:setPosition(x,y)
	local botX, botY = bot.body:getWorldPoint(0,0)
	anchor.joint = love.physics.newDistanceJoint(anchor.body, bot.body, x, y, botX, botY)

	-- apply force in the current direction of movement but orthogonal to the joint
	local toBot = vNorm(vSub(v(botX, botY), v(x, y)))
	local velX, velY = bot.body:getLinearVelocity()
	local botDirection = vNorm(v(velX, velY))
	local impulse = vNorm(vSub(botDirection, vMul(toBot, vDot(botDirection, toBot))), 1200)
	local cX, cY = bot.body:getWorldCenter()
	bot.body:applyLinearImpulse(impulse.x, impulse.y, cX, cY)

	adjustScore(-2)
end

function love.update(dt)
	if started then
		-- TODO: if we go into slow motion, just multiply this dt value in advance before using it below
		elapsedTime = elapsedTime + dt
		world:update(dt)
		for i = 1, #targets do
			if targets[i].lastTouchTime > 0 and elapsedTime > targets[i].lastTouchTime + TARGET_DIE_TIME then
				newPosition = chooseNewTargetPosition()
				if newPosition then
					targets[i].fixture:destroy()
					targets[i].body:destroy()
					
					targets[i] = makeTarget(newPosition.x, newPosition.y)
				else
					-- gross, but oh well.
					targets[i].lastTouchTime = -1
				end
			end
		end
	end
end

function reset()
	clearTargets()
	breakAnchor()

	local w, h = love.window.getDimensions()
	bot.body:setPosition(w / 2, h * 0.2)
	bot.body:setAngularVelocity(0)
	bot.body:setLinearVelocity(0, 0)
	started = false
end

function start()
	for i = 1, 3 do
		local p = chooseNewTargetPosition()
		if p then
			targets[#targets + 1] = makeTarget(p.x, p.y)
		end
	end
	started = true
end

function love.mousepressed(x, y, button)
	if not started then
		start()
	else
		makeAnchor(x,y)
	end
end

function love.mousereleased(x, y, button)
	breakAnchor()
end

function randomTargetPosition(w, h)
	return v((0.1 + math.random() * 0.8) * w, (0.1 + math.random() * 0.8) * h)
end

function chooseNewTargetPosition()
	local w, h = love.window.getDimensions()
	local i = 0
	local foundPosition = nil
	while i < 100 and not foundPosition do
		local p = randomTargetPosition(w, h)
		local intersects = false
		if vDist(p, v(bot.body:getX(), bot.body:getY())) < TARGET_SIZE * 3 then
			intersects = true
			break
		end
		if #targets > 0 then
			for j = 1, #targets do
				if vDist(v(targets[j].body:getX(), targets[j].body:getY()), p) < TARGET_SIZE * 4 then
					intersects = true
					break
				end
			end
		end
		if not intersects then
			foundPosition = p
		end
		i = i + 1
	end
	return foundPosition
end
