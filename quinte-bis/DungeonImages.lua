local addonName, Q = ...
-- Illustrations Blizzard, sources et SHA-256 : Media/Dungeons/sources.json.
local images = {
 RFC = "RagefireChasm",
 WC = "WailingCaverns",
 DM = "Deadmines",
 SFK = "ShadowFangKeep",
 STOCKS = "TheStockade",
 BFD = "BlackfathomDeeps",
 GNOMER = "Gnomeregan",
 RFK = "RazorfenKraul",
 RFD = "RazorfenDowns",
 ULDA = "Uldaman",
 ZF = "ZulFarrak",
 MARA = "Maraudon",
 ST = "SunkenTemple",
 BRD = "BlackrockDepths",
 LBRS = "BlackrockSpire",
 UBRS = "BlackrockSpire",
 STRAT = "Stratholme",
 SCHOLO = "Scholomance",
 ONY = "Onyxia",
 MC = "MoltenCore",
 BWL = "BlackwingLair",
 ZG = "ZulGurub",
 AQ20 = "RuinsofAhnQiraj",
 AQ40 = "TempleofAhnQiraj",
 NAXX = "Naxxramas",
 SM_GY = "ScarletMonastery",
 SM_LIB = "ScarletMonastery",
 SM_ARM = "ScarletMonastery",
 SM_CATH = "ScarletMonastery",
 DME = "DireMaul",
 DMW = "DireMaul",
 DMN = "DireMaul",
}
function Q.DungeonImage(code)
 return "Interface\\AddOns\\" .. addonName .. "\\Media\\Dungeons\\" .. (images[code] or "Default") .. ".tga"
end
