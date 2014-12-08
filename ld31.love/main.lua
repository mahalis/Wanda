require "vectors"

local world

local leftWall, rightWall, floor, bot, anchor

local targets = {}

local elapsedTime = 0
local titleStartTime = 0
local playing = false
local gameOver = false
local gameOverTime = 0

WALL_THICKNESS = 20
TARGET_SIZE = 20
TARGET_DIE_TIME = 0.4
NEW_TARGET_MIN_DISTANCE_FROM_PLAYER = 2 * TARGET_SIZE
TARGET_GROW_TIME = 0.2
SCORE_BLINK_TIME = 0.3
TITLE_TIME = 4 -- duration of title rise/fade animation

local score = 0
local lastScore = 0
local scoreChangedTime = -1
local streak = 0
local streakChangedTime = -1
local lastStreak = 0
local longestStreak = 0
local hitTargetWithLastAnchor = false

local backgroundImage, wandaImage
local ringImages = {}

local scoreBigFont, scoreLittleFont

local titleImages = {}
local endScoreImage, endStreakImage, endImageIndex
local endImages = {}

local dingSound, successSound

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
				hitTargetWithLastAnchor = true
				setStreak(streak + 1)

				target.lastTouchTime = elapsedTime -- we’ll remove it in update() later — not safe to do that in physics callback

				-- success sound
				successSound:rewind()
				successSound:play()

				return
			end
		end

		if fixture1 == floor.fixture or fixture2 == floor.fixture then
			gameOver = true
			playing = false
			endImageIndex = 1 + math.floor(math.random() * 9)
			gameOverTime = elapsedTime

			return
		end

		-- play a sound for anything else that’s not the ceiling, i.e. pretty much just the walls
		if fixture1 ~= ceiling.fixture and fixture2 ~= ceiling.fixture then
			dingSound:play()
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
	math.randomseed(os.time())

	-- images

	backgroundImage = love.graphics.newImage("graphics/background.jpg")
	wandaImage = love.graphics.newImage("graphics/wanda.png")
	for i = 1, 3 do
		ringImages[i] = love.graphics.newImage("graphics/ring" .. tostring(i) .. ".png")
	end

	local titleImageNames = {"title", "story row 1", "story row 2", "story row 3", "instructions"}
	for i = 1, #titleImageNames do
		titleImages[i] = love.graphics.newImage("graphics/" .. titleImageNames[i] .. ".png")
	end

	endScoreImage = love.graphics.newImage("graphics/final score.png")
	endStreakImage = love.graphics.newImage("graphics/longest streak.png")
	for i = 1, 9 do
		endImages[i] = love.graphics.newImage("graphics/end/end " .. tostring(i) .. ".png")
	end

	-- sounds
	dingSound = love.audio.newSource("sounds/ding.wav", "static")
	dingSound:setPitch(0.5)
	dingSound:setVolume(0.6)
	successSound = love.audio.newSource("sounds/chord.wav", "static")
	successSound:setVolume(0.4)

	-- fonts

	scoreBigFont = love.graphics.newFont(30)
	scoreLittleFont = love.graphics.newFont(20)

	-- physics

	local w, h = love.window.getDimensions()
	world = love.physics.newWorld(0, 400) -- second parameter is Y gravity
	world:setCallbacks(contactBegan, nil, nil, nil)

	leftWall = {}
	leftWall.shape = love.physics.newRectangleShape(WALL_THICKNESS, h * 1.5)
	leftWall.body = love.physics.newBody(world, 0, h / 2)
	leftWall.fixture = love.physics.newFixture(leftWall.body, leftWall.shape)
	leftWall.fixture:setRestitution(1)

	rightWall = {}
	rightWall.shape = love.physics.newRectangleShape(WALL_THICKNESS, h * 1.5)
	rightWall.body = love.physics.newBody(world, w, h / 2)
	rightWall.fixture = love.physics.newFixture(rightWall.body, rightWall.shape)
	rightWall.fixture:setRestitution(1)

	floor = {}
	floor.shape = love.physics.newRectangleShape(w - 2 * WALL_THICKNESS, WALL_THICKNESS)
	floor.body = love.physics.newBody(world, w / 2, h * 1.25)
	floor.fixture = love.physics.newFixture(floor.body, floor.shape)
	floor.fixture:setRestitution(0)

	ceiling = {}
	ceiling.shape = love.physics.newRectangleShape(w - 2 * WALL_THICKNESS, WALL_THICKNESS)
	ceiling.body = love.physics.newBody(world, w / 2, -h * .25)
	ceiling.fixture = love.physics.newFixture(ceiling.body, ceiling.shape)
	ceiling.fixture:setRestitution(1)

	bot = {}
	bot.shape = love.physics.newCircleShape(30)
	bot.body = love.physics.newBody(world, 0, 0, "dynamic") -- 0,0 for now — reset() is responsible for the actual starting position
	bot.fixture = love.physics.newFixture(bot.body, bot.shape)
	bot.fixture:setRestitution(0.9)

	anchor = {}
	anchor.body = love.physics.newBody(world, 0, 0, "static")

	-- get gameplay stuff ready

	reset()
end

-- yes the naming is silly; this doesn't have anything to do with colors. whatever, I don’t feel like typing mixThreeNumberTables
function mixColors(a, b, f)
	return {a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), a[3] + f * (b[3] - a[3])}
end

-- mix two values along the curve used for title stuff
function titleInterpolate(a, b, f)
	f = math.max(0, math.min(1, f))
	return a + (b - a) * (1 - math.pow(1 - f, 5))
end

