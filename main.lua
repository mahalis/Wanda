require "vectors"

local world

local leftWall, rightWall, floor, bot, anchor

WALL_THICKNESS = 20

-- need to keep track of fixtures for world callback collisions

local function contactBegan(fixture1, fixture2, contact)

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
	--drawWorldBox(floor)
	--drawWorldBox(leftWall)
	--drawWorldBox(rightWall)

	love.graphics.circle("line", bot.body:getX(), bot.body:getY(), bot.shape:getRadius(), 20)
	love.graphics.circle("line", anchor.body:getX(), anchor.body:getY(), 4, 20)
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
	anchor.joint = love.physics.newDistanceJoint(anchor.body, bot.body, x, y, bot.body:getX(), bot.body:getY())
end

function drawWorldBox(thing)
	love.graphics.polygon("line", thing.body:getWorldPoints(thing.shape:getPoints()))
end

function love.update(dt)
	world:update(dt)
end

function love.mousereleased(x, y, button)
	makeAnchor(x,y)
end