-- FrostHollow Auto Farm — loader (selalu ambil commit terbaru)
-- Tempel blok ini ke executor (PC / mobile).

local repo = "demuth666/frosthollow-farm"
local file = "frosthollow_farm.luau"
local url = "https://raw.githubusercontent.com/" .. repo .. "/main/" .. file

-- Ambil SHA commit terbaru supaya tidak kena cache CDN GitHub
local ok, body = pcall(function()
    return game:HttpGet("https://api.github.com/repos/" .. repo .. "/commits/main")
end)
if ok and type(body) == "string" then
    local sha = body:match('"sha"%s*:%s*"(.-)"')
    if sha then
        url = "https://raw.githubusercontent.com/" .. repo .. "/" .. sha .. "/" .. file
    end
end

loadstring(game:HttpGet(url))()

-- Versi pendek (tanpa cek versi, bisa telat beberapa menit setelah update):
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/frosthollow-farm/main/frosthollow_farm.luau"))()
