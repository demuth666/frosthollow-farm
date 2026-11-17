# FrostHollow [Floor 1] — Auto Farm Hub

Script auto farm untuk **FrostHollow RPG [Floor 1]** dengan UI **WindUI**.

## Load

**Recommended — selalu versi terbaru** (ambil commit terakhir, anti-cache):

```lua
local repo, file = "demuth666/frosthollow-farm", "frosthollow_farm.luau"
local url = "https://raw.githubusercontent.com/" .. repo .. "/main/" .. file
local ok, body = pcall(function() return game:HttpGet("https://api.github.com/repos/" .. repo .. "/commits/main") end)
if ok and type(body) == "string" then
    local sha = body:match('"sha"%s*:%s*"(.-)"')
    if sha then url = "https://raw.githubusercontent.com/" .. repo .. "/" .. sha .. "/" .. file end
end
loadstring(game:HttpGet(url))()
```

Versi pendek (bisa telat beberapa menit setelah update karena cache GitHub):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/frosthollow-farm/main/frosthollow_farm.luau"))()
```

CDN alternatif:

```lua
loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/demuth666/frosthollow-farm@main/frosthollow_farm.luau"))()
```

## Fitur

| Tab | Fitur |
|---|---|
| **Farm** | Auto Farm (teleport + serang), Kill Aura, Auto Loot, Auto Revive, Auto Mine (butuh Pickaxe), **filter Target Mob** (pilih jenis mob: Slime, Wolf, Golem, dll), prioritas target, filter level min/max, jeda pukulan, auto kabur saat HP rendah, teleport ke mob terdekat |
| **Farm → Defense** | **Auto Parry** (latency auto-calibration + belajar timing per mob/serangan), **Auto Dash (Q)** — dodge pakai dash asli game, **Boss Safe Mode** (berhenti mukul saat impact boss dekat), kabur dari boss kalau HP rendah, serang boss dari belakang |
| **Teleport** | 8 waypoint (Town, Harbor, Temple, Mine, Highlands, Summit, Forest, MineLake), Quest Target, Crystal terdekat, Loot terdekat |
| **Movement** | Speed Hack, Jump Boost, Fly, Noclip, Infinite Jump, Anti-AFK |
| **Visuals** | ESP Mobs (nama/Lv/HP/jarak), ESP Loot, ESP Crystal, ESP Players, jarak maksimal |
| **Misc** | Allocate semua StatPoints, Auto Allocate, Revive manual, teleport ke Town |

## Cara pakai

1. Join FrostHollow, inject executor.
2. Jalankan loader di atas.
3. Buka menu: **RightShift** (PC) atau tombol melayang **FrostHollow** (mobile).
4. Nyalakan **Auto Farm**. Atur **Level Maksimum** (0 = level kamu + 2).
5. **Target Mob**: pilih satu/lebih jenis mob yang mau dibunuh (Slime, Wolf, Golem, Bandit, dll). Kosongkan = semua jenis.
6. **Auto Parry** dan **Auto Loot** sudah aktif secara default.

### Daftar mob

Slime, King Slime, Shard Slime, Wolf, King Wolf, Polar Bear, King Polar Bear, Golem, King Golem, Spider, King Spider, Egg Guardian Spider, Goblin, Goblin Chief, Bandit, Bandit Chief, Skeleton Miner.

Jika ada mob baru, tekan **Refresh Daftar Mob** di tab Farm → Target.

## Catatan mobile

- Menu dibuka lewat tombol melayang, bukan tombol keyboard.
- Auto Farm, Parry, Loot, Teleport, Revive, Speed, Jump, Noclip, Infinite Jump berjalan di HP.
- Fly di HP: geser joystick, arahkan kamera ke atas/bawah untuk naik-turun.
- ESP memerlukan executor yang mendukung `Drawing`; kalau tidak ada, ESP otomatis di-skip.
- Di HP jangan pasang jarak ESP terlalu jauh (150–250 sudah cukup).

## Teknis

- Damage tetap dihitung server: script memanggil `Tool:Activate()` saat menempel di mob.
- **Auto Parry**: saat block dimulai, server menulis `ParryWindowEnd`; script memakai selisihnya untuk mengukur latency remote (~0.1s) dan menaruh block tepat di tengah parry window (0.17s). Timing impact dipelajari per `mob|serangan`, jadi mob baru butuh 1-2 hit untuk akurat.
- **Auto Dash**: mengirim key `Q` lewat VirtualInputManager — memakai dash asli game (stamina 8, cooldown 1.2s). Arah dash menjauh dari penyerang + sedikit menyamping.
- **Boss**: posisi di belakang boss, block ditahan melewati impact (mitigasi kalau window parry meleset), dan dash dipakai saat HP di bawah batas / lawan boss. Parry boss lebih sulit karena windup-nya panjang dan bervariasi — dash + block yang bikin selamat.
- Loot diambil lewat `ProximityPrompt:InputHoldBegin()`.
- Revive lewat `RequestRespawn`.

## Peringatan

Gunakan dengan wajar. Speed tinggi, fly, dan teleport bisa terlihat mencurigakan. Risiko ban / kick ditanggung pengguna. Script ini untuk keperluan pribadi di game single-player RPG.

## Credits

- UI: [WindUI](https://github.com/Footagesus/WindUI) oleh Footagesus
- Game: FrostHollow RPG
