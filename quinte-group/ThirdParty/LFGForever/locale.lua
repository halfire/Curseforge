-- QuinteLFG -- core/locale.lua
--
-- Every word LFG Forever shows, by key, in English -- and the one place a
-- LANGUAGE PACK can replace them. The first file the .toc loads, so by the time
-- any other file runs, LFGF.L already holds the words it should show.
--
-- A LANGUAGE PACK is a separate addon, LoadOnDemand, whose TOC carries
--   ## X-QuinteLFG-LanguagePack: 1
--   ## AllowAddOnTableAccess: 1
-- and whose only file fills its OWN addon table (the second vararg every file
-- gets) with { api = 1, language = "...", strings = { KEY = "...", ... } }.
-- This file walks the addon list, loads the FIRST such addon that works, reads
-- that table back, and copies each string it accepts over the English one.
-- Enabling or disabling the pack in the AddOns list is the language switch;
-- with no pack, nothing here changes a word. .claude/rules/language-packs.md
--
-- NOT HERE, by the author's decisions: the whisper text sent to other players
-- (the two default messages, the class and talent words, the "or" joiner; all
-- in core/main.lua and core/talents.lua), which stays English whatever the
-- pack; the %class%-style placeholders; the name "LFG Forever"; and anything
-- the game itself names -- dungeons, zones, categories, playstyles.
local addonName, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end

--- The client's own string, so a German client keeps Blizzard's German for
--- these words when no pack is installed, as it always did; the English is
--- only for a client that lacks the global. Read once, here: GlobalStrings
--- are loaded before any addon file runs, and never change after.
local function Blizzard(globalName, english)
	local value = GetLocale and GetLocale() == "frFR" and _G[globalName]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return english
end

--- A class's name the way the client says it -- LOCALIZED_CLASS_NAMES_MALE,
--- built by Blizzard_FrameXMLBase/Constants.lua:37 before any addon loads --
--- with the English behind it.
local function ClassName(token, english)
	local names = LOCALIZED_CLASS_NAMES_MALE
	local value = type(names) == "table" and names[token]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return english
end

