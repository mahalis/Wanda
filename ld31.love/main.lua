require "vectors"

local world

local leftWall, rightWall, floor, bot, anchor

local targets = {}

local elapsedTime = 0
local started = false

WALL_THICKNESS = 20
TARGET_SIZE = 30
TARGET_FADE_TIME = 0.4

-- need to keep track of fixtures for world callback collisions

local function contactBegan(fixture1, fixture2, contact)
	for i = 1, #targets do
		local target = targets[i]
		local targetFixture = target.fixture
		if fixture1 == targetFixture or fixture2 == targetFixture then
			target.lastTouchTime = elapsedTime
		end
	end
end

function love.load()
	love.graphics.setBackgroundColor(56, 60, 64)
	love.graphics.setLineStyle("smooth")
	local w, h = love.window.getDimensions()
	world = love.physics.newWorld(0, 400) -- second parameter is Y gravity
	world:setCallbacks(contactBegan, nil, nil, nil)

	leftWall = {}
	leftWall.shape = love.physics.newRectangleShape(WALL_THICKNESS, h)
	leftWall.body = love.physics.newBody(world, WALL_THICKNESS / 2, h / 2)
	leftWall.fixture = love.physics.newFixture(leftWall.body, leftWall.shape)
	leftWall.fixture:setRestitution(1)

	rightWall = {}
	rightWall.shape = love.physics.newRectangleShape(WALL_THICKNESS, h)
	rightWall.body = love.physics.newBody(world, w - WALL_THICKNESS / 2, h / 2)
	rightWall.fixture = love.physics.newFixture(rightWall.body, rightWall.shape)
	rightWall.fixture:setRestitution(1)

	floor = {}
	floor.shape = love.physics.newRectangleShape(w - 2 * WALL_THICKNESS, WALL_THICKNESS)
	floor.body = love.physics.newBody(world, w / 2, h - WALL_THICKNESS / 2)
	floor.fixture = love.physics.newFixture(floor.body, floor.shape)
	floor.fixture:setRestitution(1)

	ceiling = {}
	ceiling.shape = love.physics.newRectangleShape(w - 2 * WALL_THICKNESS, WALL_THICKNESS)
	ceiling.body = love.physics.newBody(world, w / 2, WALL_THICKNESS / 2)
	ceiling.fixture = love.physics.newFixture(ceiling.body, ceiling.shape)
	ceiling.fixture:setRestitution(1)

	bot = {}
	bot.shape = love.physics.newCircleShape(10)
	bot.body = love.physics.newBody(world, w / 2, 100, "dynamic")
	bot.fixture = love.physics.newFixture(bot.body, bot.shape)
	bot.fixture:setRestitution(0.9)

	anchor = {}
	anchor.body = love.physics.newBody(world, 0, 0, "static")
end

function love.draw()
	love.graphics.setColor(255, 255, 255, 255)
	drawWorldBox(floor)
	drawWorldBox(leftWall)
	drawWorldBox(rightWall)
	drawWorldBox(ceiling)

	for i = 1, #targets do
		local target = targets[i]
		local targetBumpAmount = 1 - math.max(math.min((elapsedTime - target.lastTouchTime) / TARGET_FADE_TIME, 1), 0)
		love.graphics.setColor(40, 190 + 60 * targetBumpAmount, 0, 100 + 100 * targetBumpAmount)
		love.graphics.circle("fill", target.body:getX(), target.body:getY(), TARGET_SIZE)
	end

	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.circle("line", bot.body:getX(), bot.body:getY(), bot.shape:getRadius(), 20)
	if anchor.joint then
		love.graphics.circle("line", anchor.body:getX(), anchor.body:getY(), 4, 20)
		love.graphics.line(anchor.body:getX(), anchor.body:getY(), bot.body:getX(), bot.body:getY())
	end
end

function makeTarget(x, y)
	target = {}
	target.shape = love.physics.newCircleShape(TARGET_SIZE)
	target.body = love.physics.newBody(world, x, y, "static")
	target.fixture = love.physics.newFixture(target.body, target.shape)
	target.fixture:setSensor(true)
	target.lastTouchTime = -TARGET_FADE_TIME -- since the main timeline starts at 0, even if a target spawns right after we start, it shouldn’t show any fading
	targets[#targets + 1] = target
end

function clearTargets()
	print("clearing")
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
	local botX, botY = bot.body:getX(), bot.body:getY()
	anchor.joint = love.physics.newDistanceJoint(anchor.body, bot.body, x, y, botX, botY)

	-- apply force in the current direction of movement but orthogonal to the joint
	local toBot = vNorm(vSub(v(botX, botY), v(x, y)))
	local velX, velY = bot.body:getLinearVelocity()
	local botDirection = vNorm(v(velX, velY))
	local impulse = vNorm(vSub(botDirection, vMul(toBot, vDot(botDirection, toBot))), 100)
	bot.body:applyLinearImpulse(impulse.x, impulse.y)
end

function drawWorldBox(thing)
	love.graphics.polygon("fill", thing.body:getWorldPoints(thing.shape:getPoints()))
end

function love.update(dt)
	if started then
		-- TODO: if we go into slow motion, just multiply this dt value in advance before using it below
		elapsedTime = elapsedTime + dt
		world:update(dt)
	end
end

function love.mousepressed(x, y, button)
	makeAnchor(x,y)
end

function love.mousereleased(x, y, button)
	breakAnchor()
end

function randomTargetPosition(w, h)
	return v((0.2 + math.random() * 0.6) * w, (0.2 + math.random() * 0.6) * h)
end

function chooseNewTargetPosition()
	local w, h = love.window.getDimensions()
	local i = 0
	local foundPosition = nil
	while i < 10 and not foundPosition do
		local p = randomTargetPosition(w, h)
		local intersects = false
		if #targets > 0 then
			for j = 1, #targets do
				if vDist(v(targets[j].body:getX(), targets[j].body:getY()), p) < TARGET_SIZE * 3 then
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

function love.keyreleased(key)
	started = true
	clearTargets()
	
	for i = 1, 4 do
		local p = chooseNewTargetPosition()
		if p then
			makeTarget(p.x, p.y)
		end
	end
end