local _, Q = ...
local cache,revision
local ACCENTS = {
    ['é']='e',['è']='e',['ê']='e',['ë']='e',['É']='e',['È']='e',['Ê']='e',['Ë']='e',
    ['à']='a',['â']='a',['ä']='a',['À']='a',['Â']='a',['Ä']='a',
    ['ç']='c',['Ç']='c',
    ['î']='i',['ï']='i',['Î']='i',['Ï']='i',
    ['ô']='o',['ö']='o',['Ô']='o',['Ö']='o',
    ['ù']='u',['û']='u',['ü']='u',['Ù']='u',['Û']='u',['Ü']='u',
    ['ÿ']='y',['œ']='oe',['Œ']='oe',['æ']='ae',['Æ']='ae',
}
-- Une seule passe pour les accents : toutes les lettres de ACCENTS sont des caractères UTF-8 de 2 octets en \195 ou \197
-- (35 gsub par appel auparavant, une par lettre : le gros du coût de l'index de la fenêtre).
local function fold(value)
    local s=tostring(value or ''):gsub('[\195\197][\128-\191]',ACCENTS)
    s=s:gsub('[A-Z]',string.lower)
    s=s:gsub('elexir','elixir')
    return s
end
Q.Fold=fold

-- Catégories officielles des métiers en jeu (complétées par les en-têtes exacts lus via C_TradeSkillUI.GetCategoryInfo / GetTradeSkillInfo)
Q.PROFESSION_CATEGORIES = {
    enchanting = {
        'Bottes', 'Bracelets', 'Cape', 'Gants', 'Plastron', 'Bouclier',
        'Arme', 'Arme 2M', 'Baguettes', 'Huiles', 'Matériaux', 'Autre',
    },
    alchemy = {
        'Élixirs', 'Flacons', 'Potions', 'Potions de soins et de mana',
        'Potions de protection', 'Transmutations', 'Huiles',
    },
    blacksmithing = {
        'Modifications d\'armes', 'Heaumes', 'Épaulières', 'Cuirasses', 'Bracelets',
        'Gantelets', 'Ceintures', 'Jambières', 'Bottes', 'Boucliers',
        'Dagues', 'Haches à une main', 'Haches à deux mains',
        'Masses à une main', 'Masses à deux mains',
        'Épées à une main', 'Épées à deux mains', 'Armes d\'hast', 'Matériaux',
    },
    tailoring = {
        'Sacs', 'Chapeaux', 'Épaulières', 'Robes et tuniques', 'Bracelets',
        'Gants', 'Ceintures', 'Pantalons', 'Bottes', 'Capes', 'Chemises', 'Matériaux',
    },
    leatherworking = {
        'Renforts d\'armure', 'Sacs et carquois', 'Casques', 'Épaulières',
        'Cuirasses', 'Bracelets', 'Gants', 'Ceintures', 'Pantalons', 'Bottes', 'Capes', 'Matériaux',
    },
    engineering = {
        'Explosifs', 'Lunettes', 'Armes à feu et arcs', 'Lunettes de visée',
        'Munitions', 'Bijoux', 'Appareils', 'Pièces',
    },
    cooking = {
        'Viandes', 'Poissons', 'Boissons', 'Desserts et pains',
    },
    firstaid = {
        'Bandages', 'Antivenins',
    },
    mining = {
        'Fonte',
    },
}

local function hasAny(s, words)
    for i = 1, #words do
        if s:find(words[i], 1, true) then return true end
    end
    return false
end

function Q.ProfessionKey(profession)
    local p = fold(profession or '')
    if p:find('alchim', 1, true) or p:find('alchem', 1, true) then return 'alchemy' end
    if p:find('enchant', 1, true) then return 'enchanting' end
    if p:find('forge', 1, true) or p:find('blacksmith', 1, true) then return 'blacksmithing' end
    if p:find('coutur', 1, true) or p:find('tailor', 1, true) then return 'tailoring' end
    if p:find('cuir', 1, true) or p:find('leather', 1, true) then return 'leatherworking' end
    if p:find('ingenier', 1, true) or p:find('engineer', 1, true) then return 'engineering' end
    if p:find('cuisin', 1, true) or p:find('cook', 1, true) then return 'cooking' end
    if p:find('secour', 1, true) or p:find('first aid', 1, true) or p == 'firstaid' then return 'firstaid' end
    if p:find('minag', 1, true) or p:find('mining', 1, true) or p:find('fonte', 1, true) or p:find('smelt', 1, true) then return 'mining' end
    return 'other'
end

local function itemEquipLoc(itemID)
    if not itemID then return nil end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c, d = Q.Call(fn, itemID)
    if not ok then return nil end
    if type(d) == 'string' and d:match('^INVTYPE_') then return d end
    if type(c) == 'string' and c:match('^INVTYPE_') then return c end
    if type(b) == 'string' and b:match('^INVTYPE_') then return b end
    if type(a) == 'string' and a:match('^INVTYPE_') then return a end
    return nil
end

--- Renvoie la catégorie en jeu de la recette (priorité à l'en-tête exact lu dans le métier en jeu `explicitCategory`,
--- sinon catégorie officielle du métier déduite du nom et de l'emplacement d'objet).
function Q.CategorizeRecipe(profession, name, itemID, explicitCategory)
    if type(explicitCategory) == 'string' and explicitCategory ~= '' and explicitCategory ~= 'Category' then
        return explicitCategory, ''
    end
    local pkey = Q.ProfessionKey(profession)
    local s = fold(name or '')
    local loc = itemEquipLoc(itemID)

    if pkey == 'enchanting' then
        if hasAny(s, { 'bouclier', 'shield', 'main gauche', 'off-hand' }) then
            return 'Bouclier', 'bouclier shield main gauche'
        elseif hasAny(s, { 'plastron', 'torse', 'chest' }) then
            return 'Plastron', 'plastron torse chest'
        elseif hasAny(s, { 'bracelet', 'poignet', 'bracer', 'wrist' }) then
            return 'Bracelets', 'bracelets poignets bracer wrist'
        elseif hasAny(s, { 'gant', 'mains', 'glove', 'hands' }) then
            return 'Gants', 'gants mains gloves hands'
        elseif hasAny(s, { 'botte', 'pied', 'chaussure', 'boot', 'feet' }) then
            return 'Bottes', 'bottes pieds chaussures boots feet'
        elseif hasAny(s, { 'cape', 'dos', 'manteau', 'cloak', 'back' }) then
            return 'Cape', 'cape dos manteau cloak back'
        elseif hasAny(s, { 'arme 2m', 'deux mains', '2h', 'two-hand', 'baton', 'staff' }) then
            return 'Arme 2M', 'arme 2m deux mains baton'
        elseif hasAny(s, { 'arme', 'weapon', 'croise', 'crusader', 'flamboyant', 'fiery', 'frisson', 'icy chill', 'siphonnage', 'lifestealing', 'faucon' }) then
            return 'Arme', 'arme weapon'
        elseif hasAny(s, { 'baguette', 'wand' }) then
            return 'Baguettes', 'baguette wand'
        elseif hasAny(s, { 'huile', 'oil' }) then
            return 'Huiles', 'huile oil'
        elseif hasAny(s, { 'batonnet', 'rod', 'poussiere', 'essence', 'eclat', 'cristal', 'cuir enchante', 'thorium enchante', 'dust', 'shard', 'crystal', 'enchanted' }) then
            return 'Matériaux', 'batonnet rod materiau'
        end
        return 'Autre', 'enchantement'
    elseif pkey == 'alchemy' then
        if hasAny(s, { 'flacon', 'flask' }) then
            return 'Flacons', 'flacon flask'
        elseif hasAny(s, { 'elixir', 'mangouste', 'mongoose', 'pouvoir des ombres', 'shadow power', 'pouvoir du feu', 'fire power', 'pouvoir du givre', 'frost power', 'robustesse', 'fortitude', 'sagesse', 'geants', 'giants', 'oeil de chat', 'cat\'s eye', 'respiration aquatique', 'water breathing', 'detection', 'detect', 'arthas', 'vision', 'arcanes', 'arcane', 'defense', 'force du lion', 'agilite', 'tueur de demons', 'demonslaying', 'sang de mage', 'mageblood' }) and not hasAny(s, { 'potion', 'transmut', 'flacon', 'flask', 'huile', 'oil' }) then
            return 'Élixirs', 'elixir elexir'
        elseif hasAny(s, { 'transmut', 'pierre philosophale', 'philosopher', 'arcanite' }) then
            return 'Transmutations', 'transmutation transmuter'
        elseif hasAny(s, { 'huile', 'oil', 'teinture', 'dye', 'carburant', 'fuel', 'vitriol' }) then
            return 'Huiles', 'huile oil'
        elseif hasAny(s, { 'protection', 'absorption', 'resistance' }) then
            return 'Potions de protection', 'potion protection resistance'
        elseif hasAny(s, { 'soin', 'mana', 'regeneration', 'rajeunissement', 'rejuvenation', 'healing', 'sommeil', 'dreamless', 'sang de troll', 'troll\'s blood', 'guerison' }) then
            return 'Potions de soins et de mana', 'potion soins mana vie'
        end
        return 'Potions', 'potion'
    elseif pkey == 'blacksmithing' then
        if hasAny(s, { 'pierre a aiguiser', 'pierre de lest', 'sharpening', 'weightstone', 'contrepoids', 'counterweight', 'dragonne', 'weapon chain', 'passe-partout', 'skeleton key', 'cle ', 'key', 'eperons', 'spurs', 'pointe de bouclier', 'shield spike' }) then
            return 'Modifications d\'armes', 'pierre aiguiser lest cle pointe dragonne'
        elseif hasAny(s, { 'batonnet', 'rod', 'barre ', 'lingot', 'clou', 'stud', 'boucle en', 'sangle en' }) then
            return 'Matériaux', ''
        elseif loc == 'INVTYPE_SHIELD' or hasAny(s, { 'bouclier', 'ecu', 'rempart', 'shield', 'buckler', 'bulwark' }) then
            return 'Boucliers', 'bouclier shield'
        elseif loc == 'INVTYPE_HEAD' or hasAny(s, { 'heaume', 'casque', 'couronne', 'diademe', 'visiere', 'chapel', 'helm', 'crown', 'circlet', 'visor', 'coeur-de-lion', 'lionheart' }) then
            return 'Heaumes', 'tete casque heaume'
        elseif loc == 'INVTYPE_SHOULDER' or hasAny(s, { 'epauliere', 'spalliere', 'mantelet', 'protege-epaules', 'shoulder', 'pauldron', 'spaulder', 'mantle' }) then
            return 'Épaulières', 'epaules epaulieres'
        elseif loc == 'INVTYPE_CHEST' or loc == 'INVTYPE_ROBE' or hasAny(s, { 'cuirasse', 'plastron', 'cotte', 'haubert', 'tunique', 'gilet', 'armure', 'breastplate', 'chest', 'hauberk', 'tunic', 'vest', 'armor', 'coat' }) then
            return 'Cuirasses', 'torse plastron cuirasse'
        elseif loc == 'INVTYPE_LEGS' or hasAny(s, { 'jambiere', 'jambard', 'pantalon', 'cuissard', 'legging', 'legplate', 'legguard', 'pants' }) then
            return 'Jambières', 'jambes jambieres pantalon'
        elseif loc == 'INVTYPE_HAND' or hasAny(s, { 'gantelet', 'gant', 'mains', 'poigne', 'gauntlet', 'glove', 'hand' }) then
            return 'Gantelets', 'gants gantelets mains'
        elseif loc == 'INVTYPE_FEET' or hasAny(s, { 'botte', 'soleret', 'sabot', 'pied', 'brodequin', 'greve', 'boot', 'sabaton', 'greave', 'footguard' }) then
            return 'Bottes', 'bottes pieds solerets'
        elseif loc == 'INVTYPE_WRIST' or hasAny(s, { 'brassard', 'bracelet', 'poignet', 'garde-poignet', 'bracer', 'vambrace', 'wrist' }) then
            return 'Bracelets', 'bracelets brassards poignets'
        elseif loc == 'INVTYPE_WAIST' or hasAny(s, { 'ceinture', 'sangle', 'ceinturon', 'baudrier', 'cordon', 'belt', 'girdle', 'waist', 'cinch', 'cord' }) then
            return 'Ceintures', 'ceinture taille'
        elseif hasAny(s, { 'dague', 'kriss', 'dirk', 'dagger', 'shanker', 'heartseeker' }) then
            return 'Dagues', 'arme dague'
        elseif hasAny(s, { 'hallebarde', 'lance', 'pique', 'polearm', 'spear', 'halberd' }) then
            return 'Armes d\'hast', 'arme hast lance'
        elseif (loc == 'INVTYPE_2HWEAPON' or hasAny(s, { 'deux mains', '2m', 'lourde', 'grand', 'greataxe', '2h', 'crepuscule', 'nightfall', 'annihilator', 'arcanite reaper', 'faucheuse' })) and hasAny(s, { 'hache', 'fendoir', 'couperet', 'axe', 'cleaver', 'reaper', 'crepuscule', 'nightfall' }) then
            return 'Haches à deux mains', 'arme 2m hache'
        elseif hasAny(s, { 'hache', 'fendoir', 'couperet', 'axe', 'cleaver' }) then
            return 'Haches à une main', 'arme 1m hache'
        elseif (loc == 'INVTYPE_2HWEAPON' or hasAny(s, { 'deux mains', '2m', 'lourd', 'grand', '2h', 'sulfuron', 'pulv' })) and hasAny(s, { 'masse', 'marteau', 'mailloche', 'mace', 'hammer', 'maul', 'sulfuron' }) then
            return 'Masses à deux mains', 'arme 2m masse marteau'
        elseif hasAny(s, { 'masse', 'marteau', 'broyeur', 'main d\'ebene', 'mace', 'hammer', 'crusher', 'persuader', 'ebon hand' }) then
            return 'Masses à une main', 'arme 1m masse marteau'
        elseif loc == 'INVTYPE_2HWEAPON' or hasAny(s, { 'espadon', 'claymore', 'deux mains', '2m', 'greatsword', 'two-hand', '2h', 'destructeur', 'destroyer', 'corruptrice' }) then
            return 'Épées à deux mains', 'arme 2m epee'
        elseif loc == 'INVTYPE_WEAPON' or loc == 'INVTYPE_WEAPONMAINHAND' or loc == 'INVTYPE_WEAPONOFFHAND' or hasAny(s, { 'epee', 'lame', 'glaive', 'coutelas', 'rapiere', 'trancheuse', 'sword', 'blade', 'rapier', 'slicer', 'blackguard' }) then
            return 'Épées à une main', 'arme 1m epee'
        end
        return 'Matériaux', ''
    elseif pkey == 'tailoring' then
        if loc == 'INVTYPE_BAG' or hasAny(s, { 'sac', 'bourse', 'besace', 'fourre-tout', 'cartable', 'giberne', 'bag', 'pouch', 'satchel', 'pack' }) then
            return 'Sacs', 'sac bourse besace'
        elseif loc == 'INVTYPE_HEAD' or hasAny(s, { 'chapeau', 'chapel', 'couronne', 'diademe', 'bandeau', 'masque', 'cagoule', 'capuche', 'coiffe', 'turban', 'hat', 'cowl', 'hood', 'circlet', 'crown', 'headband', 'mask', 'cap', 'whitemend' }) then
            return 'Chapeaux', 'tete chapeau couronne capuche'
        elseif loc == 'INVTYPE_SHOULDER' or hasAny(s, { 'epauliere', 'mantelet', 'protege-epaules', 'spalliere', 'mantle', 'pads', 'shoulder', 'pauldron' }) then
            return 'Épaulières', 'epaules epaulieres mantelet'
        elseif loc == 'INVTYPE_CHEST' or loc == 'INVTYPE_ROBE' or hasAny(s, { 'robe', 'tunique', 'gilet', 'pourpoint', 'habit', 'veste', 'vest', 'tunic', 'jerkin', 'coat', 'jacket' }) then
            return 'Robes et tuniques', 'torse robe tunique'
        elseif loc == 'INVTYPE_LEGS' or hasAny(s, { 'pantalon', 'jambiere', 'kilt', 'culotte', 'braies', 'jambard', 'pants', 'legging', 'breeches', 'trousers', 'legwrap' }) then
            return 'Pantalons', 'jambes pantalon jambieres'
        elseif loc == 'INVTYPE_HAND' or hasAny(s, { 'gant', 'mains', 'moufle', 'glove', 'hand', 'mitt' }) then
            return 'Gants', 'gants mains'
        elseif loc == 'INVTYPE_FEET' or hasAny(s, { 'botte', 'sandale', 'chaussure', 'mule', 'soulier', 'bottine', 'chausson', 'boot', 'sandal', 'shoe', 'slipper', 'walker', 'tread' }) then
            return 'Bottes', 'bottes pieds sandales chaussures'
        elseif loc == 'INVTYPE_WRIST' or hasAny(s, { 'brassard', 'bracelet', 'poignet', 'manchette', 'bracer', 'wrist', 'cuff', 'binding' }) then
            return 'Bracelets', 'bracelets brassards poignets'
        elseif loc == 'INVTYPE_WAIST' or hasAny(s, { 'ceinture', 'echarpe', 'cordon', 'sangle', 'ceinturon', 'belt', 'sash', 'cord', 'girdle', 'waist' }) then
            return 'Ceintures', 'ceinture echarpe taille'
        elseif loc == 'INVTYPE_CLOAK' or hasAny(s, { 'cape', 'manteau', 'drape', 'chale', 'voile', 'cloak', 'shawl', 'wrap' }) then
            return 'Capes', 'cape dos manteau'
        elseif loc == 'INVTYPE_BODY' or hasAny(s, { 'chemise', 'camisole', 'shirt', 'swashbuckler' }) then
            return 'Chemises', 'chemise'
        end
        return 'Matériaux', 'etoffe rouleau fil'
    elseif pkey == 'leatherworking' then
        if hasAny(s, { 'renfort', 'armure de jambe', 'piece d\'armure', 'armor kit', 'leg armor', 'reinforcement' }) then
            return 'Renforts d\'armure', 'renfort kit'
        elseif loc == 'INVTYPE_BAG' or loc == 'INVTYPE_QUIVER' or hasAny(s, { 'carquois', 'giberne', 'sac', 'bourse', 'quiver', 'ammo pouch', 'pouch', 'bag', 'bandolier' }) then
            return 'Sacs et carquois', 'carquois giberne sac'
        elseif loc == 'INVTYPE_HEAD' or hasAny(s, { 'casque', 'heaume', 'chapel', 'chapeau', 'masque', 'cagoule', 'coiffe', 'bandeau', 'couronne', 'helm', 'cap', 'hat', 'mask', 'hood', 'cowl', 'headband', 'crown' }) then
            return 'Casques', 'tete casque'
        elseif loc == 'INVTYPE_SHOULDER' or hasAny(s, { 'epauliere', 'spalliere', 'mantelet', 'protege-epaules', 'shoulder', 'spaulder', 'mantle', 'pauldron', 'pads' }) then
            return 'Épaulières', 'epaules epaulieres'
        elseif loc == 'INVTYPE_CHEST' or loc == 'INVTYPE_ROBE' or hasAny(s, { 'tunique', 'plastron', 'gilet', 'cuirasse', 'harnais', 'pourpoint', 'cotte', 'haubert', 'armure', 'veste', 'tunic', 'breastplate', 'vest', 'jerkin', 'harness', 'hauberk', 'armor', 'coat', 'chestguard' }) then
            return 'Cuirasses', 'torse tunique plastron cuirasse'
        elseif loc == 'INVTYPE_LEGS' or hasAny(s, { 'jambiere', 'pantalon', 'kilt', 'culotte', 'braies', 'jambard', 'legging', 'pants', 'breeches', 'legplate', 'legguard' }) then
            return 'Pantalons', 'jambes pantalon jambieres'
        elseif loc == 'INVTYPE_HAND' or hasAny(s, { 'gant', 'gantelet', 'moufle', 'mains', 'poigne', 'glove', 'gauntlet', 'mitt', 'hand', 'fist' }) then
            return 'Gants', 'gants gantelets mains'
        elseif loc == 'INVTYPE_FEET' or hasAny(s, { 'botte', 'sandale', 'mocassin', 'chaussure', 'brodequin', 'soleret', 'boot', 'sandal', 'moccasin', 'shoe', 'tread', 'greave', 'footpad' }) then
            return 'Bottes', 'bottes pieds sandales'
        elseif loc == 'INVTYPE_WRIST' or hasAny(s, { 'brassard', 'bracelet', 'poignet', 'garde-poignet', 'manchette', 'bracer', 'wrist', 'binding', 'armguard', 'cuff' }) then
            return 'Bracelets', 'bracelets brassards poignets'
        elseif loc == 'INVTYPE_WAIST' or hasAny(s, { 'ceinture', 'cordon', 'sangle', 'ceinturon', 'baudrier', 'belt', 'girdle', 'cord', 'waist', 'cinch' }) then
            return 'Ceintures', 'ceinture taille'
        elseif loc == 'INVTYPE_CLOAK' or hasAny(s, { 'cape', 'manteau', 'drape', 'voile', 'peau d\'ombre', 'cloak', 'shawl', 'hide of the wild', 'shifting cloak' }) then
            return 'Capes', 'cape dos manteau'
        end
        return 'Matériaux', 'peau cuir ecaille sel'
    elseif pkey == 'engineering' then
        if hasAny(s, { 'bombe', 'dynamite', 'grenade', 'charge', 'sapeur', 'mouton explosif', 'leurre', 'mine', 'mortier', 'fusee', 'feu d\'artifice', 'detonateur', 'petard', 'bomb', 'sapper', 'explosive', 'dummy', 'mortar', 'firework', 'rocket', 'land mine' }) then
            return 'Explosifs', 'explosif bombe dynamite grenade sapeur'
        elseif loc == 'INVTYPE_AMMO' or hasAny(s, { 'balle', 'fleche', 'cartouche', 'projectile', 'obus', 'shot', 'shell', 'bullet', 'arrow', 'ammo' }) then
            return 'Munitions', 'munition balle fleche cartouche projectile'
        elseif hasAny(s, { 'lunette de visee', 'lunette ', 'viseur', 'scope' }) then
            return 'Lunettes de visée', 'lunette viseur scope'
        elseif loc == 'INVTYPE_RANGED' or loc == 'INVTYPE_RANGEDRIGHT' or hasAny(s, { 'carabine', 'fusil', 'tromblon', 'arc', 'canon', 'rifle', 'gun', 'blunderbuss', 'bow' }) then
            return 'Armes à feu et arcs', 'arme fusil carabine arc'
        elseif loc == 'INVTYPE_HEAD' or hasAny(s, { 'lunettes', 'monocle', 'casque', 'heaume', 'chapeau', 'goggles', 'lens', 'helm', 'hat' }) then
            return 'Lunettes', 'lunettes casque tete'
        elseif loc == 'INVTYPE_TRINKET' or hasAny(s, { 'bijou', 'deflecteur', 'reflecteur', 'teleporteur', 'transporteur', 'rayon', 'coq', 'dragon', 'ecureuil', 'agrandisseur', 'generateur', 'trinket', 'reflector', 'deflector', 'teleporter', 'transporter', 'ripper', 'ray', 'dragonling', 'chicken', 'squirrel', 'enlarger' }) then
            return 'Bijoux', 'bijou trinket teleporteur deflecteur'
        elseif hasAny(s, { 'cables', 'defibrillateur', 'robot', 'recolteur', 'couteau', 'serrure', 'filet', 'discombobulateur', 'ceinture', 'bottes', 'cape', 'parachute', 'bouclier', 'jumper', 'bot', 'harvester', 'knife', 'lock', 'net-o-matic', 'belt', 'boots', 'cloak', 'shield' }) then
            return 'Appareils', 'appareil gadget robot cables bottes ceinture'
        end
        return 'Pièces', 'piece tube vis boulon poudre rouage'
    elseif pkey == 'cooking' then
        if hasAny(s, { 'the ', 'the d', 'biere', 'rhum', 'vin ', 'cidre', 'grog', 'infusion', 'boisson', 'tea', 'ale', 'rum', 'wine', 'brew', 'cider', 'drink' }) then
            return 'Boissons', 'boisson the biere rhum'
        elseif hasAny(s, { 'poisson', 'saumon', 'calmar', 'thon', 'truite', 'vivaneau', 'lutjan', 'murene', 'barracuda', 'palourde', 'crabe', 'homard', 'crevette', 'anchois', 'maquereau', 'perche', 'rouget', 'friture', 'filet de', 'nage de', 'deviant', 'fish', 'salmon', 'squid', 'tuna', 'trout', 'catfish', 'snapper', 'eel', 'clam', 'crab', 'lobster', 'shrimp', 'mackerel', 'redgill', 'mightfish', 'sunscale', 'nightfin', 'chowder', 'bisque' }) then
            return 'Poissons', 'poisson calmar saumon palourde'
        elseif hasAny(s, { 'biscuit', 'pain', 'gateau', 'tarte', 'tourte', 'cookie', 'gingerbread', 'bread', 'cake' }) then
            return 'Desserts et pains', 'pain dessert biscuit tourte'
        end
        return 'Viandes', 'viande ragout steak cotelettes chili saucisse omelette'
    elseif pkey == 'firstaid' then
        if hasAny(s, { 'venin', 'antivenin', 'poison', 'venom' }) then
            return 'Antivenins', 'antivenin poison'
        end
        return 'Bandages', 'bandage soin'
    elseif pkey == 'mining' then
        return 'Fonte', 'fonte barre lingot'
    end

    return 'Divers', ''
end

function Q.ItemCrafters(itemID)
    if not cache or revision~=Q.revision then
        cache={};revision=Q.revision
        for key,c in pairs(QuinteCraftDB.characters) do
            local seen={}
            for _,p in pairs(c.professions or {}) do for _,r in ipairs(p.recipes or {}) do
                if r.item and not seen[r.item] then
                    seen[r.item]=true;cache[r.item]=cache[r.item] or {};cache[r.item][#cache[r.item]+1]=key
                end
            end end
        end
        for _,names in pairs(cache) do table.sort(names) end
    end
    return cache[itemID] or {}
end
function Q.Colored(key)
    local c=QuinteCraftDB.characters[key]
    local color=c and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[c.class]
    local hex=color and color.colorStr
    if not hex or not hex:match('^%x%x%x%x%x%x%x%x$') then hex='ffffffff' end
    -- Nom sans royaume sur WoW Forever (royaumes cachés), comme dans la fenêtre
    return '|c'..hex..Q.Safe(Quintessence.DisplayName(key))..'|r'
end
function Q.Online(key)
    if key==Q.Key() then return true end
    local row=Q.sync and Q.sync.roster[LibStub('LibQuinteSync-1.0').CanonicalKey(key)]
    return row and row.online or false
end
-- Recherche dans le chat : même index que la fenêtre (déjà catégorisé et normalisé) au lieu de recatégoriser chaque
-- recette de chaque artisan (40 artisans × 500 recettes : 290 ms de gel à chaque /qcraft chat).
function Q.Search(query)
    local ordered=Q.UI.Filter(nil,query)
    if #ordered==0 then return Q.Print('Aucune recette correspondante dans les relevés. Ouvre tes métiers pour les collecter.') end
    Q.Print(#ordered..' recette(s) correspondante(s).')
    for i=1,math.min(40,#ordered) do
        local r=ordered[i];local display={}
        for _,who in ipairs(r.crafters) do display[#display+1]=Q.Colored(who.key)..(Q.Online(who.key) and ' (en ligne)' or ' (hors ligne)') end
        Q.Print(Q.Safe(r.name)..(r.category and (' ['..Q.Safe(r.category)..']') or '')..' : '..table.concat(display,', '))
    end
    if #ordered>40 then Q.Print('Affichage limité à 40 recettes : précise la recherche.') end
end
function Q.Summary()
    local own,remote,recipes=0,0,0
    for _,c in pairs(QuinteCraftDB.characters) do
        if c.source=='self' then own=own+1 else remote=remote+1 end
        for _,p in pairs(c.professions or {}) do recipes=recipes+#(p.recipes or {}) end
    end
    Q.Print(own..' perso(s) locaux, '..remote..' synchronisé(s), '..recipes..' recette(s) apprises au total.')
    if Q.sync then
        local state=Q.sync:Status()
        Q.Print('Synchro '..(state.enabled and 'on' or 'off')..' ; file '..state.queued..' ; report '..state.deferred..'.')
    else Q.Print('Synchro indisponible : voir /qcraft debug.') end
    Q.Print('Fais /reload puis envoie WTF/Account/<COMPTE>/SavedVariables/quinte-craft.lua sur la page Importer du site.')
end
