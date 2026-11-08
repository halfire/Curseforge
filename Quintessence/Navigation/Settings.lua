local _, Core = ...
local N, S = Core.Navigation, Core.Style
local panel, buttons
local rows = {
    { 'enabled', 'Activer le guidage', 'Couper arrête aussi le trajet en cours.' },
    { 'automatic', 'Démarrage automatique', 'Sur un marqueur natif ; sinon, bouton Chemin.' },
    { 'worldMap', 'Chemin sur la grande carte', 'Tracé et destination du voyage.' },
    { 'minimap', 'Chemin sur la minicarte', 'Tracé du passage en cours.' },
    { 'arrow', 'Flèche et distance', 'Direction du prochain passage.' },
    { 'compass', 'Boussole de voyage', 'Orientation affichée en haut de l’écran.' },
    { 'steps', 'Liste des étapes', 'Résumé du trajet dans le suivi des objectifs.' },
    { 'destination', 'Repère à l’écran', 'Marqueur visible dans le monde.' },
    { 'transportPins', 'Icônes de transport', 'Bateaux, portails et maîtres de vol.' },
    { 'transportTimes', 'Horaires des transports', 'Départs à proximité dans le suivi.' },
    { 'alerts', 'Alertes de voyage', 'Arrivées des bateaux et nouveaux maîtres de vol.' },
    { 'sound', 'Sons de voyage', 'Alertes et arrivée à destination.' },
}
function N.RefreshSettings()
    if not panel then return end
    local prefs = N.Options()
    for key, button in pairs(buttons) do
        button:SetLabel(prefs[key] and 'Activé' or 'Désactivé')
        button:SetActive(prefs[key])
    end
    panel.state:SetText(prefs.enabled and 'Guidage actif · affichage personnalisable' or 'Guidage désactivé · les marqueurs restent disponibles')
end
local function create(parent)
    panel = CreateFrame('Frame', nil, parent)
    panel:SetSize(1078, 658) -- toute la zone de contenu (1.39.0), textes de la même taille
    buttons = {}
    local title = S.Text(panel, 20, S.colors.text); title:SetPoint('TOPLEFT', 0, -2); title:SetText('Réglages — Voyages')
    local hint = S.Text(panel, 12, S.colors.muted); hint:SetPoint('TOPLEFT', 0, -32); hint:SetWidth(1068); hint:SetWordWrap(true)
    hint:SetText('Choisis les informations visibles. Les changements s’appliquent immédiatement et restent enregistrés.')
    panel.state = S.Text(panel, 12, S.colors.gold); panel.state:SetPoint('TOPLEFT', 0, -72)
    local stop = S.Button(panel, 'Arrêter le trajet', 140, 26, 'ghost'); stop:SetPoint('TOPRIGHT', 0, -65)
    stop:SetScript('OnClick', function() N.Clear(); Core.Print('Guidage Quintessence arrêté.') end)
    for i, row in ipairs(rows) do
        local key = row[1]
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local box = S.Box(panel, S.colors.panel, S.colors.line)
        box:SetSize(532, 46); box:SetPoint('TOPLEFT', col * 546, -110 - line * 52)
        local label = S.Text(box, 12, S.colors.text); label:SetPoint('TOPLEFT', 10, -8); label:SetWidth(410); label:SetText(row[2])
        local help = S.Text(box, 10, S.colors.muted); help:SetPoint('TOPLEFT', 10, -26); help:SetWidth(512); help:SetText(row[3])
        local toggle = S.Button(box, '', 90, 22, 'ghost'); toggle:SetPoint('TOPRIGHT', -8, -4)
        toggle:SetScript('OnClick', function() N.SetOption(key, not N.Options()[key]) end)
        buttons[key] = toggle
    end
    local note = S.Text(panel, 11, S.colors.muted); note:SetPoint('TOPLEFT', 0, -438); note:SetWidth(1068); note:SetWordWrap(true)
    note:SetText('Chemin utilise les passages du terrain. Bateaux, vols et portails peuvent faire partie du trajet même si leurs icônes sont masquées. Moteur Shortest Path Forever, de cjber, intégré à Quintessence (GPL).')
    N.RefreshSettings()
    return panel
end
Core:RegisterModule({ id = 'settings', title = 'Réglages', order = 98,
    icon = 'Interface\\Icons\\Trade_Engineering', width = 1078, height = 658,
    create = create, refresh = N.RefreshSettings, summary = function() return 'Voyages : affichage, activation et démarrage automatique.' end })