function love.draw()
	love.graphics.setColor(255, 255, 255, 255)
	local w, h = love.window.getDimensions()
	
	love.graphics.draw(backgroundImage, 0, 0)

	local baseColor = {60, 80, 100} -- used below by the end-game stuff (to draw score numbers) and the score stuff (guess)

	if playing then
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
	else
		-- either title screen or end-game state
		-- TODO: make these drift up / fade in
		if not gameOver then
			-- title screen
			local titleImageYs = {158, 228, 300, 372, 480}
			local titleDelays = {2, 3, 3, 2, 0}
			local accumulatedDelay = 0
			for i = 1, #titleImages do
				local time = (elapsedTime - accumulatedDelay - titleStartTime) / TITLE_TIME
				accumulatedDelay = accumulatedDelay + titleDelays[i]
				love.graphics.setColor(255, 255, 255, titleInterpolate(0, 255, time))
				local yOffset = titleInterpolate(40, 0, time) -- one second for now, may change it
				local image = titleImages[i]
				local imageW, imageH = image:getDimensions()
				love.graphics.draw(image, w / 2, titleImageYs[i] + yOffset, 0, 1, 1, imageW / 2, 0)
			end
		else
			local time = (elapsedTime - gameOverTime) / TITLE_TIME
			love.graphics.setColor(255, 255, 255, titleInterpolate(0, 255, time))
			-- game over
			local endImage = endImages[endImageIndex]
			local imageW, imageH = endImage:getDimensions()
			love.graphics.draw(endImage, w / 2, 230, 0, 1, 1, imageW / 2, 0)
			imageW, imageH = endScoreImage:getDimensions()
			love.graphics.draw(endScoreImage, w / 2, 370, 0, 1, 1, imageW / 2, 0)
			imageW, imageH = endStreakImage:getDimensions()
			love.graphics.draw(endStreakImage, w / 2, 450, 0, 1, 1, imageW / 2, 0)
			love.graphics.setColor(baseColor[1], baseColor[2], baseColor[3], titleInterpolate(0, 255, time))
			love.graphics.setFont(scoreBigFont)
			love.graphics.printf(tostring(score), w / 2 - 30, 390, 60, "center")
			love.graphics.printf(tostring(streak), w / 2 - 30, 468, 60, "center")
		end
	end

	love.graphics.setColor(255, 255, 255, 255)
	local wandaW, wandaH = wandaImage:getDimensions()
	love.graphics.draw(wandaImage, bot.body:getX(), bot.body:getY(), bot.body:getAngle(), 1, 1, wandaW / 2, wandaH / 2)

	-- score

	if playing then
		local goodColor = {20, 140, 60}
		local badColor = {150, 70, 30}
		local scoreColor = baseColor
		local streakColor = baseColor
		if scoreChangedTime > -1 then
			scoreColor = mixColors((score > lastScore and goodColor or badColor), baseColor, math.min(1, math.max(0, (elapsedTime - scoreChangedTime) / SCORE_BLINK_TIME)))
		end
		if streakChangedTime > -1 then
			streakColor = mixColors((streak > lastStreak and goodColor or badColor), baseColor, math.min(1, math.max(0, (elapsedTime - streakChangedTime) / SCORE_BLINK_TIME)))
		end
		love.graphics.setFont(scoreBigFont)
		love.graphics.setColor(scoreColor[1], scoreColor[2], scoreColor[3], 255)
		love.graphics.printf(string.format("%03d", score), 18, h - 48, 60, "left")
		love.graphics.setColor(streakColor[1], streakColor[2], streakColor[3], 255)
		love.graphics.printf(string.format("%02d", streak), w - 48, h - 48, 30, "right")
		love.graphics.setFont(scoreLittleFont)
		love.graphics.setColor(scoreColor[1], scoreColor[2], scoreColor[3], 128)
		love.graphics.printf("score", 80, h - 38, 60, "left")
		love.graphics.setColor(streakColor[1], streakColor[2], streakColor[3], 128)
		love.graphics.printf("streak", w - 122, h - 38, 60, "right")
	end
end

function adjustScore(value)
	lastScore = score
	score = math.max(0, score + value)
	if score ~= lastScore then
		scoreChangedTime = elapsedTime
	end
end

function setStreak(value)
	lastStreak = streak
	streak = value
	if streak ~= lastStreak then
		streakChangedTime = elapsedTime
	end
	if streak > longestStreak then
		longestStreak = streak
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

	if not hitTargetWithLastAnchor then
		setStreak(0)
	end
	hitTargetWithLastAnchor = false
end

function love.update(dt)
	-- TODO: if we go into slow motion, just multiply this dt value in advance before using it below
	elapsedTime = elapsedTime + dt

	if playing then
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
	score = 0
	streak = 0
	longestStreak = 0

	local w, h = love.window.getDimensions()
	bot.body:setPosition(w / 2, h * 0.2)
	bot.body:setAngle(0)
	bot.body:setAngularVelocity(0)
	bot.body:setLinearVelocity(0, 0)
	playing = false
	gameOver = false
	titleStartTime = elapsedTime
end

function start()
	for i = 1, 3 do
		local p = chooseNewTargetPosition()
		if p then
			targets[#targets + 1] = makeTarget(p.x, p.y)
		end
	end
	playing = true
end

function love.mousepressed(x, y, button)
	if not playing then
		if gameOver then
			reset()
		else
			start()
		end
	else
		makeAnchor(x,y)
	end
end

function love.mousereleased(x, y, button)
	breakAnchor()
end

function randomTargetPosition(w, h)
	return v((0.1 + math.random() * 0.8) * w, (0.1 + math.random() * 0.7) * h)
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
