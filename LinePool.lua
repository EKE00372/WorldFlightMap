---- LINE POOL ----
-- copy/pasta of TexturePoolMixin, just for lines
local LinePoolMixin = {}

local function LinePoolFactory(linePool)
    return linePool.parent:CreateLine(nil, linePool.layer, linePool.textureTemplate, linePool.subLayer)
end

function LinePoolMixin:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc)
    Mixin(self, CreateUnsecuredObjectPool(LinePoolFactory, resetterFunc))
    Mixin(self, CreateUnsecuredTexturePool(parent, layer, subLayer, textureTemplate, resetterFunc))
    self:Init(LinePoolFactory, resetterFunc)
    self.parent = parent
    self.layer = layer
    self.subLayer = subLayer
    self.textureTemplate = textureTemplate
end

function CreateLinePool(parent, layer, subLayer, textureTemplate, resetterFunc)
    local linePool = CreateFromMixins(LinePoolMixin)
    linePool:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc or Pool_HideAndClearAnchors)
    return linePool
end
