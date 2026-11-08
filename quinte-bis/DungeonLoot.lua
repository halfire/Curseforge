local _, Q = ...
-- Généré par scripts/make_loot_forever.py depuis Wowhead Forever (relevé du 08/11/2026) : butin des boss des
-- donjons, armes et armures vertes et mieux. { id, emplacement (suffixe INVTYPE_), nom anglais en secours } ; le jeu
-- affiche le nom français. « ancienne table » : boss sans butin sur Wowhead Forever pour l'instant, gardé de
-- l'ancien relevé (identifiants seulement). Ne pas modifier à la main : relancer le script.
Q.DUNGEON_LOOT = {
    { key = 'RFC', bosses = {
        { name = 'Oggleflint', items = { { 272996, 'WEAPONMAINHAND', 'Trogg Scepter' }, { 272998, 'WEAPONMAINHAND', 'Bone Knuckles' }, { 272999, 'RANGED', 'Barbaric Crossbow' } } },
        { name = 'Taragaman the Hungerer', items = { { 14145, 'WEAPONMAINHAND', 'Cursed Felblade' }, { 14148, 'WRIST', 'Crystalline Cuffs' }, { 14149, 'CLOAK', 'Subterranean Cape' } } },
        { name = 'Jergosh the Invoker', items = { { 14147, 'WRIST', 'Cavedweller Bracers' }, { 14150, 'CHEST', 'Robe of Evocation' }, { 14151, 'WEAPON', 'Chanting Blade' } } },
        { name = 'Bazzalan', items = { { 273003, 'WEAPONMAINHAND', 'Searing Dagger' }, { 273005, 'CLOAK', 'Satyrskin Cloak' }, { 273007, 'FEET', 'Chasm Walkers' } } },
    } },
    { key = 'THANES', bosses = {
        { name = 'Faldrim Anvilmar', items = { { 270227, 'NECK', 'Ephemeral Choker' }, { 271096, 'WRIST', 'Aetherwisp Bracers' }, { 271097, 'CLOAK', 'Spiritwraith Drape' } } },
        { name = 'Magmatus', items = { { 270230, 'WAIST', 'Kindlegem Girdle' }, { 270231, 'HAND', 'Flamefist Grips' }, { 271095, 'WEAPONMAINHAND', 'Fang of Magmatus' } } },
        { name = 'Plunder', items = { { 270228, '2HWEAPON', 'Golemheart Stave' }, { 270229, 'FEET', 'Treads of the Protector Golem' }, { 271098, 'CHEST', 'Golemguard Chest' } } },
        { name = 'Durgen Dirgehammer', items = { { 270256, 'WEAPONMAINHAND', 'Durgen\'s Crescent Axe' }, { 270260, 'LEGS', 'Direhammer Leggings' }, { 270261, 'CHEST', 'Robes of the Disgraced Thane' } } },
    } },
    { key = 'LORDAERON', bosses = {
        { name = 'Witherfang', items = { { 271201, 'WAIST', 'Atrophic Girdle' }, { 271202, 'WRIST', 'Witherbite Bracers' }, { 271203, '2HWEAPON', 'Segmented Spider Leg' } } },
        { name = 'The Baron', items = { { 271204, 'WEAPON', 'Meathook Slicer' }, { 271205, 'CHEST', 'Abomination Bones' }, { 271206, 'CHEST', 'Leftover Abomination Skin' } } },
        { name = 'Viktor the Vile', items = { { 271211, 'FEET', 'Vilewalkers' }, { 271212, 'CHEST', 'Bloodied Chestwraps' }, { 271218, 'WEAPON', 'Vileblood Scimitar' } } },
        { name = 'The Abandoned', items = { { 271207, 'LEGS', 'Rotmender\'s Leggings' }, { 271208, 'HAND', 'Grip of Fear' }, { 271216, 'WEAPONMAINHAND', 'Scepter of the Abandoned' } } },
        { name = 'Bjork', items = { { 271209, 'LEGS', 'Bonerust Leggings' }, { 271210, 'WAIST', 'Tuskwrap Belt' }, { 271217, '2HWEAPON', 'Corpse Chopper' } } },
        { name = 'Rath\'mael', items = { { 271213, 'SHIELD', 'Mirror of Rath\'mael' }, { 271214, 'FEET', 'Rotmender\'s Treads' }, { 271215, '2HWEAPON', 'Coldspire Staff' } } },
        { name = 'Lordaeron Captain', items = { { 6641, '2HWEAPON', 'Haunting Blade' }, { 6642, 'CHEST', 'Phantom Armor' } } },
    } },
    { key = 'WC', bosses = {
        { name = 'Lady Anacondra', items = { { 5404, 'SHOULDER', 'Serpent\'s Shoulders' }, { 10412, 'WAIST', 'Belt of the Fang' }, { 273088, 'NECK', 'Snake Eye Kaleidoscope' } } },
        { name = 'Lord Cobrahn', items = { { 6460, 'WAIST', 'Cobrahn\'s Grasp' }, { 6465, 'CHEST', 'Robe of the Moccasin' }, { 10410, 'LEGS', 'Leggings of the Fang' } } },
        { name = 'Kresh', items = { { 6447, 'SHIELD', 'Worn Turtle Shell Shield' }, { 13245, 'SHIELD', 'Kresh\'s Back' }, { 273084, 'CLOAK', 'Cloak of Hermitic Bliss' } } },
        { name = 'Lord Pythas', items = { { 6472, 'WEAPON', 'Stinging Viper' }, { 6473, 'CHEST', 'Armor of the Fang' }, { 273089, 'WAIST', 'Slither Cord' } } },
        { name = 'Skum', items = { { 6448, 'WEAPON', 'Tail Spike' }, { 6449, 'CLOAK', 'Glowing Lizardscale Cloak' }, { 273137, 'HOLDABLE', 'Skum\'s Bucket' } } },
        { name = 'Lord Serpentis', items = { { 5970, 'HAND', 'Serpent Gloves' }, { 6459, 'FEET', 'Savage Trodders' }, { 6469, 'RANGED', 'Venomstrike' }, { 10411, 'FEET', 'Footpads of the Fang' } } },
        { name = 'Verdan the Everliving', items = { { 6629, 'CLOAK', 'Sporid Cape' }, { 6630, 'SHIELD', 'Seedcloud Buckler' }, { 6631, '2HWEAPON', 'Living Root' } } },
        { name = 'Mutanus the Devourer', items = { { 6461, 'SHOULDER', 'Slime-encrusted Pads' }, { 6463, 'FINGER', 'Deep Fathom Ring' }, { 6627, 'CHEST', 'Mutant Scale Breastplate' } } },
        { name = 'Deviate Faerie Dragon', items = { { 5243, 'RANGED', 'Firebelcher' }, { 6632, 'CLOAK', 'Feyscale Cloak' } } },
        { name = 'Trash (butin de zone)', items = { { 10413 }, { 12989 }, { 14723 } } }, -- ancienne table
    } },
    { key = 'DM', bosses = {
        { name = 'Rhahk\'Zor', items = { { 872, '2HWEAPON', 'Rockslicer' }, { 5187, '2HWEAPON', 'Rhahk\'Zor\'s Hammer' }, { 273289, 'LEGS', 'Ogre Loincloth' } } },
        { name = 'Sneed\'s Shredder', items = { { 1937, 'WEAPON', 'Buzz Saw' }, { 2169, 'WEAPONMAINHAND', 'Buzzer Blade' }, { 285292, 'THROWN', 'Dull Sawblade' } } },
        { name = 'Sneed', items = { { 5194, '2HWEAPON', 'Taskmaster Axe' }, { 5195, 'HAND', 'Gold-flecked Gloves' }, { 273293, 'WRIST', 'Bandsaw Wristbands' } } },
        { name = 'Gilnid', items = { { 1156, 'FINGER', 'Lavishly Jeweled Ring' }, { 5199, 'LEGS', 'Smelting Pants' }, { 273297, 'WEAPONMAINHAND', 'Goblin Hammer' } } },
        { name = 'Mr. Smite', items = { { 5192, 'WEAPON', 'Thief\'s Blade' }, { 5196, 'WEAPON', 'Smite\'s Reaver' }, { 7230, '2HWEAPON', 'Smite\'s Mighty Hammer' }, { 284715, 'FINGER', 'First Mate Band' } } },
        { name = 'Captain Greenskin', items = { { 5200, '2HWEAPON', 'Impaling Harpoon' }, { 5201, '2HWEAPON', 'Emberstone Staff' }, { 10403, 'WAIST', 'Blackened Defias Belt' } } },
        { name = 'Edwin VanCleef', items = { { 5191, 'WEAPON', 'Cruel Barb' }, { 5193, 'CLOAK', 'Cape of the Brotherhood' }, { 5202, 'CHEST', 'Corsair\'s Overshirt' }, { 10399, 'CHEST', 'Blackened Defias Armor' } } },
        { name = 'Cookie', items = { { 5197, 'WEAPON', 'Cookie\'s Tenderizer' }, { 5198, 'RANGED', 'Cookie\'s Stirring Rod' }, { 273298, 'TRINKET', 'Lookie\'s Spyglass' } } },
        { name = 'Miner Johnson', items = { { 5443, 'SHIELD', 'Gold-plated Buckler' }, { 5444, 'CLOAK', 'Miner\'s Cape' } } },
        { name = 'Trash (butin de zone)', items = { { 1945 }, { 1943 }, { 1951 }, { 1929 }, { 1936 }, { 1934 }, { 1944 }, { 10400 }, { 10401 }, { 10402 }, { 1930 } } }, -- ancienne table
    } },
    { key = 'SFK', bosses = {
        { name = 'Rethilgore', items = { { 5254, 'SHOULDER', 'Rugged Spaulders' }, { 273456, 'WEAPONMAINHAND', 'Cell Keeper\'s Claws' }, { 273457, 'NECK', 'Sorcerer Collar' } } },
        { name = 'Razorclaw the Butcher', items = { { 1292, 'WEAPON', 'Butcher\'s Cleaver' }, { 6226, 'CHEST', 'Bloody Apron' }, { 6633, 'WEAPON', 'Butcher\'s Slicer' } } },
        { name = 'Baron Silverlaine', items = { { 6321, 'FINGER', 'Silverlaine\'s Family Seal' }, { 6323, 'WEAPONMAINHAND', 'Baron\'s Scepter' }, { 273637, 'WEAPONMAINHAND', 'Blade of Silverlaine' } } },
        { name = 'Commander Springvale', items = { { 3191, '2HWEAPON', 'Arced War Axe' }, { 6320, 'SHIELD', 'Commander\'s Crest' }, { 273643, 'TRINKET', 'Worgenbane Talisman' } } },
        { name = 'Odo the Blindwatcher', items = { { 6318, '2HWEAPON', 'Odo\'s Ley Staff' }, { 6319, 'WAIST', 'Girdle of the Blindwatcher' }, { 273645, 'HEAD', 'Blindwatcher\'s Sight' } } },
        { name = 'Fenrus the Devourer', items = { { 3230, 'WRIST', 'Black Wolf Bracers' }, { 6340, 'CLOAK', 'Fenrus\' Hide' }, { 273646, 'FEET', 'Half-Eaten Boots' } } },
        { name = 'Wolf Master Nandos', items = { { 3748, 'SHOULDER', 'Feline Mantle' }, { 6314, 'CLOAK', 'Wolfmaster Cape' }, { 273647, 'LEGS', 'Worgpelt Leggings' } } },
        { name = 'Archmage Arugal', items = { { 6220, 'WEAPON', 'Meteor Shard' }, { 6324, 'CHEST', 'Robes of Arugal' }, { 6392, 'WAIST', 'Belt of Arugal' } } },
        { name = 'Deathsworn Captain', items = { { 6641, '2HWEAPON', 'Haunting Blade' }, { 6642, 'CHEST', 'Phantom Armor' } } },
        { name = 'Fel Steed', items = { { 6341, 'HOLDABLE', 'Eerie Stable Lantern' } } },
        { name = 'Sever', items = { { 23173 }, { 23171 } } }, -- ancienne table
        { name = 'Arugal\'s Voidwalker', items = { { 5943 } } }, -- ancienne table
        { name = 'Trash (butin de zone)', items = { { 6341 }, { 1318 }, { 1482 }, { 1483 }, { 1484 }, { 1489 }, { 1935 }, { 1974 }, { 2205 }, { 2292 }, { 2807 }, { 3194 } } }, -- ancienne table
    } },
    { key = 'EXCAV', bosses = {
        { name = 'Saltspine', items = { { 273022, 'LEGS', 'Supple Bellyskin Leggings' }, { 273023, 'WAIST', 'Saltscale Girdle' }, { 273024, 'FEET', 'Glinteye Slippers' } } },
        { name = 'Shadetooth', items = { { 273025, 'FEET', 'Raptorclaw Greaves' }, { 273026, 'CHEST', 'Garb of Florid Feathers' }, { 273027, 'HOLDABLE', 'Raptor\'s Gaze' } } },
        { name = 'Relic Guardian', items = { { 273028, 'SHOULDER', 'Reliquary Mantle' }, { 273029, 'RANGED', 'Golemsight Long Gun' }, { 273030, 'FINGER', 'Ring of Power Regulation' } } },
    } },
    { key = 'STOCKS', bosses = {
        { name = 'Targorr the Dread', items = { { 273804, 'SHOULDER', 'Executioner Mantle' }, { 273805, 'CHEST', 'Blackrock Harness' }, { 273806, 'FINGER', 'Dark Horde Band' } } },
        { name = 'Kam Deepfury', items = { { 2280, '2HWEAPON', 'Kam\'s Walking Stick' }, { 273807, 'WAIST', 'Demolition Girdle' }, { 273808, 'WRIST', 'Bridgebreaker Bindings' } } },
        { name = 'Hamhock', items = { { 273809, 'WEAPONMAINHAND', 'Hamhock\'s Cleaver' }, { 273810, 'HAND', 'Ogre Grips' }, { 273811, 'SHIELD', 'Repurposed Rack' } } },
        { name = 'Bazil Thredd', items = { { 273824, 'HAND', 'Defias Jailbreakers' }, { 273825, 'CLOAK', 'Red Wool Cloak' }, { 273827, 'WEAPONMAINHAND', 'Debt Collector' }, { 273829, 'RANGED', 'Concealed Hand Crossbow' } } },
        { name = 'Dextren Ward', items = { { 273817, '2HWEAPON', 'Graverobber\'s Shovel' }, { 273819, '2HWEAPON', 'Boneslicer' }, { 273820, 'FINGER', 'Nightskulker Ring' } } },
        { name = 'Bruegal Ironknuckle', items = { { 2941, 'WEAPON', 'Prison Shank' }, { 2942, 'WEAPON', 'Iron Knuckles' }, { 3228, 'WRIST', 'Jimmied Handcuffs' } } },
        { name = 'Trash (butin de zone)', items = { { 1076 }, { 274092 } } }, -- ancienne table
    } },
    { key = 'BFD', bosses = {
        { name = 'Ghamoo-ra', items = { { 6907, 'CHEST', 'Tortoise Armor' }, { 6908, 'WAIST', 'Ghamoo-ra\'s Bind' }, { 273839, 'FINGER', 'Spiked Shell Band' } } },
        { name = 'Lady Sarevess', items = { { 888, 'HAND', 'Naga Battle Gloves' }, { 3078, 'RANGED', 'Naga Heartpiercer' }, { 11121, 'WEAPONMAINHAND', 'Darkwater Talwar' } } },
        { name = 'Gelihast', items = { { 6905, '2HWEAPON', 'Reef Axe' }, { 6906, 'HAND', 'Algae Fists' }, { 273840, 'TRINKET', 'Cursed Murloc Eye' } } },
        { name = 'Lorgus Jett', items = { { 273841, '2HWEAPON', 'Twilight Maul' }, { 273842, 'FEET', 'Treacherous Treads' }, { 273843, 'RANGED', 'Fallenroot Longbow' } } },
        { name = 'Twilight Lord Kelris', items = { { 1155, '2HWEAPON', 'Rod of the Sleepwalker' }, { 6903, 'LEGS', 'Gaze Dreamer Pants' }, { 273846, 'WAIST', 'Twilight Lord Girdle' } } },
        { name = 'Old Serra\'kis', items = { { 6901, 'CLOAK', 'Glowing Thresher Cape' }, { 6902, 'WRIST', 'Bands of Serra\'kis' }, { 6904, 'WEAPON', 'Bite of Serra\'kis' } } },
        { name = 'Aku\'mai', items = { { 6909, '2HWEAPON', 'Strike of the Hydra' }, { 6910, 'LEGS', 'Leech Pants' }, { 6911, 'WAIST', 'Moss Cinch' } } },
        { name = 'Trash (butin de zone)', items = { { 2034 }, { 1454 }, { 1481 }, { 1486 }, { 1491 }, { 2271 }, { 2567 }, { 3413 }, { 3414 }, { 3415 }, { 3416 }, { 3417 } } }, -- ancienne table
    } },
    { key = 'SM_GY', bosses = {
        { name = 'Interrogator Vishas', items = { { 7682, 'WEAPON', 'Torturing Poker' }, { 7683, 'WEAPON', 'Bloody Brass Knuckles' }, { 274290, 'SHIELD', 'Painwalker Buckler' } } },
        { name = 'Bloodmage Thalnos', items = { { 7684, 'SHOULDER', 'Bloodmage Mantle' }, { 7685, 'HOLDABLE', 'Orb of the Forgotten Seer' }, { 274291, 'HEAD', 'Polished Skullcap' } } },
        { name = 'Azshir the Sleepless', items = { { 7708, 'RANGED', 'Necrotic Wand' }, { 7709, 'LEGS', 'Blighted Leggings' }, { 7731, 'NECK', 'Ghostshard Talisman' } } },
        { name = 'Fallen Champion', items = { { 7689, '2HWEAPON', 'Morbid Dawn' }, { 7690, 'HAND', 'Ebon Vise' }, { 7691, 'HEAD', 'Embalmed Shroud' } } },
        { name = 'Ironspine', items = { { 7686, 'FINGER', 'Ironspine\'s Eye' }, { 7687, 'WEAPON', 'Ironspine\'s Fist' }, { 7688, 'CHEST', 'Ironspine\'s Ribcage' } } },
        { name = 'Scorn', items = { { 23169, 'NECK', 'Scorn\'s Icy Choker' } } },
        { name = 'Trash (butin de zone)', items = { { 10329 }, { 10333 }, { 10331 }, { 10328 }, { 1992 }, { 2262 }, { 5756 }, { 5819 }, { 7727 }, { 7728 }, { 7729 }, { 7730 }, { 7736 }, { 7752 }, { 7753 }, { 7754 }, { 7755 }, { 7757 }, { 7758 }, { 7759 }, { 7760 }, { 7761 }, { 7786 }, { 7787 }, { 8225 }, { 8226 }, { 10332 } } }, -- ancienne table
    } },
    { key = 'DALARAN', bosses = {
        { name = 'Atrexis the Grave Knight', items = { { 273032, 'FINGER', 'Bonebinder\'s Signet' }, { 273033, 'RANGED', 'Gravespike Repeater' }, { 273036, 'WRIST', 'Graveweave Bindings' } } },
        { name = 'Arcane Anomaly', items = { { 273031, 'FINGER', 'Runemender\'s Seal' }, { 273034, 'HAND', 'Ephemeral Grips' }, { 273035, 'CHEST', 'Mana-Warped Chain Shirt' } } },
        { name = 'Fel Ancient', items = { { 273037, '2HWEAPON', 'Felbough Arm' }, { 273038, 'CHEST', 'Garb of Fallen Felbark' }, { 273039, 'WAIST', 'Blightleaf Rope' } } },
        { name = 'Unstable Sentinel', items = { { 273046, '2HWEAPON', 'Guardian\'s Dualblade' }, { 273047, 'SHOULDER', 'Unstable Crystalline Shoulderpads' }, { 273048, 'LEGS', 'Refractory Scaleguards' } } },
        { name = 'Shade of the Archmage', items = { { 273049, 'NECK', 'Archmagister\'s Faceted Pendant' }, { 273051, 'SHOULDER', 'Violet Sorcerer\'s Mantle' }, { 273052, 'HOLDABLE', 'Ponderous Orb' } } },
        { name = 'Lyn the Ignored', items = { { 273053, 'WEAPONMAINHAND', 'Tendonscraper Dagger' }, { 273054, 'HAND', 'Cartilage Shapers' }, { 273055, 'SHIELD', 'Bonepile Gaze' } } },
        { name = 'Mana Devourer', items = { { 273040, '2HWEAPON', 'Spine of the Devourer' }, { 273041, 'WAIST', 'Slitherwrap Girdle' }, { 273042, 'FEET', 'Manascale Treads' } } },
        { name = 'Arcanic Enigma', items = { { 273043, 'RANGED', 'Wand of Mana Concentration' }, { 273044, 'CHEST', 'Violet Sorcerer\'s Robes' }, { 273045, 'CLOAK', 'Drape of Shifting Energy' } } },
    } },
    { key = 'GNOMER', bosses = {
        { name = 'Grubbis', items = { { 9445, 'HAND', 'Grubbis Paws' }, { 274042, 'WAIST', 'Skullduggery Belt' }, { 274043, 'SHIELD', 'Irradiated Shield' } } },
        { name = 'Viscous Fallout', items = { { 9452, '2HWEAPON', 'Hydrocane' }, { 9453, 'WEAPON', 'Toxic Revenger' }, { 9454, 'FEET', 'Acidic Walkers' } } },
        { name = 'Electrocutioner 6000', items = { { 9446, 'WEAPONMAINHAND', 'Electrocutioner Leg' }, { 9447, 'FINGER', 'Electrocutioner Lagnut' }, { 9448, 'WRIST', 'Spidertank Oilrag' } } },
        { name = 'Crowd Pummeler 9-60', items = { { 9450, 'FEET', 'Gnomebot Operating Boots' }, { 274068, 'NECK', 'Thermaplugg Medal of Honor' } } },
        { name = 'Mekgineer Thermaplugg', items = { { 9458, 'SHIELD', 'Thermaplugg\'s Central Core' }, { 9459, '2HWEAPON', 'Thermaplugg\'s Left Arm' }, { 9461, 'FINGER', 'Charged Gear' }, { 9492, 'HEAD', 'Electromagnetic Gigaflux Reactivator' } } },
        { name = 'Dark Iron Ambassador', items = { { 9455, 'WRIST', 'Emissary Cuffs' }, { 9456, 'RANGED', 'Glass Shooter' }, { 9457, 'WEAPONMAINHAND', 'Royal Diplomatic Scepter' } } },
        { name = 'Trash (butin de zone)', items = { { 9485 }, { 9486 }, { 9487 }, { 9488 }, { 9490 }, { 9491 }, { 9508 }, { 9509 }, { 9510 }, { 9489 }, { 10298 }, { 10299 } } }, -- ancienne table
    } },
    { key = 'RFK', bosses = {
        { name = 'Aggem Thorncurse', items = { { 6681, 'WEAPON', 'Thornspike' }, { 274158, '2HWEAPON', 'Death Prophet Spine' }, { 274159, 'HAND', 'Thorncursed Grips' } } },
        { name = 'Death Speaker Jargba', items = { { 2816, 'WEAPONMAINHAND', 'Death Speaker Scepter' }, { 6682, 'CHEST', 'Death Speaker Robes' }, { 6685, 'SHOULDER', 'Death Speaker Mantle' } } },
        { name = 'Overlord Ramtusk', items = { { 6686, 'HEAD', 'Tusken Helm' }, { 6687, '2HWEAPON', 'Corpsemaker' }, { 274161, 'LEGS', 'Quillord Mail Leggings' } } },
        { name = 'Agathelos the Raging', items = { { 6690, 'LEGS', 'Ferine Leggings' }, { 6691, 'WEAPONMAINHAND', 'Swinetusk Shank' }, { 274160, 'THROWN', 'Quilrager Throwing Axe' } } },
        { name = 'Charlga Razorflank', items = { { 6692, 'WEAPON', 'Pronged Reaver' }, { 6693, 'FINGER', 'Agamaggan\'s Clutch' }, { 6694, 'SHIELD', 'Heart of Agamaggan' } } },
        { name = 'Blind Hunter', items = { { 6695, 'NECK', 'Stygian Bone Amulet' }, { 6696, 'RANGED', 'Nightstalker Bow' }, { 6697, 'SHOULDER', 'Batwing Mantle' } } },
        { name = 'Earthcaller Halmgar', items = { { 6688, 'HEAD', 'Whisperwind Headdress' }, { 6689, '2HWEAPON', 'Wind Spirit Staff' } } },
        { name = 'Razorfen Spearhide', items = { { 6679, '2HWEAPON', 'Armor Piercer' } } },
        { name = 'Roogug', items = { { 274149, 'CLOAK', 'Thornweaver Drape' }, { 274152, 'TRINKET', 'Roogug\'s Severed Head' }, { 274155, 'HEAD', 'Geomancer Headdress' } } },
        { name = 'Trash (butin de zone)', items = { { 6679 }, { 3569 }, { 776 }, { 1488 }, { 1727 }, { 1975 }, { 1976 }, { 1978 }, { 2039 }, { 2264 }, { 2549 }, { 4438 } } }, -- ancienne table
    } },
    { key = 'SM_LIB', bosses = {
        { name = 'Houndmaster Loksey', items = { { 3456, 'TRINKET', 'Dog Whistle' }, { 7710, '2HWEAPON', 'Loksey\'s Training Stick' }, { 7756, 'HAND', 'Dog Training Gloves' }, { 274292, 'THROWN', 'Houndmaster Boomerang' } } },
        { name = 'Arcanist Doan', items = { { 7711, 'CHEST', 'Robe of Doan' }, { 7712, 'SHOULDER', 'Mantle of Doan' }, { 7713, '2HWEAPON', 'Illusionary Rod' }, { 7714, 'WEAPONMAINHAND', 'Hypnotic Blade' }, { 274293, 'RANGED', 'Spellsever Crossbow' }, { 274294, 'FEET', 'Library Walkers' } } },
        { name = 'Trash (butin de zone)', items = { { 10329 }, { 10333 }, { 10331 }, { 10328 }, { 1992 }, { 2262 }, { 5756 }, { 5819 }, { 7727 }, { 7728 }, { 7729 }, { 7730 }, { 7736 }, { 7752 }, { 7753 }, { 7754 }, { 7755 }, { 7757 }, { 7758 }, { 7759 }, { 7760 }, { 7761 }, { 7786 }, { 7787 }, { 8225 }, { 8226 }, { 10332 } } }, -- ancienne table
    } },
    { key = 'SM_ARM', bosses = {
        { name = 'Herod', items = { { 7717, '2HWEAPON', 'Ravager' }, { 7718, 'SHOULDER', 'Herod\'s Shoulder' }, { 7719, 'HEAD', 'Raging Berserker\'s Helm' } } },
        { name = 'Trash (butin de zone)', items = { { 10329 }, { 10333 }, { 10331 }, { 10328 }, { 1992 }, { 2262 }, { 5756 }, { 5819 }, { 7727 }, { 7728 }, { 7729 }, { 7730 }, { 7736 }, { 7752 }, { 7753 }, { 7754 }, { 7755 }, { 7757 }, { 7758 }, { 7759 }, { 7760 }, { 7761 }, { 7786 }, { 7787 }, { 8225 }, { 8226 }, { 10332 } } }, -- ancienne table
    } },
    { key = 'SM_CATH', bosses = {
        { name = 'High Inquisitor Fairbanks', items = { { 19507, 'SHOULDER', 'Inquisitor\'s Shawl' }, { 19508, 'WRIST', 'Branded Leather Bracers' }, { 19509, 'FEET', 'Dusty Mail Boots' } } },
        { name = 'Scarlet Commander Mograine', items = { { 7723, '2HWEAPON', 'Mograine\'s Might' }, { 7724, 'HAND', 'Gauntlets of Divinity' }, { 7726, 'SHIELD', 'Aegis of the Scarlet Commander' } } },
        { name = 'High Inquisitor Whitemane', items = { { 7720, 'HEAD', 'Whitemane\'s Chapeau' }, { 7721, 'WEAPONMAINHAND', 'Hand of Righteousness' }, { 7722, 'NECK', 'Triune Amulet' } } },
        { name = 'Trash (butin de zone)', items = { { 10329 }, { 10333 }, { 10331 }, { 10328 }, { 1992 }, { 2262 }, { 5756 }, { 5819 }, { 7727 }, { 7728 }, { 7729 }, { 7730 }, { 7736 }, { 7752 }, { 7753 }, { 7754 }, { 7755 }, { 7757 }, { 7758 }, { 7759 }, { 7760 }, { 7761 }, { 7786 }, { 7787 }, { 8225 }, { 8226 }, { 10332 } } }, -- ancienne table
    } },
    { key = 'RFD', bosses = {
        { name = 'Tuten\'kash', items = { { 10775, 'CHEST', 'Carapace of Tuten\'kash' }, { 10776, 'CLOAK', 'Silky Spider Cape' }, { 10777, 'HAND', 'Arachnid Gloves' } } },
        { name = 'Mordresh Fire Eye', items = { { 10769, 'NECK', 'Glowing Eye of Mordresh' }, { 10770, 'HOLDABLE', 'Mordresh\'s Lifeless Skull' }, { 10771, 'WAIST', 'Deathmage Sash' } } },
        { name = 'Glutton', items = { { 10772, 'WEAPON', 'Glutton\'s Cleaver' }, { 10774, 'SHOULDER', 'Fleshhide Shoulders' } } },
        { name = 'Amnennar the Coldbringer', items = { { 10761, 'WEAPON', 'Coldrage Dagger' }, { 10762, 'CHEST', 'Robes of the Lich' }, { 10763, 'HEAD', 'Icemetal Barbute' }, { 10764, 'CHEST', 'Deathchill Armor' }, { 10765, 'HAND', 'Bonefingers' } } },
        { name = 'Ragglesnout', items = { { 10758, '2HWEAPON', 'X\'caliboar' }, { 10767, 'SHIELD', 'Savage Boar\'s Guard' }, { 10768, 'WAIST', 'Boar Champion\'s Belt' } } },
        { name = 'Plaguemaw the Rotting', items = { { 10760, 'HAND', 'Swine Fists' }, { 10766, 'RANGED', 'Plaguerot Sprig' } } },
        { name = 'Lady Falther\'ess', items = { { 23177 }, { 23178 } } }, -- ancienne table
        { name = 'Trash (butin de zone)', items = { { 10567 }, { 10570 }, { 10571 }, { 10572 }, { 10573 }, { 10574 }, { 10578 }, { 10581 }, { 10582 }, { 10583 }, { 10584 } } }, -- ancienne table
    } },
    { key = 'ULDA', bosses = {
        { name = 'Revelosh', items = { { 9387, 'FEET', 'Revelosh\'s Boots' }, { 9388, 'WRIST', 'Revelosh\'s Armguards' }, { 9389, 'SHOULDER', 'Revelosh\'s Spaulders' }, { 9390, 'HAND', 'Revelosh\'s Gloves' } } },
        { name = 'Ironaya', items = { { 9407, 'LEGS', 'Stoneweaver Leggings' }, { 9408, '2HWEAPON', 'Ironshod Bludgeon' }, { 9409, 'WRIST', 'Ironaya\'s Bracers' } } },
        { name = 'Obsidian Sentinel', items = { { 9384 } } }, -- ancienne table
        { name = 'Ancient Stone Keeper', items = { { 9410, 'HAND', 'Cragfists' }, { 9411, 'SHOULDER', 'Rockshard Pauldrons' } } },
        { name = 'Galgann Firehammer', items = { { 9412, 'RANGED', 'Galgann\'s Fireblaster' }, { 9419, 'WEAPONMAINHAND', 'Galgann\'s Firehammer' }, { 11310, 'SHOULDER', 'Flameseer Mantle' }, { 11311, 'CLOAK', 'Emberscale Cape' } } },
        { name = 'Grimlok', items = { { 9414, 'LEGS', 'Oilskin Leggings' }, { 9415, 'CHEST', 'Grimlok\'s Tribal Vestments' }, { 9416, '2HWEAPON', 'Grimlok\'s Charge' } } },
        { name = 'Archaedas', items = { { 9413, '2HWEAPON', 'The Rockpounder' }, { 9418, '2HWEAPON', 'Stoneslayer' }, { 11118, 'FINGER', 'Archaedic Stone' } } },
        { name = 'Baelog', items = { { 9400, 'RANGED', 'Baelog\'s Shortbow' }, { 9401, 'WEAPON', 'Nordic Longshank' } } },
        { name = 'Eric \\', items = { { 9398 }, { 9394 } } }, -- ancienne table
        { name = 'Olaf', items = { { 9403, 'SHIELD', 'Battered Viking Shield' }, { 9404, 'SHIELD', 'Olaf\'s All Purpose Shield' } } },
        { name = 'Trash (butin de zone)', items = { { 9381 }, { 9383 }, { 9384 }, { 9386 }, { 9391 }, { 9392 }, { 9393 }, { 9396 }, { 9397 }, { 9406 }, { 9420 }, { 9422 }, { 9423 }, { 9424 }, { 9425 }, { 9426 }, { 9427 }, { 9428 }, { 9429 }, { 9430 }, { 9431 }, { 9432 }, { 9465 }, { 7532 }, { 7542 } } }, -- ancienne table
        { name = 'Eric "The Swift"', items = { { 9394, 'HEAD', 'Horned Viking Helmet' }, { 9398, 'FEET', 'Worn Running Boots' } } },
    } },
    { key = 'ZF', bosses = {
        { name = 'Antu\'sul', items = { { 9379, 'WEAPON', 'Sang\'thraze the Deflector' }, { 9639, 'WEAPONMAINHAND', 'The Hand of Antu\'sul' }, { 9640, 'HAND', 'Vice Grips' }, { 9641, 'NECK', 'Lifeblood Amulet' } } },
        { name = 'Theka the Martyr', items = { { 5616 }, { 14660 }, { 15166 }, { 15373 }, { 15964 } } }, -- ancienne table
        { name = 'Witch Doctor Zum\'rah', items = { { 18082, '2HWEAPON', 'Zum\'rah\'s Vexing Cane' }, { 18083, 'HAND', 'Jumanza Grips' } } },
        { name = 'Nekrum Gutchewer', items = { { 14907 } } }, -- ancienne table
        { name = 'Shadowpriest Sezz\'ziz', items = { { 9470, 'HEAD', 'Bad Mojo Mask' }, { 9473, 'CHEST', 'Jinxed Hoodoo Skin' }, { 9474, 'LEGS', 'Jinxed Hoodoo Kilt' }, { 9475, '2HWEAPON', 'Diabolic Skiver' } } },
        { name = 'Sergeant Bly', items = { { 5616 } } }, -- ancienne table
        { name = 'Hydromancer Velratha', items = { { 1447 }, { 5616 } } }, -- ancienne table
        { name = 'Gahz\'rilla', items = { { 9467, 'WEAPON', 'Gahz\'rilla Fang' }, { 9469, 'CHEST', 'Gahz\'rilla Scale Armor' } } },
        { name = 'Chief Ukorz Sandscalp', items = { { 9476, 'SHOULDER', 'Big Bad Pauldrons' }, { 9477, '2HWEAPON', 'The Chief\'s Enforcer' }, { 9478, 'WEAPONMAINHAND', 'Ripsaw' }, { 9479, 'HEAD', 'Embrace of the Lycan' } } },
        { name = 'Zerillis', items = { { 12470, 'FEET', 'Sandstalker Ankleguards' } } },
        { name = 'Dustwraith', items = { { 12471, 'HOLDABLE', 'Desertwalker Cane' } } },
        { name = 'Trash (butin de zone)', items = { { 9243 }, { 11999 } } }, -- ancienne table
    } },
    { key = 'MARA', bosses = {
        { name = 'Noxxion', items = { { 17744, 'TRINKET', 'Heart of Noxxion' }, { 17745, 'RANGED', 'Noxious Shooter' }, { 17746, 'WRIST', 'Noxxion\'s Shackles' } } },
        { name = 'Razorlash', items = { { 17748, 'FEET', 'Vinerot Sandals' }, { 17749, 'SHOULDER', 'Phytoskin Spaulders' }, { 17750, 'WAIST', 'Chloromesh Girdle' }, { 17751, 'LEGS', 'Brusslehide Leggings' } } },
        { name = 'Lord Vyletongue', items = { { 17752, 'WEAPON', 'Satyr\'s Lash' }, { 17754, 'LEGS', 'Infernal Trickster Leggings' }, { 17755, 'WAIST', 'Satyrmane Sash' } } },
        { name = 'Celebras the Cursed', items = { { 17738, 'WEAPONOFFHAND', 'Claw of Celebras' }, { 17739, 'CLOAK', 'Grovekeeper\'s Drape' }, { 17740, 'HEAD', 'Soothsayer\'s Headdress' } } },
        { name = 'Landslide', items = { { 17734, 'HEAD', 'Helm of the Mountain' }, { 17736, 'HAND', 'Rockgrip Gauntlets' }, { 17737, 'HOLDABLE', 'Cloud Stone' }, { 17943, 'WEAPONMAINHAND', 'Fist of Stone' } } },
        { name = 'Tinkerer Gizlock', items = { { 17717, 'RANGED', 'Megashot Rifle' }, { 17718, 'SHIELD', 'Gizlock\'s Hypertech Buckler' }, { 17719, 'WEAPONMAINHAND', 'Inventor\'s Focal Sword' } } },
        { name = 'Rotgrip', items = { { 17728, 'FEET', 'Albino Crocscale Boots' }, { 17730, '2HWEAPON', 'Gatorbite Axe' }, { 17732, 'SHOULDER', 'Rotgrip Mantle' } } },
        { name = 'Princess Theradras', items = { { 17707, 'NECK', 'Gemshard Heart' }, { 17710, 'WEAPONMAINHAND', 'Charstone Dirk' }, { 17711, 'LEGS', 'Elemental Rockridge Leggings' }, { 17713, 'FINGER', 'Blackstone Ring' }, { 17714, 'WRIST', 'Bracers of the Stone Princess' }, { 17715, 'HEAD', 'Eye of Theradras' }, { 17766, '2HWEAPON', 'Princess Theradras\' Scepter' } } },
        { name = 'Meshlok the Harvester', items = { { 17741, 'CHEST', 'Nature\'s Embrace' }, { 17742, 'CHEST', 'Fungus Shroud Armor' }, { 17767, 'HEAD', 'Bloomsprout Headpiece' } } },
    } },
    { key = 'ST', bosses = {
        { name = 'Atal\'alarion', items = { { 10798, 'WAIST', 'Atal\'alarion\'s Tusk Ring' }, { 10800, 'WRIST', 'Darkwater Bracers' } } },
        { name = 'Dreamscythe', items = { { 12465 }, { 12466 }, { 12243 } } }, -- ancienne table
        { name = 'Weaver', items = { { 12243 }, { 12466 }, { 12465 } } }, -- ancienne table
        { name = 'Jammal\'an the Prophet', items = { { 10807, 'LEGS', 'Kilt of the Atal\'ai Prophet' } } },
        { name = 'Ogom the Wretched', items = { { 10803, 'WEAPONMAINHAND', 'Blade of the Wretched' }, { 10804, 'WEAPON', 'Fist of the Damned' }, { 10805, 'WEAPONMAINHAND', 'Eater of the Dead' } } },
        { name = 'Morphaz', items = { { 12466 }, { 12243 }, { 12465 } } }, -- ancienne table
        { name = 'Hazzas', items = { { 12466 }, { 12243 }, { 12465 } } }, -- ancienne table
        { name = 'Shade of Eranikus', items = { { 10833, 'HEAD', 'Horns of Eranikus' }, { 10836, 'RANGED', 'Rod of Corrosion' } } },
        { name = 'Avatar of Hakkar', items = { { 10843, 'CLOAK', 'Featherskin Cape' }, { 10845, 'CHEST', 'Warrior\'s Embrace' } } },
        { name = 'Spawn of Hakkar', items = { { 10801, 'FEET', 'Slitherscale Boots' } } },
        { name = 'Trash (butin de zone)', items = { { 10846 }, { 10842 }, { 10843 }, { 10845 }, { 10838 }, { 10844 }, { 10788 }, { 10795 }, { 10797 }, { 12463 }, { 10796 }, { 12466 }, { 12465 }, { 12243 }, { 10786 }, { 12464 }, { 10787 }, { 10785 }, { 10783 }, { 10784 }, { 10624 }, { 10625 }, { 10626 }, { 10629 }, { 10630 }, { 10631 }, { 10632 }, { 10633 } } }, -- ancienne table
    } },
    { key = 'BRD', bosses = {
        { name = 'High Interrogator Gerstahn', items = { { 11624, 'SHOULDER', 'Kentic Amice' }, { 11625, 'HOLDABLE', 'Enthralled Sphere' }, { 11626, 'CLOAK', 'Blackveil Cape' } } },
        { name = 'Lord Roccor', items = { { 22234, 'SHOULDER', 'Mantle of Lost Hope' } } },
        { name = 'Houndmaster Grebmar', items = { { 11628, 'RANGED', 'Houndmaster\'s Bow' } } },
        { name = 'Anub\'shiah', items = { { 11678, 'CHEST', 'Carapace of Anub\'shiah' } } },
        { name = 'Eviscerator', items = { { 11679 }, { 11685 }, { 11686 }, { 11730 } } }, -- ancienne table
        { name = 'Gorosh the Dervish', items = { { 22257 }, { 22271 }, { 22266 }, { 11726 } } }, -- ancienne table
        { name = 'Grizzle', items = { { 11703 }, { 11702 }, { 11722 }, { 22270 }, { 11610 } } }, -- ancienne table
        { name = 'Hedrum the Creeper', items = { { 11633, 'CHEST', 'Spiderfang Carapace' } } },
        { name = 'Ok\'thor the Breaker', items = { { 11665, 'HAND', 'Ogreseer Fists' } } },
        { name = 'Pyromancer Loregrain', items = { { 11749, 'LEGS', 'Searingscale Leggings' }, { 11750, '2HWEAPON', 'Kindling Stave' } } },
        { name = 'Lord Incendius', items = { { 11766, 'WRIST', 'Flameweave Cuffs' }, { 11767, 'WRIST', 'Emberplate Armguards' } } },
        { name = 'Warder Stilgiss', items = { { 11784, 'WEAPONMAINHAND', 'Arbiter\'s Blade' }, { 22241, 'SHOULDER', 'Dark Warder\'s Pauldrons' } } },
        { name = 'Verek', items = { { 22242, 'WAIST', 'Verek\'s Leash' } } },
        { name = 'Fineous Darkvire', items = { { 11841, 'LEGS', 'Senior Designer\'s Pantaloons' }, { 22223, 'HEAD', 'Foreman\'s Head Protector' } } },
        { name = 'Bael\'Gar', items = { { 11807, 'WAIST', 'Sash of the Burning Heart' } } },
        { name = 'General Angerforge', items = { { 11821, 'LEGS', 'Warstrife Leggings' } } },
        { name = 'Golem Lord Argelmach', items = { { 11819, 'TRINKET', 'Second Wind' } } },
        { name = 'Hurley Blackbreath', items = { { 11735, 'HEAD', 'Ragefury Eyepatch' }, { 22275, 'FEET', 'Firemoss Boots' } } },
        { name = 'Phalanx', items = { { 11745, 'HAND', 'Fists of Phalanx' } } },
        { name = 'Ribbly Screwspigot', items = { { 11612 }, { 227901 } } }, -- ancienne table
        { name = 'Plugger Spazzring', items = { { 12793 }, { 12791 }, { 18653 } } }, -- ancienne table
        { name = 'Ambassador Flamelash', items = { { 11814, 'HAND', 'Molten Fists' } } },
        { name = 'Magmus', items = { { 22208, '2HWEAPON', 'Lavastone Hammer' } } },
        { name = 'Emperor Dagran Thaurissan', items = { { 11815, 'TRINKET', 'Hand of Justice' }, { 11924, 'CHEST', 'Robes of the Royal Crown' }, { 16724, 'HAND', 'Lightforge Gauntlets' } } },
        { name = 'Panzor the Invincible', items = { { 11787 }, { 11786 }, { 11785 }, { 22245 } } }, -- ancienne table
        { name = 'Princess Moira Bronzebeard', items = { { 12554 }, { 12553 }, { 12557 }, { 12556 } } }, -- ancienne table
        { name = 'Secret Safe', items = { { 22205 }, { 22254 }, { 22256 }, { 22255 }, { 11920 }, { 11929 }, { 11926 } } }, -- ancienne table
        { name = 'Chest of The Seven', items = { { 11927 }, { 11925 } } }, -- ancienne table
        { name = 'Trash (butin de zone)', items = { { 22305 }, { 11920 }, { 11921 }, { 11922 }, { 11926 }, { 11929 }, { 12527 }, { 12528 }, { 12531 }, { 12532 }, { 12535 }, { 12542 }, { 12546 }, { 12547 }, { 12549 }, { 12550 }, { 12551 }, { 12552 }, { 12555 } } }, -- ancienne table
    } },
    { key = 'LBRS', bosses = {
        { name = 'Highlord Omokk', items = { { 13170, 'LEGS', 'Skyshroud Leggings' }, { 16670, 'FEET', 'Boots of Elements' } } },
        { name = 'Shadow Hunter Vosh\'gajin', items = { { 12653, 'RANGED', 'Riphook' }, { 16712, 'HAND', 'Shadowcraft Gloves' } } },
        { name = 'War Master Voone', items = { { 13179, 'WRIST', 'Brazecore Armguards' }, { 16676, 'HAND', 'Beaststalker\'s Gloves' } } },
        { name = 'Mother Smolderweb', items = { { 13183, 'WEAPON', 'Venomspitter' }, { 13213, 'TRINKET', 'Smolderweb\'s Eye' }, { 16715, 'FEET', 'Wildheart Boots' } } },
        { name = 'Urok Doomhowl', items = { { 13259 }, { 13258 }, { 22232 }, { 13178 } } }, -- ancienne table
        { name = 'Quartermaster Zigris', items = { { 16703, 'WRIST', 'Dreadmist Bracers' }, { 16713, 'WAIST', 'Shadowcraft Belt' }, { 16735, 'WRIST', 'Bracers of Valor' } } },
        { name = 'Gizrul the Slavener', items = { { 13205, 'SHIELD', 'Rhombeard Protector' }, { 13206, 'LEGS', 'Wolfshear Leggings' }, { 16718, 'SHOULDER', 'Wildheart Spaulders' } } },
        { name = 'Halycon', items = { { 13212, 'NECK', 'Halycon\'s Spiked Collar' }, { 22313, 'WRIST', 'Ironweave Bracers' } } },
        { name = 'Overlord Wyrmthalak', items = { { 13162, 'HAND', 'Reiver Claws' }, { 13164, 'TRINKET', 'Heart of the Scale' }, { 16679, 'SHOULDER', 'Beaststalker\'s Mantle' } } },
        { name = 'Spirestone Butcher', items = { { 12608 }, { 13286 } } }, -- ancienne table
        { name = 'Spirestone Battle Lord', items = { { 13284 }, { 13285 } } }, -- ancienne table
        { name = 'Spirestone Lord Magus', items = { { 13283, 'FINGER', 'Magus Ring' } } },
        { name = 'Bannok Grimaxe', items = { { 12634, 'WAIST', 'Chiselbrand Girdle' } } },
        { name = 'Crystal Fang', items = { { 13184, 'HAND', 'Fallbrush Handgrips' }, { 13218, 'WEAPON', 'Fang of the Crystal Spider' } } },
        { name = 'Ghok Bashguud', items = { { 13203 }, { 13204 }, { 13198 } } }, -- ancienne table
        { name = 'Burning Felguard', items = { { 13181 }, { 13182 } } }, -- ancienne table
        { name = 'Mor Grayhoof', items = { { 22306, 'WAIST', 'Ironweave Belt' } } },
        { name = 'Trash (butin de zone)', items = { { 16683 }, { 16680 }, { 16696 }, { 16703 }, { 16673 }, { 16735 }, { 16713 }, { 13260 }, { 16717 }, { 13371 } } }, -- ancienne table
    } },
    { key = 'UBRS', bosses = {
        { name = 'Pyroguard Emberseer', items = { { 16672, 'HAND', 'Gauntlets of Elements' } } },
        { name = 'Solakar Flamewreath', items = { { 16695, 'SHOULDER', 'Devout Mantle' } } },
        { name = 'Goraluk Anvilcrack', items = { { 13498 }, { 18048 }, { 18047 }, { 13502 }, { 12834 }, { 12837 }, { 228312 } } }, -- ancienne table
        { name = 'Gyth', items = { { 16669, 'SHOULDER', 'Pauldrons of Elements' } } },
        { name = 'Warchief Rend Blackhand', items = { { 16733, 'SHOULDER', 'Spaulders of Valor' } } },
        { name = 'The Beast', items = { { 16729, 'SHOULDER', 'Lightforge Spaulders' }, { 22311, 'FEET', 'Ironweave Boots' } } },
        { name = 'General Drakkisath', items = { { 16666, 'CHEST', 'Vest of Elements' }, { 16674, 'CHEST', 'Beaststalker\'s Tunic' }, { 16688, 'CHEST', 'Magister\'s Robes' }, { 16690, 'CHEST', 'Devout Robe' }, { 16700, 'CHEST', 'Dreadmist Robe' }, { 16706, 'CHEST', 'Wildheart Vest' }, { 16721, 'CHEST', 'Shadowcraft Tunic' }, { 16726, 'CHEST', 'Lightforge Breastplate' }, { 16730, 'CHEST', 'Breastplate of Valor' } } },
        { name = 'Jed Runewatcher', items = { { 12605 }, { 12604 }, { 12930 } } }, -- ancienne table
        { name = 'Lord Valthalak', items = { { 22302, 'HEAD', 'Ironweave Cowl' } } },
        { name = 'Trash (butin de zone)', items = { { 16683 }, { 16680 }, { 16696 }, { 16703 }, { 16673 }, { 16735 }, { 16713 }, { 13260 }, { 16717 }, { 13371 } } }, -- ancienne table
    } },
    { key = 'DME', bosses = {
        { name = 'Pusillin', items = { { 18267 } } }, -- ancienne table
        { name = 'Zevrim Thornhoof', items = { { 18319, 'HEAD', 'Fervent Helm' }, { 18323, 'RANGED', 'Satyr\'s Bow' } } },
        { name = 'Hydrospawn', items = { { 18305, 'LEGS', 'Breakwater Legguards' }, { 18324, '2HWEAPON', 'Waveslicer' } } },
        { name = 'Lethtendris', items = { { 18302, 'FINGER', 'Band of Vigor' } } },
        { name = 'Alzzin the Wildshaper', items = { { 18315, 'FINGER', 'Ring of Demonic Potency' }, { 18326, 'HAND', 'Razor Gauntlets' } } },
        { name = 'Isalien', items = { { 22304, 'HAND', 'Ironweave Gloves' } } },
        { name = 'Trash (butin de zone)', items = { { 18494 }, { 18498 }, { 18496 }, { 18493 }, { 18497 }, { 18289 }, { 18295 }, { 18340 }, { 18343 }, { 18339 }, { 18338 }, { 18344 }, { 18337 }, { 18298 }, { 18296 }, { 18528 }, { 18530 }, { 18533 }, { 18475 }, { 18477 }, { 18479 } } }, -- ancienne table
    } },
    { key = 'DMW', bosses = {
        { name = 'Tendris Warpwood', items = { { 18390 }, { 18352 }, { 18353 }, { 18393 } } }, -- ancienne table
        { name = 'Illyanna Ravenoak', items = { { 18347 }, { 18349 }, { 18383 }, { 18386 } } }, -- ancienne table
        { name = 'Magister Kalendris', items = { { 18350 }, { 18351 }, { 18374 }, { 18397 }, { 18371 }, { 22309 } } }, -- ancienne table
        { name = 'Immol\'thar', items = { { 18377 }, { 18379 }, { 18381 }, { 18391 }, { 18385 }, { 18384 }, { 18389 }, { 18394 }, { 18372 }, { 18370 } } }, -- ancienne table
        { name = 'Prince Tortheldrin', items = { { 18395 }, { 18382 }, { 18380 }, { 18378 }, { 18396 }, { 18392 }, { 18376 }, { 18375 }, { 18388 }, { 18373 } } }, -- ancienne table
        { name = 'Tsu\'zee', items = { { 18345 }, { 18387 }, { 18346 } } }, -- ancienne table
        { name = 'Lord Hel\'nurath', items = { { 18755 }, { 18756 }, { 18757 }, { 18754 } } }, -- ancienne table
        { name = 'Revanchion', items = { { 23128 }, { 23127 }, { 23129 } } }, -- ancienne table
        { name = 'Trash (butin de zone)', items = { { 18494 }, { 18498 }, { 18496 }, { 18493 }, { 18497 }, { 18289 }, { 18295 }, { 18340 }, { 18343 }, { 18339 }, { 18338 }, { 18344 }, { 18337 }, { 18298 }, { 18296 }, { 18528 }, { 18530 }, { 18533 }, { 18475 }, { 18477 }, { 18479 } } }, -- ancienne table
    } },
    { key = 'DMN', bosses = {
        { name = 'Stomper Kreeg', items = { { 18425 } } }, -- ancienne table
        { name = 'Guard Fengus', items = { { 18450 }, { 18451 }, { 18458 }, { 18459 }, { 18460 }, { 18462 }, { 18463 }, { 18464 } } }, -- ancienne table
        { name = 'Captain Kromcrush', items = { { 18503 }, { 18507 }, { 18505 }, { 18502 } } }, -- ancienne table
        { name = 'King Gordok', items = { { 18521 }, { 18524 }, { 18523 }, { 18527 }, { 18525 }, { 18520 }, { 18522 }, { 18526 } } }, -- ancienne table
        { name = 'Cho\'Rush the Observer', items = { { 18484 }, { 18483 }, { 18485 }, { 18490 } } }, -- ancienne table
        { name = 'Gordok Tribute', items = { { 18478 }, { 18500 }, { 18481 }, { 18499 }, { 18529 }, { 18480 }, { 18532 }, { 18531 }, { 18482 }, { 18534 }, { 18476 }, { 18495 }, { 18537 } } }, -- ancienne table
        { name = 'Trash (butin de zone)', items = { { 18494 }, { 18498 }, { 18496 }, { 18493 }, { 18497 }, { 18289 }, { 18295 }, { 18340 }, { 18343 }, { 18339 }, { 18338 }, { 18344 }, { 18337 }, { 18298 }, { 18296 }, { 18528 }, { 18530 }, { 18533 }, { 18475 }, { 18477 }, { 18479 } } }, -- ancienne table
    } },
    { key = 'STRAT', bosses = {
        { name = 'Timmy the Cruel', items = { { 16724, 'HAND', 'Lightforge Gauntlets' } } },
        { name = 'The Unforgiven', items = { { 13405, 'SHOULDER', 'Wailing Nightbane Pauldrons' }, { 16717, 'HAND', 'Wildheart Gloves' } } },
        { name = 'Hearthsinger Forresten', items = { { 16682, 'FEET', 'Magister\'s Boots' } } },
        { name = 'Cannon Master Willey', items = { { 16708, 'SHOULDER', 'Shadowcraft Spaulders' } } },
        { name = 'Archivist Galford', items = { { 13385, 'HOLDABLE', 'Tome of Knowledge' }, { 16692, 'HAND', 'Devout Gloves' } } },
        { name = 'Balnazzar', items = { { 13358, 'SHOULDER', 'Wyrmtongue Shoulders' }, { 13359, 'HEAD', 'Crown of Tyranny' }, { 16725, 'FEET', 'Lightforge Boots' } } },
        { name = 'Skul', items = { { 13395, 'HAND', 'Skul\'s Fingerbone Claws' } } },
        { name = 'Stonespine', items = { { 13954, 'FEET', 'Verdant Footpads' } } },
        { name = 'Postmaster Malown', items = { { 13388 }, { 13392 }, { 13393 }, { 13391 }, { 13389 }, { 13390 } } }, -- ancienne table
        { name = 'Grand Crusader Dathrohan', items = { { 13358, 'SHOULDER', 'Wyrmtongue Shoulders' }, { 13359, 'HEAD', 'Crown of Tyranny' }, { 16725, 'FEET', 'Lightforge Boots' } } },
        { name = 'Balzaphon', items = { { 23125, 'NECK', 'Chains of the Lich' } } },
        { name = 'Magistrate Barthilas', items = { { 18725, '2HWEAPON', 'Peacemaker' }, { 18727, 'HEAD', 'Crimson Felt Hat' } } },
        { name = 'Baroness Anastari', items = { { 16704, 'FEET', 'Dreadmist Sandals' }, { 18730, 'HAND', 'Shadowy Laced Handwraps' } } },
        { name = 'Nerub\'enkan', items = { { 13529, 'SHIELD', 'Husk of Nerub\'enkan' }, { 13531, 'LEGS', 'Crypt Stalker Leggings' }, { 16675, 'FEET', 'Beaststalker\'s Boots' } } },
        { name = 'Maleki the Pallid', items = { { 13524, 'HOLDABLE', 'Skull of Burning Shadows' }, { 13528, 'WRIST', 'Twilight Void Bracers' }, { 16691, 'FEET', 'Devout Sandals' } } },
        { name = 'Ramstein the Gorger', items = { { 16737, 'HAND', 'Gauntlets of Valor' }, { 18723, 'NECK', 'Animated Chain Necklace' } } },
        { name = 'Baron Rivendare', items = { { 13340, 'CLOAK', 'Cape of the Black Baron' }, { 16668, 'LEGS', 'Kilt of Elements' }, { 16678, 'LEGS', 'Beaststalker\'s Pants' }, { 16687, 'LEGS', 'Magister\'s Leggings' }, { 16694, 'LEGS', 'Devout Skirt' }, { 16699, 'LEGS', 'Dreadmist Leggings' }, { 16709, 'LEGS', 'Shadowcraft Pants' }, { 16719, 'LEGS', 'Wildheart Kilt' }, { 16728, 'LEGS', 'Lightforge Legplates' }, { 16732, 'LEGS', 'Legplates of Valor' }, { 22408, 'RANGED', 'Ritssyn\'s Wand of Bad Mojo' } } },
        { name = 'Trash (butin de zone)', items = { { 16723 }, { 16697 }, { 16671 }, { 16681 }, { 16685 }, { 16702 }, { 16714 }, { 16736 }, { 17061 }, { 18736 }, { 18741 }, { 18742 }, { 18743 }, { 18744 }, { 18745 } } }, -- ancienne table
    } },
    { key = 'SCHOLO', bosses = {
        { name = 'Kirtonos the Herald', items = { { 13957, 'HAND', 'Gargoyle Slashers' }, { 16734, 'FEET', 'Boots of Valor' } } },
        { name = 'Jandice Barov', items = { { 16701, 'SHOULDER', 'Dreadmist Mantle' } } },
        { name = 'Rattlegore', items = { { 14528, 'SHIELD', 'Rattlecage Buckler' }, { 16711, 'FEET', 'Shadowcraft Boots' } } },
        { name = 'Marduk Blackpool', items = { { 18692 }, { 14576 } } }, -- ancienne table
        { name = 'Vectus', items = { { 14577 }, { 18691 } } }, -- ancienne table
        { name = 'Ras Frostwhisper', items = { { 16689, 'SHOULDER', 'Magister\'s Mantle' } } },
        { name = 'Instructor Malicia', items = { { 14626, 'CHEST', 'Necropile Robe' }, { 14629, 'WRIST', 'Necropile Cuffs' }, { 14631, 'FEET', 'Necropile Boots' }, { 14632, 'LEGS', 'Necropile Leggings' }, { 14633, 'SHOULDER', 'Necropile Mantle' }, { 16710, 'WRIST', 'Shadowcraft Bracers' } } },
        { name = 'Doctor Theolen Krastinov', items = { { 14626, 'CHEST', 'Necropile Robe' }, { 14629, 'WRIST', 'Necropile Cuffs' }, { 14631, 'FEET', 'Necropile Boots' }, { 14632, 'LEGS', 'Necropile Leggings' }, { 14633, 'SHOULDER', 'Necropile Mantle' }, { 16684, 'HAND', 'Magister\'s Gloves' } } },
        { name = 'Lorekeeper Polkelt', items = { { 14629, 'WRIST', 'Necropile Cuffs' }, { 14631, 'FEET', 'Necropile Boots' }, { 14632, 'LEGS', 'Necropile Leggings' }, { 14633, 'SHOULDER', 'Necropile Mantle' }, { 16705, 'HAND', 'Dreadmist Wraps' } } },
        { name = 'The Ravenian', items = { { 14626, 'CHEST', 'Necropile Robe' }, { 14629, 'WRIST', 'Necropile Cuffs' }, { 14631, 'FEET', 'Necropile Boots' }, { 14632, 'LEGS', 'Necropile Leggings' }, { 14633, 'SHOULDER', 'Necropile Mantle' }, { 16716, 'WAIST', 'Wildheart Belt' } } },
        { name = 'Lord Alexei Barov', items = { { 14626, 'CHEST', 'Necropile Robe' }, { 14629, 'WRIST', 'Necropile Cuffs' }, { 14631, 'FEET', 'Necropile Boots' }, { 14632, 'LEGS', 'Necropile Leggings' }, { 14633, 'SHOULDER', 'Necropile Mantle' }, { 16722, 'WRIST', 'Lightforge Bracers' } } },
        { name = 'Lady Illucia Barov', items = { { 14629, 'WRIST', 'Necropile Cuffs' }, { 14631, 'FEET', 'Necropile Boots' }, { 14632, 'LEGS', 'Necropile Leggings' }, { 14633, 'SHOULDER', 'Necropile Mantle' } } },
        { name = 'Darkmaster Gandling', items = { { 16667, 'HEAD', 'Coif of Elements' }, { 16677, 'HEAD', 'Beaststalker\'s Cap' }, { 16686, 'HEAD', 'Magister\'s Crown' }, { 16693, 'HEAD', 'Devout Crown' }, { 16698, 'HEAD', 'Dreadmist Mask' }, { 16707, 'HEAD', 'Shadowcraft Cap' }, { 16720, 'HEAD', 'Wildheart Cowl' }, { 16727, 'HEAD', 'Lightforge Helm' }, { 16731, 'HEAD', 'Helm of Valor' } } },
        { name = 'Lord Blackwood', items = { { 23132 }, { 23139 }, { 23156 } } }, -- ancienne table
        { name = 'Kormok', items = { { 22303, 'LEGS', 'Ironweave Pants' } } },
        { name = 'Death Knight Darkreaver', items = { { 18760, 'FINGER', 'Necromantic Band' } } },
        { name = 'Trash (butin de zone)', items = { { 16684 }, { 16705 }, { 14631 }, { 14636 }, { 14638 }, { 14629 }, { 14632 }, { 14633 }, { 14640 }, { 14641 }, { 14615 }, { 14620 }, { 16722 }, { 14612 }, { 14614 }, { 14616 }, { 14621 }, { 14622 }, { 14623 }, { 14626 }, { 18680 }, { 18681 }, { 18683 }, { 14637 }, { 18682 }, { 18684 }, { 14624 }, { 14611 }, { 23200 }, { 14536 }, { 18697 }, { 18698 }, { 18699 }, { 18700 }, { 18701 }, { 18702 } } }, -- ancienne table
    } },
}