-- KEY RULES (a spec holds the code to them):
--   * a key whose value is passed to string.format / SetFormattedText ends in
--     _FORMAT, and only those do -- what a pack's value is checked against;
--   * a key is never reused with a new meaning: change the English meaning,
--     change the key, so an older pack falls back to English instead of
--     showing the wrong words.
local L = {
	-- core/main.lua
	COMBAT_SETTINGS = "Les réglages sont indisponibles en combat.",
	LOADED_VERSION_FORMAT = "%s %s chargé. Tape %s.",
	LOADED_FORMAT = "%s chargé. Tape %s.",
	-- core/relations.lua
	RELATION_GUILD = Blizzard("LFG_LIST_GUILD_MEMBER", "Membre de la guilde"),
	RELATION_FRIEND = Blizzard("LFG_LIST_FRIEND", "Ami"),

	-- core/settings.lua. A *_LABEL here is a Settings row label: one line, no
	-- wrap, about 28 characters (Blizzard_SettingControls.lua:338-341).
	SETTINGS_WHISPER_LOG_SIZE_LABEL = "Taille du journal MP",
	SETTINGS_WHISPER_LOG_SIZE_TOOLTIP = "Nombre de chuchotements reçus à garder. Les plus anciens sont retirés en premier.",
	SETTINGS_ASK_TO_JOIN_AUTO_WHISPER_LABEL = "Message de demande",
	SETTINGS_ASK_TO_JOIN_AUTO_WHISPER_TOOLTIP = "Envoie ton message au chef du groupe au clic. Si désactivé, ouvre la saisie d’un chuchotement.",
	SETTINGS_ASK_TO_JOIN_MESSAGE_LABEL = "Message",
	SETTINGS_ASK_TO_JOIN_MESSAGE_TOOLTIP = "%class% et %level% indiquent ta classe et ton niveau. %talents% indique ton arbre de talents principal, %role% tes rôles choisis dans le jeu. 200 caractères au plus, par personnage.",
	-- The "?" beside each message box: a title, then one bulleted line per
	-- keyword, "<keyword> - <description>". Only the description is here: the
	-- keyword, its colour and the bullet are added by core/settings.lua.
	SETTINGS_PLACEHOLDERS_TITLE = "Variables de message",
	SETTINGS_PLACEHOLDER_CLASS = "ta classe",
	SETTINGS_PLACEHOLDER_LEVEL = "ton niveau",
	SETTINGS_PLACEHOLDER_TALENTS = "ton arbre de talents principal",
	SETTINGS_PLACEHOLDER_ROLE = "les rôles choisis dans le Cherche-groupe du jeu",
	SETTINGS_PLACEHOLDER_DUNGEON = "les activités de ton annonce ou du filtre, dans la langue du jeu",
	SETTINGS_PLACEHOLDER_DUNGEON_EN = "les mêmes noms de donjons et de raids, en anglais",
	SETTINGS_INVITE_AUTO_WHISPER_LABEL = "Message d’invitation",
	SETTINGS_INVITE_AUTO_WHISPER_TOOLTIP = "Envoie ton message en plus de l’invitation au clic.",
	SETTINGS_INVITE_MESSAGE_LABEL = "Message",
	SETTINGS_INVITE_MESSAGE_TOOLTIP = "%dungeon% reprend les activités de ton annonce ou du filtre, dans la langue du jeu. %dungeon_en% reprend leurs noms en anglais. 200 caractères au plus, par personnage.",
	SETTINGS_SEARCH_HEADER = "Recherche",
	SETTINGS_SHOW_ALL_LEVELS_LABEL = "Activités de tous niveaux",
	SETTINGS_SHOW_ALL_LEVELS_TOOLTIP = "Affiche toutes les activités, y compris celles hors de ta tranche de niveau.",
	SETTINGS_SHOW_LEVEL_RANGES_LABEL = "Tranches de niveau",
	SETTINGS_SHOW_LEVEL_RANGES_TOOLTIP = "Affiche la tranche conseillée après le nom de chaque activité.",
	SETTINGS_MARK_GUILDMATES_LABEL = "Membres de la guilde",
	SETTINGS_MARK_GUILDMATES_TOOLTIP = "Place les membres de ta guilde en haut de la liste et ajoute une icône.",
	SETTINGS_MARK_FRIENDS_LABEL = "Amis",
	SETTINGS_MARK_FRIENDS_TOOLTIP = "Place tes amis WoW et Battle.net en haut de la liste et ajoute une icône.",
	-- "Sort players by", the last row of Search: a dropdown whose tooltip adds
	-- one "<name>: <line>" per order (Blizzard_Settings.lua:416-496). Keep each
	-- name short: the dropdown is 220 wide (Blizzard_SettingControls.lua:818).
	SETTINGS_PLAYER_SORT_LABEL = "Trier les joueurs par",
	SETTINGS_PLAYER_SORT_PARTS_TOOLTIP = "L’ordre s’applique au sein de chaque groupe de la liste. Ton annonce reste en premier.",
	PLAYER_SORT_NEWEST = "Annonces récentes",
	PLAYER_SORT_NEWEST_TOOLTIP = "Les annonces les plus récentes en premier.",
	PLAYER_SORT_OLDEST = "Annonces anciennes",
	PLAYER_SORT_OLDEST_TOOLTIP = "Les annonces les plus anciennes en premier.",
	PLAYER_SORT_LEVEL_HIGH = "Niveau décroissant",
	PLAYER_SORT_LEVEL_HIGH_TOOLTIP = "Les niveaux les plus élevés en premier.",
	PLAYER_SORT_LEVEL_LOW = "Niveau croissant",
	PLAYER_SORT_LEVEL_LOW_TOOLTIP = "Les niveaux les plus bas en premier.",
	PLAYER_SORT_CLASS = Blizzard("CLASS", "Classe"),
	PLAYER_SORT_CLASS_TOOLTIP = "Annonces regroupées par classe.",
	-- The key binding's label, on Blizzard's Keybindings page (core/slash.lua)
	-- and on the key binding row of LFG Forever's page. The key opens and
	-- closes it. The row's button opens Blizzard's Keybindings page.
	BINDING_OPEN_WINDOW = "Ouvrir la recherche de groupe",
	KEYBINDINGS = Blizzard("SETTINGS_KEYBINDINGS_LABEL", "Raccourcis"),
	SETTINGS_KEYBINDING_TOOLTIP = "Configure la touche dans le menu des raccourcis du jeu.",
	-- "Player ratings", the second row of Miscellaneous: one key for the row's
	-- label and the tab's title (core/playerratings.lua), so the two read alike.
	PLAYER_RATINGS = "Avis sur les joueurs",
	SETTINGS_PLAYER_RATINGS_TOOLTIP = "Note tes alliés récents pour retrouver les joueurs avec qui tu veux rejouer.",
	SETTINGS_MINIMAP_BUTTON_LABEL = "Bouton de minicarte",
	SETTINGS_MINIMAP_BUTTON_TOOLTIP = "Affiche un bouton déplaçable sur le bord de la minicarte. /qlfg ouvre aussi la fenêtre.",
	-- The settings page's sentence above Report a bug. %s is a language
	-- pack's exact title, which stays English; the quote marks around it are
	-- the translation's.
	SETTINGS_LANGUAGE_PACKS_FORMAT = "Exemple de pack de langue facultatif de LFG Forever sur CurseForge : « %s ».",
	SETTINGS_REPORT_BUG_LABEL = "Une erreur ou une idée ?",
	SETTINGS_REPORT_BUG_TOOLTIP = "Ouvre le lien Discord de l’auteur.",
	REPORT_BUG_POPUP_TEXT = "Copie le lien avec Ctrl+C ou Cmd+C, puis colle-le dans ton navigateur.",
	-- The window header's Report a bug, beside Blizzard's bug icon. Its
	-- tooltip is the two sentences above.
	REPORT_BUG = "Signaler une erreur",
	SETTINGS_RESET_WINDOW_LABEL = "Position et taille",
	SETTINGS_RESET_WINDOW_TOOLTIP = "Rétablit la taille et la position d’origine de la fenêtre.",
	MISCELLANEOUS = Blizzard("MISCELLANEOUS", "Divers"),
	RESET = Blizzard("RESET", "Réinitialiser"),
	CLOSE = Blizzard("CLOSE", "Fermer"),

	-- core/listpanel.lua
	ASK_TO_JOIN = "Demander à rejoindre",
	-- The same button's tooltip once the group was asked this session.
	ASK_TO_JOIN_AGAIN = "Redemander à rejoindre",
	GROUP_INVITE = Blizzard("GROUP_INVITE", "Inviter dans le groupe"),
	LEVEL_ABBR = Blizzard("LEVEL_ABBR", "Niv."),
	ACTIVITY_COUNT_FORMAT = Blizzard("LFGBROWSE_ACTIVITY_COUNT", "%d |4activité:activités;"),
	SEARCHING = Blizzard("SEARCHING", "Recherche en cours…"),
	LIST_DIVIDER_PLAYERS = Blizzard("LFG_LIST_CATEGORY_SOLO_PLAYERS", "Joueurs"),
	LIST_DIVIDER_GROUPS = Blizzard("LFG_LIST_CATEGORY_GROUPS", "Groupes"),
	-- The tooltip of each box's header: what a click on it does.
	LIST_COLLAPSE_GROUPS = "Replier les groupes",
	LIST_COLLAPSE_PLAYERS = "Replier les joueurs",
	LIST_EXPAND_GROUPS = "Déplier les groupes",
	LIST_EXPAND_PLAYERS = "Déplier les joueurs",
	NO_RESULTS = Blizzard("LFG_LIST_NO_RESULTS_FOUND",
		"Aucune annonce trouvée."),
	SEARCH_FAILED = Blizzard("LFG_LIST_SEARCH_FAILED",
		"La recherche a échoué."),

	-- core/whisperlog.lua
	WHISPERS_TAB_TITLE = "Chuchotements",
	WHISPERS_SECTION_TITLE = "Messages reçus",
	LOCATION = "Localisation",
	NO_WHISPERS = "Aucun chuchotement reçu.",
	REMOVE = Blizzard("REMOVE", "Retirer"),
	INVITE = Blizzard("INVITE", "Inviter"),
	CONTINUED = Blizzard("CONTINUED", "..."),

	-- core/playerratings.lua: the Player ratings tab's one section, its notices,
	-- the "<time> ago" of a row's second line, and the words of Blizzard's own
	-- Recent Allies tooltip (Blizzard_RecentAlliesTemplates.lua:153-225), all
	-- Blizzard's. The two tab names in the not-ready sentence are Blizzard's too,
	-- so a client keeps its own words.
	RECENT_ALLIES_SECTION_TITLE = "Alliés récents",
	NO_RECENT_ALLIES = "Aucun allié récent.",
	RECENT_ALLIES_UNAVAILABLE = "Les alliés récents sont indisponibles.",
	RECENT_ALLIES_NOT_READY_FORMAT = "Ouvre %s puis %s pour charger tes alliés.",
	FRIENDS = Blizzard("FRIENDS", "Amis"),
	RECENT_ALLIES = Blizzard("CONTACTS_RECENT_ALLIES_TAB_NAME", "Alliés récents"),
	RECENT_ACTIVITIES = Blizzard("RECENT_ALLY_RECENT_ACTIVITIES_LABEL", "Activités récentes"),
	RECENT_ALLY_TIME_FORMAT = Blizzard("RECENT_ALLY_INTERACTION_TIME_FORMAT", "Il y a %s"),
	RECENT_ALLY_LEVEL_RACE_FORMAT = Blizzard("RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT", "Niveau %d  %s  %s"),
	RECENT_ALLY_NOTE_FORMAT = Blizzard("RECENT_ALLY_NOTE_FORMAT",
		"|TInterface\\FriendsFrame\\UI-FriendsFrame-Note:0:0:0:0:1:1:0:1:0:1:255:209:0|t %s"),
	-- A player from LFG Forever's own list of the last party members
	-- (core/recentparty.lua) on top of the tab: the activity on their second
	-- line and in their tooltip, worded like the server's "Fought Together" (the
	-- author's choice), and the tooltip's level line, Blizzard's.
	PARTY_MEMBER_ACTIVITY = "Dans ton groupe",
	PARTY_MEMBER_LEVEL_FORMAT = Blizzard("UNIT_LEVEL_TEMPLATE", "Niveau %d"),
	-- The chat line printed after "LFG Forever: " when a player you rated 1
	-- star joins your party (core/recentparty.lua), the author's wording. The
	-- first %s is the player's name (in red), the second the gold star icon,
	-- which comes right after "1 star".
	PARTY_ONE_STAR_JOINED_FORMAT = "%s a rejoint ton groupe. Tu lui as donné 1 étoile %s.",
	-- The rating stars' tooltip, the author's wording (option A of six): the
	-- sentence comes first and is drawn as the tooltip's title, then one line
	-- per rating, each a key of its own.
	PLAYER_RATING_MARKED = "Les joueurs notés sont signalés en rouge, argent ou vert dans les annonces et les chuchotements.",
	PLAYER_RATING_ONE_STAR_LINE = "1 étoile - Je préfère éviter ce joueur",
	PLAYER_RATING_TWO_STARS_LINE = "2 étoiles - Je peux jouer avec ce joueur",
	PLAYER_RATING_THREE_STARS_LINE = "3 étoiles - Je veux rejouer avec ce joueur",
	-- Clear player rating: the link at the right end of the Recent allies
	-- title line, the popup it opens (the label above the box, and the two
	-- reasons its Okay is off, after the link's words as the tooltip's title)
	-- and the chat line printed after "LFG Forever: " once a rating is
	-- cleared. Each %s is the player's name as the rating is saved under it.
	CLEAR_PLAYER_RATING = "Effacer un avis",
	CLEAR_PLAYER_RATING_PROMPT = "Saisis le nom du personnage.",
	CLEAR_PLAYER_RATING_EMPTY = "Saisis un nom de personnage.",
	CLEAR_PLAYER_RATING_UNKNOWN_FORMAT = "Aucun avis enregistré pour « %s ».",
	PLAYER_RATING_CLEARED_FORMAT = "Avis sur « %s » effacé.",
	-- core/rateleavers.lua: the chat line posted after players leave your party,
	-- the author's wording. %s is the link, whose words are the second key; a
	-- click opens the Player ratings tab. The third is printed after
	-- "LFG Forever: " when the link is clicked while Player ratings is off, and
	-- its %s is PLAYER_RATINGS.
	RATE_LEAVERS_FORMAT = "Des joueurs ont quitté ton groupe. Veux-tu donner ton avis ? %s",
	RATE_LEAVERS_LINK = "Donner un avis",
	RATE_LEAVERS_TURNED_OFF_FORMAT = "Active « %s » dans les réglages pour noter les joueurs.",
	-- core/filterpanel.lua
	ROLE_SECTION_TITLE = "Joueurs par rôle et niveau",
	CLASS_SECTION_TITLE = "Joueurs par classe",
	GROUP_SECTION_TITLE = "Groupes par composition",
	-- core/filterpanel_shared.lua: the tooltip of the warning a collapsed
	-- section shows while its filters are not at their defaults.
	COLLAPSED_FILTERS_TITLE = "Filtres actifs",
	COLLAPSED_FILTERS_TOOLTIP = "Les filtres de cette section restent actifs quand elle est repliée.",
	FILTERS_TAB_TITLE = "Filtres",
	RESET_FILTERS = "Réinitialiser les filtres",
	-- The class filter's two links, and the Languages menu's first two rows
	-- (core/filterpanel_miscellaneous.lua), so the panel says it one way.
	UNSELECT_ALL = "Tout décocher",
	SELECT_ALL = "Tout cocher",
	CLEAR_CHAT = "Effacer les messages",
	LEVEL_RANGE_LABEL = "Niveau des joueurs",
	MY_FILTERS = "Mes filtres",
	SAVE_NEW_FILTER = "Enregistrer un filtre",
	-- core/filterpanel_miscellaneous.lua: the Playstyle row. Its label is
	-- Blizzard's own over the retail filter's playstyles
	-- (Blizzard_GroupFinder/Mainline/LFGList.lua:2675); the dropdown says ALL
	-- when every playstyle is ticked or none is, the one name when one is, and
	-- the count otherwise. The names themselves stay the game's
	-- (GetGeneralPlaystyleString), as on the list rows.
	PLAYSTYLE_ROW_LABEL = Blizzard("GROUP_FINDER_FILTER_PLAYSTYLE", "Style de jeu"),
	PLAYSTYLE_ALL = Blizzard("ALL", "Tous"),
	PLAYSTYLES_SELECTED_FORMAT = "%d sélectionnés",
	-- core/filterpanel_miscellaneous.lua: the Languages row, flush right on the
	-- Playstyle row. The label is Blizzard's own over its retail language menu
	-- (Blizzard_GroupFinder/Mainline/LFGList.lua:2686); its two bulk rows are
	-- the class filter's Select all and Unselect all, above. The dropdown names
	-- the one language ticked (by default, the player's own), says ALL when
	-- every one is, and the count otherwise.
	LANGUAGES_ROW_LABEL = Blizzard("LANGUAGES_LABEL", "Langues"),
	LANGUAGES_ALL = Blizzard("ALL", "Toutes"),
	LANGUAGES_SELECTED_FORMAT = "%d sélectionnées",
	-- On a locked row of the menu, under the language's name.
	LANGUAGE_LOCKED_BY_BLIZZARD_TOOLTIP = "WoW inclut toujours cette langue dans les recherches.",
	-- A greyed-out row, alone after the bulk rows, when the game offers none.
	LANGUAGES_NONE_AVAILABLE = "Aucune langue disponible.",
	-- Read by code, L["LANGUAGE_NAME_" .. string.upper(code)]: one per locale
	-- the WowLocale structure holds (LFGListInfoDocumentation.lua:1045-1060).
	-- Blizzard's retail language names (LFG_LIST_LANGUAGE_*), except for the
	-- two pairs those name alike: Chinese takes the names
	-- LocaleUtil.GetLocaleDisplayName prefers (LOCALE_DISPLAY_NAME_*,
	-- Blizzard_SharedXMLBase/LocaleUtil.lua:12-24), Spanish the client's ESES
	-- and ESMX.
	LANGUAGE_NAME_DEDE = Blizzard("LFG_LIST_LANGUAGE_DEDE", "Allemand"),
	LANGUAGE_NAME_ENUS = Blizzard("LFG_LIST_LANGUAGE_ENUS", "Anglais"),
	LANGUAGE_NAME_ESES = Blizzard("ESES", "Espagnol (Europe)"),
	LANGUAGE_NAME_ESMX = Blizzard("ESMX", "Espagnol (Amérique latine)"),
	LANGUAGE_NAME_FRFR = Blizzard("LFG_LIST_LANGUAGE_FRFR", "Français"),
	LANGUAGE_NAME_ITIT = Blizzard("LFG_LIST_LANGUAGE_ITIT", "Italien"),
	LANGUAGE_NAME_KOKR = Blizzard("LFG_LIST_LANGUAGE_KOKR", "Coréen"),
	LANGUAGE_NAME_PTBR = Blizzard("LFG_LIST_LANGUAGE_PTBR", "Portugais"),
	LANGUAGE_NAME_RURU = Blizzard("LFG_LIST_LANGUAGE_RURU", "Russe"),
	LANGUAGE_NAME_ZHCN = Blizzard("LOCALE_DISPLAY_NAME_ZHCN", "Chinois simplifié"),
	LANGUAGE_NAME_ZHTW = Blizzard("LOCALE_DISPLAY_NAME_ZHTW", "Chinois traditionnel"),
	ROLE_TANK = Blizzard("TANK", "Tank"),
	ROLE_HEALER = Blizzard("HEALER", "Soigneur"),
	ROLE_DAMAGE = Blizzard("DAMAGER", "DPS"),
	-- Read by token, L["CLASS_" .. classFilename]: the camelot nine
	-- (CLASS_SORT_ORDER, Camelot/Constants.lua:1-11).
	CLASS_WARRIOR = ClassName("WARRIOR", "Guerrier"),
	CLASS_PALADIN = ClassName("PALADIN", "Paladin"),
	CLASS_HUNTER = ClassName("HUNTER", "Chasseur"),
	CLASS_ROGUE = ClassName("ROGUE", "Voleur"),
	CLASS_PRIEST = ClassName("PRIEST", "Prêtre"),
	CLASS_SHAMAN = ClassName("SHAMAN", "Chaman"),
	CLASS_MAGE = ClassName("MAGE", "Mage"),
	CLASS_WARLOCK = ClassName("WARLOCK", "Démoniste"),
	CLASS_DRUID = ClassName("DRUID", "Druide"),
	GROUP_TANK_AVAILABLE = "Place pour un tank",
	GROUP_HEALER_AVAILABLE = "Place pour un soigneur",
	GROUP_DAMAGE_AVAILABLE = "Place pour un DPS",
	GROUP_HAS_TANK = "Tank présent",
	GROUP_HAS_HEALER = "Soigneur présent",
	-- core/filterpanel_groupclasses.lua: the Groups section's class filter, a
	-- dropdown with no label of its own, so its text says what it does. NONE
	-- while it hides nothing (no class selected, or every class), then the one
	-- class in the plural, then the count from two on. Three dots, never the
	-- one-character ellipsis: Blizzard's English strings use "..." and never
	-- that glyph, which the game font may lack.
	GROUP_CLASSES_NONE = "Exclure des classes",
	GROUP_CLASSES_ONE_FORMAT = "Sans %s",
	GROUP_CLASSES_COUNT_FORMAT = "Sans %d classes",
	-- Its tooltip, one short plain sentence (players found a longer one hard
	-- to read): the rule while it hides nothing, and the same sentence with the
	-- classes it hides by, each in its class colour, joined "A, B or C" with
	-- the two separators below (a translator picks the words for this sentence:
	-- "ni", "i", "a", ...).
	GROUP_CLASSES_TOOLTIP = "Affiche les groupes sans les classes choisies.",
	GROUP_CLASSES_EXCLUDED_TOOLTIP_FORMAT = "Affiche les groupes sans %s.",
	GROUP_CLASSES_LIST_SEPARATOR = ", ",
	GROUP_CLASSES_LIST_LAST_SEPARATOR = " ou ",
	-- Read by token, L["CLASS_PLURAL_" .. classFilename]: each class in the
	-- plural, as it follows "No" in the two texts above ("No Paladins", "no
	-- Druids, Mages or Warlocks"). A language that changes a noun after "no"
	-- writes that form here. Ours, not the client's: it has no plural names.
	CLASS_PLURAL_WARRIOR = "guerriers",
	CLASS_PLURAL_PALADIN = "paladins",
	CLASS_PLURAL_HUNTER = "chasseurs",
	CLASS_PLURAL_ROGUE = "voleurs",
	CLASS_PLURAL_PRIEST = "prêtres",
	CLASS_PLURAL_SHAMAN = "chamans",
	CLASS_PLURAL_MAGE = "mages",
	CLASS_PLURAL_WARLOCK = "démonistes",
	CLASS_PLURAL_DRUID = "druides",
	CATEGORY_NONE = Blizzard("LFG_TYPE_NONE", "Aucune"),
	LEVEL_SINGLE_FORMAT = Blizzard("LFD_LEVEL_FORMAT_SINGLE", "(%d)"),
	LEVEL_RANGE_FORMAT = Blizzard("LFD_LEVEL_FORMAT_RANGE", "(%d - %d)"),
	SEARCH = Blizzard("SEARCH", "Rechercher"),
	-- The Search button's tooltip, Blizzard's refresh button's (Browse.xml:540).
	SEARCH_AGAIN = Blizzard("LFG_LIST_SEARCH_AGAIN", "Relancer la recherche"),
	MY_FILTER_PROMPT = "Choisis un nom pour ton filtre.",
	MY_FILTERS_FULL_FORMAT = "Tu as atteint la limite de %d filtres. Supprimes-en un pour en enregistrer un autre.",
	MY_FILTER_EMPTY = "Saisis un nom de filtre.",
	MY_FILTER_TOO_LONG_FORMAT = "Utilise au plus %d caractères.",
	-- Red, above the popup's box, while the name typed is already saved.
	MY_FILTER_OVERWRITE_WARNING_FORMAT = "Le filtre « %s » existe déjà. Il sera remplacé.",
	-- Chat lines, each printed after "LFG Forever: ".
	MY_FILTER_SAVED_FORMAT = "Filtre « %s » enregistré.",
	MY_FILTER_OVERWRITTEN_FORMAT = "Filtre « %s » remplacé.",
	MY_FILTER_APPLIED_FORMAT = "Filtre « %s » chargé. Clique sur Rechercher pour l’appliquer.",
	MY_FILTER_DELETED_FORMAT = "Filtre « %s » supprimé.",
	OKAY = Blizzard("OKAY", "OK"),
	CANCEL = Blizzard("CANCEL", "Annuler"),
	DELETE = Blizzard("DELETE", "Supprimer"),
	ROLE_CHECK = Blizzard("ROLE_POLL", "Vérifier les rôles"),
	ROLE_CHECK_ONLY_LEADER = Blizzard("ERR_LFG_ROLE_CHECK_ONLY_LEADER",
		"Seul le chef du groupe peut lancer la vérification des rôles."),
	-- The settings gear's tooltip, at the end of the search row.
	SETTINGS = Blizzard("SETTINGS", "Réglages"),
	ACTIVITY_HEADER_DEFAULT = Blizzard("LFGBROWSE_ACTIVITY_HEADER_DEFAULT", "Activités"),
	ACTIVITY_HEADER_FORMAT = Blizzard("LFGBROWSE_ACTIVITY_HEADER", "%d |4activité choisie:activités choisies;"),
	-- A ticked activity the activity menu no longer offers (a level-up, a
	-- listing that ended) is unticked, and ONE line, printed after
	-- "LFG Forever: ", names what was. The last %s is
	-- SETTINGS_SHOW_ALL_LEVELS_LABEL, the setting as its row names it.
	ACTIVITY_NO_LONGER_OFFERED_FORMAT = "%s a été décoché car le jeu ne le propose plus à ton niveau. Pour retrouver %s, active « %s » dans les réglages.",
	ACTIVITIES_NO_LONGER_OFFERED_FORMAT = "Ces activités ont été décochées car le jeu ne les propose plus à ton niveau : %s. Pour les retrouver, active « %s » dans les réglages.",
	-- Two or more names: "A and B", "A, B and C", at most three and then a
	-- count, "A, B, C and 2 more".
	ACTIVITY_LIST_SEPARATOR = ", ",
	ACTIVITY_LIST_LAST_SEPARATOR = " et ",
	ACTIVITY_LIST_MORE_FORMAT = "%d autres",
	CATEGORY = Blizzard("CATEGORY", "Catégorie"),

	-- core/window.lua. COMBAT_WINDOW is printed after "LFG Forever: ".
	COMBAT_WINDOW = "Ouvre le Cherche-groupe après le combat.",
	TAB_CREATE_LISTING = Blizzard("LFG_LIST_TAB_1", "Créer une annonce"),
	TAB_GROUP_BROWSER = Blizzard("LFG_LIST_TAB_2", "Parcourir les groupes"),
	TAB_WHO_LIST = Blizzard("LFG_LIST_TAB_3", "Liste Qui"),

	-- core/minimap.lua
	MINIMAP_LEFT_CLICK = "Clic gauche pour ouvrir ou fermer.",
	MINIMAP_RIGHT_CLICK = "Clic droit pour les réglages.",
	MINIMAP_DRAG = "Fais glisser pour déplacer.",
}
LFGF.L = L

-------------------------------------------------------
---------- Language packs
-------------------------------------------------------

-- The pack table layout this file reads. A pack with another number is
-- skipped, so the layout can change later without an old pack breaking
-- anything: it just shows English.
LFGF.LANGUAGE_PACK_API = 1

-- The TOC field that marks an addon as an LFG Forever language pack. Read with
-- C_AddOns.GetAddOnMetadata, which answers for addons not loaded yet -- the way
-- AtlasLoot Classic reads its LoadOnDemand modules' X- fields on this client.
local PACK_FIELD = "X-LFGForever-LanguagePack"

local function ValidPack(pack)
	return type(pack) == "table" and pack.api == LFGF.LANGUAGE_PACK_API
		and type(pack.strings) == "table"
end

--- Load one pack and return its table, or nil.
---
--- LoadAddOn runs the pack's file NOW, before it returns
--- (AddOnsDocumentation.lua:347-361: loaded, reason). A pack that is disabled,
--- out of date, missing or broken does not load -- false plus a reason, or an
--- error the pcall catches. GetAddOnLocalTable (:149-163) returns the pack's
--- own table only when its TOC opted in with AllowAddOnTableAccess; otherwise
--- it errors, also caught. Every failure is nil, and the caller tries the next.
local function LoadPack(name)
	local ok, loaded = pcall(C_AddOns.LoadAddOn, name)
	if not (ok and loaded) then
		return nil
	end
	local readOk, pack = pcall(C_AddOns.GetAddOnLocalTable, name)
	if readOk and ValidPack(pack) then
		return pack
	end
	return nil
end

--- The FIRST pack in addon-list order that loads and is valid. The search
--- stops there, so a second enabled pack is never even loaded -- it cannot
--- interfere, and costs nothing.
local function FindPack()
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		if name and name ~= addonName then
			local field = C_AddOns.GetAddOnMetadata(name, PACK_FIELD)
			if field and field ~= "" then
				local pack = LoadPack(name)
				if pack then
					return pack
				end
			end
		end
	end
	return nil
end

--- The sorted conversion letters of a format string ("%s ... %d" -> "ds"),
--- or nil when it holds a % that is neither a conversion nor "%%".
local function Conversions(text)
	text = text:gsub("%%%%", "")
	local letters = {}
	for letter in text:gmatch("%%%d*%$?[-+ #0]*%d*%.?%d*(%a)") do
		letters[#letters + 1] = letter
	end
	local _, percents = text:gsub("%%", "")
	if percents ~= #letters then
		return nil
	end
	table.sort(letters)
	return table.concat(letters)
end

--- Whether a pack's value may replace the English one under this key. Built
--- so that nothing a pack holds can make string.format error in this addon.
local function Accepts(key, english, value)
	if type(english) ~= "string" or type(value) ~= "string" or value == "" then
		return false
	end
	if key:sub(-7) == "_FORMAT" then
		-- No positional %2$s: the client's format reads it, but the busted
		-- runtime (stock Lua 5.1) does not, so it could not be tested.
		if value:find("%%%d+%$") then
			return false
		end
		local want = Conversions(english)
		return want ~= nil and Conversions(value) == want
	end
	-- Not a format string: a % only where the English has one -- the
	-- %class%-style placeholders in two Settings tooltips.
	return english:find("%", 1, true) ~= nil or value:find("%", 1, true) == nil
end

local pack = FindPack()
if pack then
	for key, value in pairs(pack.strings) do
		if type(key) == "string" and Accepts(key, L[key], value) then
			L[key] = value
		end
	end
end
