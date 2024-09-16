---- LINE POOL ----
-- copy/pasta of TexturePoolMixin, just for lines

local LinePoolMixin = CreateFromMixins(ObjectPoolMixin)
local function LinePoolFactory(linePool)
	return linePool.parent:CreateLine(nil, linePool.layer, linePool.textureTemplate, linePool.subLayer)
end

function LinePoolMixin:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc)
	ObjectPoolMixin.OnLoad(self, LinePoolFactory, resetterFunc)
	self.parent = parent
	self.layer = layer
	self.subLayer = subLayer
	self.textureTemplate = textureTemplate
end

--[[ global ]]
local function LinePoolFactory(linePool)
    return linePool.parent:CreateLine(nil, linePool.layer, linePool.textureTemplate, linePool.subLayer)
end

function CreateLinePool(parent, layer, subLayer, textureTemplate, resetterFunc)
    local linePool = CreateSecureObjectPool(LinePoolFactory)
    linePool.parent = parent
    linePool.layer = layer
    linePool.subLayer = subLayer
    linePool.textureTemplate = textureTemplate
    return linePool
end