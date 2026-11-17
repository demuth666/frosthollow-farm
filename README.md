# FrostHollow [Floor 1] — Auto Farm Hub

Script auto farm untuk **FrostHollow RPG [Floor 1]** dengan UI **WindUI**.

## Load

PC / mobile — tempel satu baris:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/demuth666/frosthollow-farm/main/frosthollow_farm.luau"))()
```

Alternatif CDN (lebih cepat / kalau raw diblokir):

```lua
loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/demuth666/frosthollow-farm@main/frosthollow_farm.luau"))()
```

## Fitur

| Tab | Fitur |
|---|---|
| **Farm** | Auto Farm (teleport + serang), Kill Aura, Auto Loot, Auto Revive, Auto Mine (butuh Pickaxe), prioritas target, filter level min/max, jeda pukulan, auto kabur saat HP rendah, teleport ke mob terdekat |
| **Farm → Defense** | **Auto Parry** — block tepat sebelum impact, belajar timing tiap jenis mob otomatis, slider lead/hold/jarak, reset timing |
| **Teleport** | 8 waypoint (Town, Harbor, Temple, Mine, Highlands, Summit, Forest, MineLake), Quest Target, Crystal terdekat, Loot terdekat |
| **Movement** | Speed Hack, Jump Boost, Fly, Noclip, Infinite Jump, Anti-AFK |
| **Visuals** | ESP Mobs (nama/Lv/HP/jarak), ESP Loot, ESP Crystal, ESP Players, jarak maksimal |
| **Misc** | Allocate semua StatPoints, Auto Allocate, Revive manual, teleport ke Town |

## Cara pakai

1. Join FrostHollow, inject executor.
2. Jalankan loader di atas.
3. Buka menu: **RightShift** (PC) atau tombol melayang **FrostHollow** (mobile).
4. Nyalakan **Auto Farm**. Atur **Level Maksimum** (0 = level kamu + 2).
5. **Auto Parry** dan **Auto Loot** sudah aktif secara default.

## Catatan mobile

- Menu dibuka lewat tombol melayang, bukan tombol keyboard.
- Auto Farm, Parry, Loot, Teleport, Revive, Speed, Jump, Noclip, Infinite Jump berjalan di HP.
- Fly di HP: geser joystick, arahkan kamera ke atas/bawah untuk naik-turun.
- ESP memerlukan executor yang mendukung `Drawing`; kalau tidak ada, ESP otomatis di-skip.
- Di HP jangan pasang jarak ESP terlalu jauh (150–250 sudah cukup).

## Teknis

- Damage tetap dihitung server: script memanggil `Tool:Activate()` saat menempel di mob.
- Parry memakai `RequestBlockStart` / `RequestBlockEnd` + prediksi impact dari attribute `Action` / `ActionAt` mob.
- Loot diambil lewat `ProximityPrompt:InputHoldBegin()`.
- Revive lewat `RequestRespawn`.

## Peringatan

Gunakan dengan wajar. Speed tinggi, fly, dan teleport bisa terlihat mencurigakan. Risiko ban / kick ditanggung pengguna. Script ini untuk keperluan pribadi di game single-player RPG.

## Credits

- UI: [WindUI](https://github.com/Footagesus/WindUI) oleh Footagesus
- Game: FrostHollow RPG
