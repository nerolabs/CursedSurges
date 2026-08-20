-- CursedSurges: countdown + waypoint + zone announce for Cursed Surge events
-- on the Coiled Isle (Midnight 12.1).
--
-- Data source: C_EventScheduler (the world map's Events tab). RequestEvents()
-- must be called first; data arrives with EVENT_SCHEDULER_UPDATE.
-- GetScheduledEvents() lists days of entries with epoch startTime/endTime and
-- keeps the currently running one; GetOngoingEvents() entries carry no times.
--
-- The Coiled Isle surge rotation is five 45-minute events cycling back-to-back
-- (observed build 69299): areaPoiIDs 8936-8940 / eventIDs 42-46. Zone lookup
-- (GetEventUiMapID) and poi info (name/position) only resolve while an event
-- is ACTIVE, so we learn each surge's name and fixed location when it runs and
-- cache them in SavedVariables — after one full lap the addon knows all five.

local ADDON_NAME = ...
local VERSION = "1.3.0"
local COILED_ISLE = 2512

local SURGE_BLOCK = 2700  -- scheduler slot length (45 min)
-- The fight itself is over within ~5 minutes of the scheduled start (Andrew's
-- rule: if you weren't there in 0:00-5:00, it's OVER) — treat that as the end
local SURGE_WINDOW = 300

-- The five surges and their fixed Coiled Isle locations (coords from Andrew).
-- 8939 = Mlurkkr Massacre is confirmed from live data; the other four
-- name<->poiID pairings are inferred from the rotation order (42,44,46,43,45
-- = 8936,8939,8937,8940,8938) and self-correct from live poi data the first
-- time each surge runs (learned name/location beats this table).
local SURGES = {
  [8939] = { name = "Mlurkkr Massacre",              x = 0.705, y = 0.327 },
  [8937] = { name = "Siege at the Whispering Marsch", x = 0.671, y = 0.775 },
  [8940] = { name = "The Malformed Leviathan",       x = 0.467, y = 0.628 },
  [8938] = { name = "The Broodmother's Nest",        x = 0.457, y = 0.296 },
  [8936] = { name = "The Looming Mutagenior",        x = 0.264, y = 0.649 },
}


-- ---------------------------------------------------------------- localization
-- All player-facing strings go through L. Built-in surge names stay English as
-- fallbacks only: the addon learns each locale's real names from live event
-- data, and the announce zone name comes localized from C_Map.GetMapInfo.
-- Translations are machine-assisted -- corrections welcome on GitHub.
local LOCALES = {
  deDE = {
    ["Only show on %s"] = "Nur auf %s anzeigen",
    ["Starts in %s"] = "Beginnt in %s",
    ["Active"] = "Aktiv",
    ["ends in %s"] = "endet in %s",
    ["Next: %s in %s"] = "Als N\195\164chstes: %s in %s",
    ["Waypoint"] = "Wegpunkt",
    ["Announce"] = "Ank\195\188ndigen",
    ["Settings"] = "Einstellungen",
    ["Audio alert when a surge starts"] = "Tonsignal, wenn ein Ereignis beginnt",
    ["Announce to"] = "Ank\195\188ndigen in",
    ["Zone chat"] = "Zonenchat",
    ["Group (party/raid/instance)"] = "Gruppe (Gruppe/Schlachtzug/Instanz)",
    ["%s is live!"] = "%s hat begonnen!",
    ["%s is active on %s%s - ends in %s!"] = "%s ist aktiv auf %s%s - endet in %s!",
    ["%s is active on %s%s!"] = "%s ist aktiv auf %s%s!",
    ["%s starts in %s on %s%s"] = "%s beginnt in %s auf %s%s",
    ["no surge to point at"] = "kein Ereignis zum Markieren",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "Die Position dieses Ereignisses ist noch unbekannt - sie wird beim ersten Auftreten gelernt",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "Wegpunkt gesetzt: %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "Auf dieser Karte kann kein Wegpunkt gesetzt werden",
    ["not in a group - announcing to zone chat instead"] = "Nicht in einer Gruppe - Ank\195\188ndigung stattdessen im Zonenchat",
    ["couldn't find the zone General channel - announcing in /say instead"] = "Allgemein-Kanal nicht gefunden - Ank\195\188ndigung stattdessen per /sagen",
    ["nothing to announce"] = "nichts anzuk\195\188ndigen",
    ["audio alert ON"] = "Tonsignal AN",
    ["audio alert OFF"] = "Tonsignal AUS",
  },
  frFR = {
    ["Only show on %s"] = "Afficher uniquement sur %s",
    ["Starts in %s"] = "Commence dans %s",
    ["Active"] = "Actif",
    ["ends in %s"] = "se termine dans %s",
    ["Next: %s in %s"] = "Suivant : %s dans %s",
    ["Waypoint"] = "Point de rep\195\168re",
    ["Announce"] = "Annoncer",
    ["Settings"] = "Param\195\168tres",
    ["Audio alert when a surge starts"] = "Alerte sonore au d\195\169but d'un \195\169v\195\169nement",
    ["Announce to"] = "Annoncer dans",
    ["Zone chat"] = "Canal de zone",
    ["Group (party/raid/instance)"] = "Groupe (groupe/raid/instance)",
    ["%s is live!"] = "%s a commenc\195\169 !",
    ["%s is active on %s%s - ends in %s!"] = "%s est actif sur %s%s - se termine dans %s !",
    ["%s is active on %s%s!"] = "%s est actif sur %s%s !",
    ["%s starts in %s on %s%s"] = "%s commence dans %s sur %s%s",
    ["no surge to point at"] = "aucun \195\169v\195\169nement \195\160 rep\195\169rer",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "La position de cet \195\169v\195\169nement est encore inconnue - elle sera apprise \195\160 sa premi\195\168re apparition",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "point de rep\195\168re plac\195\169 : %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "impossible de placer un point de rep\195\168re sur cette carte",
    ["not in a group - announcing to zone chat instead"] = "pas en groupe - annonce dans le canal de zone",
    ["couldn't find the zone General channel - announcing in /say instead"] = "canal G\195\169n\195\169ral introuvable - annonce en /dire",
    ["nothing to announce"] = "rien \195\160 annoncer",
    ["audio alert ON"] = "alerte sonore ACTIV\195\137E",
    ["audio alert OFF"] = "alerte sonore D\195\137SACTIV\195\137E",
  },
  esES = {
    ["Only show on %s"] = "Mostrar solo en %s",
    ["Starts in %s"] = "Comienza en %s",
    ["Active"] = "Activo",
    ["ends in %s"] = "termina en %s",
    ["Next: %s in %s"] = "Siguiente: %s en %s",
    ["Waypoint"] = "Punto de ruta",
    ["Announce"] = "Anunciar",
    ["Settings"] = "Ajustes",
    ["Audio alert when a surge starts"] = "Alerta de sonido cuando comience un evento",
    ["Announce to"] = "Anunciar en",
    ["Zone chat"] = "Chat de zona",
    ["Group (party/raid/instance)"] = "Grupo (grupo/banda/instancia)",
    ["%s is live!"] = "\194\161%s ha comenzado!",
    ["%s is active on %s%s - ends in %s!"] = "\194\161%s est\195\161 activo en %s%s - termina en %s!",
    ["%s is active on %s%s!"] = "\194\161%s est\195\161 activo en %s%s!",
    ["%s starts in %s on %s%s"] = "%s comienza en %s en %s%s",
    ["no surge to point at"] = "no hay ning\195\186n evento que marcar",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "La ubicaci\195\179n de este evento a\195\186n no se conoce - se aprende la primera vez que aparece",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "punto de ruta fijado: %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "no se puede fijar un punto de ruta en este mapa",
    ["not in a group - announcing to zone chat instead"] = "no est\195\161s en grupo - anunciando en el chat de zona",
    ["couldn't find the zone General channel - announcing in /say instead"] = "no se encontr\195\179 el canal General - anunciando por /decir",
    ["nothing to announce"] = "nada que anunciar",
    ["audio alert ON"] = "alerta de sonido ACTIVADA",
    ["audio alert OFF"] = "alerta de sonido DESACTIVADA",
  },
  ptBR = {
    ["Only show on %s"] = "Mostrar apenas em %s",
    ["Starts in %s"] = "Come\195\167a em %s",
    ["Active"] = "Ativo",
    ["ends in %s"] = "termina em %s",
    ["Next: %s in %s"] = "Pr\195\179ximo: %s em %s",
    ["Waypoint"] = "Ponto de rota",
    ["Announce"] = "Anunciar",
    ["Settings"] = "Configura\195\167\195\181es",
    ["Audio alert when a surge starts"] = "Alerta sonoro quando um evento come\195\167ar",
    ["Announce to"] = "Anunciar em",
    ["Zone chat"] = "Chat da zona",
    ["Group (party/raid/instance)"] = "Grupo (grupo/raide/inst\195\162ncia)",
    ["%s is live!"] = "%s come\195\167ou!",
    ["%s is active on %s%s - ends in %s!"] = "%s est\195\161 ativo em %s%s - termina em %s!",
    ["%s is active on %s%s!"] = "%s est\195\161 ativo em %s%s!",
    ["%s starts in %s on %s%s"] = "%s come\195\167a em %s em %s%s",
    ["no surge to point at"] = "nenhum evento para marcar",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "A localiza\195\167\195\163o deste evento ainda n\195\163o \195\169 conhecida - ela \195\169 aprendida na primeira vez que ele ocorre",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "ponto de rota definido: %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "n\195\163o foi poss\195\173vel definir um ponto de rota neste mapa",
    ["not in a group - announcing to zone chat instead"] = "fora de grupo - anunciando no chat da zona",
    ["couldn't find the zone General channel - announcing in /say instead"] = "canal Geral n\195\163o encontrado - anunciando em /dizer",
    ["nothing to announce"] = "nada para anunciar",
    ["audio alert ON"] = "alerta sonoro LIGADO",
    ["audio alert OFF"] = "alerta sonoro DESLIGADO",
  },
  ruRU = {
    ["Only show on %s"] = "Показывать только в зоне: %s",
    ["Starts in %s"] = "\208\157\208\176\209\135\208\189\209\145\209\130\209\129\209\143 \209\135\208\181\209\128\208\181\208\183 %s",
    ["Active"] = "\208\152\208\180\209\145\209\130",
    ["ends in %s"] = "\208\183\208\176\208\186\208\190\208\189\209\135\208\184\209\130\209\129\209\143 \209\135\208\181\209\128\208\181\208\183 %s",
    ["Next: %s in %s"] = "\208\148\208\176\208\187\208\181\208\181: %s \209\135\208\181\209\128\208\181\208\183 %s",
    ["Waypoint"] = "\208\156\208\181\209\130\208\186\208\176",
    ["Announce"] = "\208\158\208\177\209\138\209\143\208\178\208\184\209\130\209\140",
    ["Settings"] = "\208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184",
    ["Audio alert when a surge starts"] = "\208\151\208\178\209\131\208\186\208\190\208\178\208\190\208\185 \209\129\208\184\208\179\208\189\208\176\208\187 \208\191\209\128\208\184 \208\189\208\176\209\135\208\176\208\187\208\181 \209\129\208\190\208\177\209\139\209\130\208\184\209\143",
    ["Announce to"] = "\208\158\208\177\209\138\209\143\208\178\208\187\209\143\209\130\209\140 \208\178",
    ["Zone chat"] = "\208\167\208\176\209\130 \208\183\208\190\208\189\209\139",
    ["Group (party/raid/instance)"] = "\208\147\209\128\209\131\208\191\208\191\208\176 (\208\179\209\128\209\131\208\191\208\191\208\176/\209\128\208\181\208\185\208\180/\208\191\208\190\208\180\208\183\208\181\208\188\208\181\208\187\209\140\208\181)",
    ["%s is live!"] = "%s \208\189\208\176\209\135\208\176\208\187\208\190\209\129\209\140!",
    ["%s is active on %s%s - ends in %s!"] = "%s \208\184\208\180\209\145\209\130: %s%s - \208\183\208\176\208\186\208\190\208\189\209\135\208\184\209\130\209\129\209\143 \209\135\208\181\209\128\208\181\208\183 %s!",
    ["%s is active on %s%s!"] = "%s \208\184\208\180\209\145\209\130: %s%s!",
    ["%s starts in %s on %s%s"] = "%s \208\189\208\176\209\135\208\189\209\145\209\130\209\129\209\143 \209\135\208\181\209\128\208\181\208\183 %s: %s%s",
    ["no surge to point at"] = "\208\189\208\181\209\130 \209\129\208\190\208\177\209\139\209\130\208\184\209\143 \208\180\208\187\209\143 \208\188\208\181\209\130\208\186\208\184",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "\208\160\208\176\209\129\208\191\208\190\208\187\208\190\208\182\208\181\208\189\208\184\208\181 \209\141\209\130\208\190\208\179\208\190 \209\129\208\190\208\177\209\139\209\130\208\184\209\143 \208\191\208\190\208\186\208\176 \208\189\208\181\208\184\208\183\208\178\208\181\209\129\209\130\208\189\208\190 - \208\190\208\189\208\190 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\209\143\208\181\209\130\209\129\209\143 \208\191\209\128\208\184 \208\181\208\179\208\190 \208\191\208\181\209\128\208\178\208\190\208\188 \208\183\208\176\208\191\209\131\209\129\208\186\208\181",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "\208\188\208\181\209\130\208\186\208\176 \209\131\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\176: %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "\208\189\208\181\208\187\209\140\208\183\209\143 \208\191\208\190\209\129\209\130\208\176\208\178\208\184\209\130\209\140 \208\188\208\181\209\130\208\186\209\131 \208\189\208\176 \209\141\209\130\208\190\208\185 \208\186\208\176\209\128\209\130\208\181",
    ["not in a group - announcing to zone chat instead"] = "\208\178\209\139 \208\189\208\181 \208\178 \208\179\209\128\209\131\208\191\208\191\208\181 - \208\190\208\177\209\138\209\143\208\178\208\187\208\181\208\189\208\184\208\181 \208\178 \209\135\208\176\209\130 \208\183\208\190\208\189\209\139",
    ["couldn't find the zone General channel - announcing in /say instead"] = "\208\186\208\176\208\189\208\176\208\187 \194\171\208\158\208\177\209\137\208\184\208\185\194\187 \208\189\208\181 \208\189\208\176\208\185\208\180\208\181\208\189 - \208\190\208\177\209\138\209\143\208\178\208\187\208\181\208\189\208\184\208\181 \208\178 /\209\129\208\186\208\176\208\183\208\176\209\130\209\140",
    ["nothing to announce"] = "\208\189\208\181\209\135\208\181\208\179\208\190 \208\190\208\177\209\138\209\143\208\178\208\187\209\143\209\130\209\140",
    ["audio alert ON"] = "\208\183\208\178\209\131\208\186\208\190\208\178\208\190\208\185 \209\129\208\184\208\179\208\189\208\176\208\187 \208\146\208\154\208\155",
    ["audio alert OFF"] = "\208\183\208\178\209\131\208\186\208\190\208\178\208\190\208\185 \209\129\208\184\208\179\208\189\208\176\208\187 \208\146\208\171\208\154\208\155",
  },
  itIT = {
    ["Only show on %s"] = "Mostra solo su %s",
    ["Starts in %s"] = "Inizia tra %s",
    ["Active"] = "Attivo",
    ["ends in %s"] = "termina tra %s",
    ["Next: %s in %s"] = "Prossimo: %s tra %s",
    ["Waypoint"] = "Punto di rotta",
    ["Announce"] = "Annuncia",
    ["Settings"] = "Impostazioni",
    ["Audio alert when a surge starts"] = "Avviso sonoro all'inizio di un evento",
    ["Announce to"] = "Annuncia in",
    ["Zone chat"] = "Chat di zona",
    ["Group (party/raid/instance)"] = "Gruppo (gruppo/incursione/istanza)",
    ["%s is live!"] = "%s \195\168 iniziato!",
    ["%s is active on %s%s - ends in %s!"] = "%s \195\168 attivo su %s%s - termina tra %s!",
    ["%s is active on %s%s!"] = "%s \195\168 attivo su %s%s!",
    ["%s starts in %s on %s%s"] = "%s inizia tra %s su %s%s",
    ["no surge to point at"] = "nessun evento da segnare",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "La posizione di questo evento non \195\168 ancora nota - viene appresa la prima volta che si verifica",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "punto di rotta impostato: %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "impossibile impostare un punto di rotta su questa mappa",
    ["not in a group - announcing to zone chat instead"] = "non sei in un gruppo - annuncio nella chat di zona",
    ["couldn't find the zone General channel - announcing in /say instead"] = "canale Generale non trovato - annuncio in /dire",
    ["nothing to announce"] = "niente da annunciare",
    ["audio alert ON"] = "avviso sonoro ATTIVO",
    ["audio alert OFF"] = "avviso sonoro DISATTIVATO",
  },
  koKR = {
    ["Only show on %s"] = "%s에서만 표시",
    ["Starts in %s"] = "%s \237\155\132 \236\139\156\236\158\145",
    ["Active"] = "\236\167\132\237\150\137 \236\164\145",
    ["ends in %s"] = "%s \237\155\132 \236\162\133\235\163\140",
    ["Next: %s in %s"] = "\235\139\164\236\157\140: %s (%s \237\155\132)",
    ["Waypoint"] = "\236\167\128\236\160\144 \237\145\156\236\139\156",
    ["Announce"] = "\236\149\140\235\166\172\234\184\176",
    ["Settings"] = "\236\132\164\236\160\149",
    ["Audio alert when a surge starts"] = "\236\157\180\235\178\164\237\138\184 \236\139\156\236\158\145 \236\139\156 \236\134\140\235\166\172 \236\149\140\235\166\188",
    ["Announce to"] = "\236\149\140\235\166\180 \235\140\128\236\131\129",
    ["Zone chat"] = "\236\167\128\236\151\173 \236\177\132\237\140\133",
    ["Group (party/raid/instance)"] = "\237\140\140\237\139\176 (\237\140\140\237\139\176/\234\179\181\234\178\169\235\140\128/\236\157\184\236\138\164\237\132\180\236\138\164)",
    ["%s is live!"] = "%s \236\139\156\236\158\145!",
    ["%s is active on %s%s - ends in %s!"] = "%s \236\167\132\237\150\137 \236\164\145 - %s%s - %s \237\155\132 \236\162\133\235\163\140!",
    ["%s is active on %s%s!"] = "%s \236\167\132\237\150\137 \236\164\145 - %s%s!",
    ["%s starts in %s on %s%s"] = "%s - %s \237\155\132 \236\139\156\236\158\145 - %s%s",
    ["no surge to point at"] = "\237\145\156\236\139\156\237\149\160 \236\157\180\235\178\164\237\138\184\234\176\128 \236\151\134\236\138\181\235\139\136\235\139\164",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "\236\157\180 \236\157\180\235\178\164\237\138\184\236\157\152 \236\156\132\236\185\152\235\138\148 \236\149\132\236\167\129 \236\149\140 \236\136\152 \236\151\134\236\138\181\235\139\136\235\139\164 - \236\178\152\236\140\152 \235\176\156\236\131\157 \236\139\156 \236\158\144\235\143\153\236\156\188\235\161\156 \234\184\176\235\161\157\235\144\169\235\139\136\235\139\164",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "\236\167\128\236\160\144 \236\132\164\236\160\149: %s (%.1f, %.1f)%s",
    ["couldn't set a waypoint on this map"] = "\236\157\180 \236\167\128\235\143\132\236\151\144\235\138\148 \236\167\128\236\160\144\236\157\132 \236\132\164\236\160\149\237\149\160 \236\136\152 \236\151\134\236\138\181\235\139\136\235\139\164",
    ["not in a group - announcing to zone chat instead"] = "\237\140\140\237\139\176\236\151\144 \236\134\141\237\149\180 \236\158\136\236\167\128 \236\149\138\236\157\140 - \236\167\128\236\151\173 \236\177\132\237\140\133\236\156\188\235\161\156 \236\149\140\235\166\189\235\139\136\235\139\164",
    ["couldn't find the zone General channel - announcing in /say instead"] = "\236\157\188\235\176\152 \236\177\132\235\132\144\236\157\132 \236\176\190\236\157\132 \236\136\152 \236\151\134\236\138\181\235\139\136\235\139\164 - /\235\167\144\237\149\152\234\184\176\235\161\156 \236\149\140\235\166\189\235\139\136\235\139\164",
    ["nothing to announce"] = "\236\149\140\235\166\180 \235\130\180\236\154\169\236\157\180 \236\151\134\236\138\181\235\139\136\235\139\164",
    ["audio alert ON"] = "\236\134\140\235\166\172 \236\149\140\235\166\188 \236\188\156\236\167\144",
    ["audio alert OFF"] = "\236\134\140\235\166\172 \236\149\140\235\166\188 \234\186\188\236\167\144",
  },
  zhCN = {
    ["Only show on %s"] = "仅在%s显示",
    ["Starts in %s"] = "%s\229\144\142\229\188\128\229\167\139",
    ["Active"] = "\232\191\155\232\161\140\228\184\173",
    ["ends in %s"] = "%s\229\144\142\231\187\147\230\157\159",
    ["Next: %s in %s"] = "\228\184\139\228\184\128\228\184\170\239\188\154%s\239\188\136%s\229\144\142\239\188\137",
    ["Waypoint"] = "\232\183\175\229\190\132\231\130\185",
    ["Announce"] = "\233\128\154\230\138\165",
    ["Settings"] = "\232\174\190\231\189\174",
    ["Audio alert when a surge starts"] = "\228\186\139\228\187\182\229\188\128\229\167\139\230\151\182\230\146\173\230\148\190\230\143\144\231\164\186\233\159\179",
    ["Announce to"] = "\233\128\154\230\138\165\229\136\176",
    ["Zone chat"] = "\229\140\186\229\159\159\233\162\145\233\129\147",
    ["Group (party/raid/instance)"] = "\233\152\159\228\188\141\239\188\136\229\176\143\233\152\159/\229\155\162\233\152\159/\229\137\175\230\156\172\239\188\137",
    ["%s is live!"] = "%s\229\183\178\229\188\128\229\167\139\239\188\129",
    ["%s is active on %s%s - ends in %s!"] = "%s\230\173\163\229\156\168%s\232\191\155\232\161\140%s - %s\229\144\142\231\187\147\230\157\159\239\188\129",
    ["%s is active on %s%s!"] = "%s\230\173\163\229\156\168%s\232\191\155\232\161\140%s\239\188\129",
    ["%s starts in %s on %s%s"] = "%s\229\176\134\228\186\142%s\229\144\142\229\156\168%s\229\188\128\229\167\139%s",
    ["no surge to point at"] = "\230\178\161\230\156\137\229\143\175\230\160\135\232\174\176\231\154\132\228\186\139\228\187\182",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "\232\175\165\228\186\139\228\187\182\231\154\132\228\189\141\231\189\174\229\176\154\230\156\170\231\159\165\230\153\147 - \233\166\150\230\172\161\229\135\186\231\142\176\230\151\182\228\188\154\232\135\170\229\138\168\232\174\176\229\189\149",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "\229\183\178\232\174\190\231\189\174\232\183\175\229\190\132\231\130\185\239\188\154%s\239\188\136%.1f, %.1f\239\188\137%s",
    ["couldn't set a waypoint on this map"] = "\230\151\160\230\179\149\229\156\168\230\173\164\229\156\176\229\155\190\232\174\190\231\189\174\232\183\175\229\190\132\231\130\185",
    ["not in a group - announcing to zone chat instead"] = "\228\184\141\229\156\168\233\152\159\228\188\141\228\184\173 - \230\148\185\228\184\186\233\128\154\230\138\165\229\136\176\229\140\186\229\159\159\233\162\145\233\129\147",
    ["couldn't find the zone General channel - announcing in /say instead"] = "\230\156\170\230\137\190\229\136\176\231\187\188\229\144\136\233\162\145\233\129\147 - \230\148\185\231\148\168/\232\175\180\232\175\157\233\128\154\230\138\165",
    ["nothing to announce"] = "\230\178\161\230\156\137\229\143\175\233\128\154\230\138\165\231\154\132\229\134\133\229\174\185",
    ["audio alert ON"] = "\230\143\144\231\164\186\233\159\179\229\183\178\229\188\128\229\144\175",
    ["audio alert OFF"] = "\230\143\144\231\164\186\233\159\179\229\183\178\229\133\179\233\151\173",
  },
  zhTW = {
    ["Only show on %s"] = "僅在%s顯示",
    ["Starts in %s"] = "%s\229\190\140\233\150\139\229\167\139",
    ["Active"] = "\233\128\178\232\161\140\228\184\173",
    ["ends in %s"] = "%s\229\190\140\231\181\144\230\157\159",
    ["Next: %s in %s"] = "\228\184\139\228\184\128\229\128\139\239\188\154%s\239\188\136%s\229\190\140\239\188\137",
    ["Waypoint"] = "\232\183\175\229\190\145\233\187\158",
    ["Announce"] = "\233\128\154\229\160\177",
    ["Settings"] = "\232\168\173\229\174\154",
    ["Audio alert when a surge starts"] = "\228\186\139\228\187\182\233\150\139\229\167\139\230\153\130\230\146\173\230\148\190\230\143\144\231\164\186\233\159\179",
    ["Announce to"] = "\233\128\154\229\160\177\232\135\179",
    ["Zone chat"] = "\229\141\128\229\159\159\233\160\187\233\129\147",
    ["Group (party/raid/instance)"] = "\233\154\138\228\188\141\239\188\136\229\176\143\233\154\138/\229\156\152\233\154\138/\229\137\175\230\156\172\239\188\137",
    ["%s is live!"] = "%s\229\183\178\233\150\139\229\167\139\239\188\129",
    ["%s is active on %s%s - ends in %s!"] = "%s\230\173\163\229\156\168%s\233\128\178\232\161\140%s - %s\229\190\140\231\181\144\230\157\159\239\188\129",
    ["%s is active on %s%s!"] = "%s\230\173\163\229\156\168%s\233\128\178\232\161\140%s\239\188\129",
    ["%s starts in %s on %s%s"] = "%s\229\176\135\230\150\188%s\229\190\140\229\156\168%s\233\150\139\229\167\139%s",
    ["no surge to point at"] = "\230\178\146\230\156\137\229\143\175\230\168\153\232\168\152\231\154\132\228\186\139\228\187\182",
    ["this surge's location isn't known yet - it's learned the first time each surge runs"] = "\232\169\178\228\186\139\228\187\182\231\154\132\228\189\141\231\189\174\229\176\154\230\156\170\231\159\165\230\155\137 - \233\166\150\230\172\161\229\135\186\231\143\190\230\153\130\230\156\131\232\135\170\229\139\149\232\168\152\233\140\132",
    ["waypoint set: %s (%.1f, %.1f)%s"] = "\229\183\178\232\168\173\229\174\154\232\183\175\229\190\145\233\187\158\239\188\154%s\239\188\136%.1f, %.1f\239\188\137%s",
    ["couldn't set a waypoint on this map"] = "\231\132\161\230\179\149\229\156\168\230\173\164\229\156\176\229\156\150\232\168\173\229\174\154\232\183\175\229\190\145\233\187\158",
    ["not in a group - announcing to zone chat instead"] = "\228\184\141\229\156\168\233\154\138\228\188\141\228\184\173 - \230\148\185\231\130\186\233\128\154\229\160\177\232\135\179\229\141\128\229\159\159\233\160\187\233\129\147",
    ["couldn't find the zone General channel - announcing in /say instead"] = "\230\137\190\228\184\141\229\136\176\231\182\156\229\144\136\233\160\187\233\129\147 - \230\148\185\231\148\168/\232\170\170\232\169\177\233\128\154\229\160\177",
    ["nothing to announce"] = "\230\178\146\230\156\137\229\143\175\233\128\154\229\160\177\231\154\132\229\133\167\229\174\185",
    ["audio alert ON"] = "\230\143\144\231\164\186\233\159\179\229\183\178\233\150\139\229\149\159",
    ["audio alert OFF"] = "\230\143\144\231\164\186\233\159\179\229\183\178\233\151\156\233\150\137",
  },
}
LOCALES.esMX = LOCALES.esES
local L = setmetatable(LOCALES[GetLocale()] or {}, { __index = function(_, k) return k end })

local CS = CreateFrame("Frame")
local ui
local ticker
local state = {
  active = nil,   -- { areaPoiID, start, endT (may be nil), eventID }
  nextEv = nil,
}

local function chat(msg)
  print("|cff9966ffCursedSurges:|r " .. msg)
end

-- 12.1 secret strings can throw on any string op; route every format of
-- game-provided text through this
local function safefmt(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  if ok then return s end
end

local function fmtDuration(secs)
  secs = math.max(0, math.floor(tonumber(secs) or 0))
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  local s = secs % 60
  if h > 0 then
    return ("%dh %02dm"):format(h, m)
  elseif m >= 10 then
    return ("%dm"):format(m)
  else
    return ("%dm %02ds"):format(m, s)
  end
end

-- ---------------------------------------------------------------- poi lookup + learning

-- GetAreaPOIInfo needs the right map, which we only reliably know while the
-- event is active; try the scheduler's answer, the Coiled Isle, then wherever
-- the player is standing
local function poiInfoFor(poiID)
  local maps = {}
  local ok, m = pcall(C_EventScheduler.GetEventUiMapID, poiID)
  if ok and type(m) == "number" then maps[#maps + 1] = m end
  maps[#maps + 1] = COILED_ISLE
  local pm = C_Map.GetBestMapForUnit("player")
  if pm then maps[#maps + 1] = pm end
  for _, mapID in ipairs(maps) do
    local ok2, pi = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
    if ok2 and type(pi) == "table" then return pi, mapID end
  end
end

local function learn(poiID)
  if not (CursedSurgesDB and CursedSurgesDB.names) then return end
  local pi, mapID = poiInfoFor(poiID)
  if not pi then return end
  local ok, name = pcall(function() return pi.name .. "" end)
  if ok and name and name ~= "" then
    CursedSurgesDB.names[poiID] = name
  end
  local pos = pi.position
  if type(pos) == "table" then
    local x, y = tonumber(pos.x), tonumber(pos.y)
    if x and y then
      CursedSurgesDB.locs[poiID] = { mapID = mapID, x = x, y = y }
    end
  end
end

local function eventName(ev)
  if not ev then return "Cursed Surge" end
  local names = CursedSurgesDB and CursedSurgesDB.names
  local learned = names and names[ev.areaPoiID]
  if learned then return learned end
  local s = SURGES[ev.areaPoiID]
  return (s and s.name) or "Cursed Surge"
end

local function eventPosition(ev)
  if not ev then return end
  -- live info first (also refreshes the cache), then learned, then the built-in table
  learn(ev.areaPoiID)
  local loc = CursedSurgesDB and CursedSurgesDB.locs and CursedSurgesDB.locs[ev.areaPoiID]
  if loc then return loc.mapID, loc.x, loc.y end
  local s = SURGES[ev.areaPoiID]
  if s then return COILED_ISLE, s.x, s.y end
end

-- ---------------------------------------------------------------- event data

local function collectEvents()
  local now = GetServerTime()
  local active, nextEv

  -- scheduled list carries times and keeps the running event while active
  local ok, list = pcall(C_EventScheduler.GetScheduledEvents)
  if ok and type(list) == "table" then
    for _, raw in ipairs(list) do
      if type(raw) == "table" and SURGES[raw.areaPoiID] then
        local start, endT = tonumber(raw.startTime), tonumber(raw.endTime)
        if start and endT then
          -- the fight ends SURGE_WINDOW after start, not at the 45-min slot end
          local ev = { areaPoiID = raw.areaPoiID, start = start,
            endT = math.min(endT, start + SURGE_WINDOW), eventID = raw.eventID,
            key = raw.eventKey or (tostring(raw.areaPoiID) .. "@" .. tostring(start)) }
          if start <= now and now < ev.endT then
            if not active or ev.start > active.start then active = ev end
          elseif start > now then
            if not nextEv or ev.start < nextEv.start then nextEv = ev end
          end
        end
      end
    end
  end

  -- fallback: ongoing list (no times; end estimated from the POI timer if possible)
  if not active then
    local ok2, ong = pcall(C_EventScheduler.GetOngoingEvents)
    if ok2 and type(ong) == "table" then
      for _, raw in ipairs(ong) do
        if type(raw) == "table" and SURGES[raw.areaPoiID] then
          -- secondsLeft counts to the 45-min slot end; the fight window closes
          -- SURGE_BLOCK - SURGE_WINDOW earlier
          local okS, secs = pcall(C_AreaPoiInfo.GetAreaPOISecondsLeft, raw.areaPoiID)
          local endT
          if okS and tonumber(secs) then
            endT = now + tonumber(secs) - (SURGE_BLOCK - SURGE_WINDOW)
          end
          if not endT or endT > now then
            active = { areaPoiID = raw.areaPoiID, start = now, endT = endT,
              key = "ongoing:" .. tostring(raw.areaPoiID) }
          end
        end
      end
    end
  end

  state.active, state.nextEv = active, nextEv
  if active then learn(active.areaPoiID) end
end

-- zone gate: true when the player is on the Coiled Isle or one of its sub-maps
local function onCoiledIsle()
  local mapID = C_Map.GetBestMapForUnit("player")
  for _ = 1, 10 do
    if not mapID or mapID <= 0 then return false end
    if mapID == COILED_ISLE then return true end
    local mi = C_Map.GetMapInfo(mapID)
    mapID = mi and mi.parentMapID
  end
  return false
end

-- ready-check sound when a surge goes live; deduped by event key so schedule
-- refreshes can't re-fire it. The key is remembered even with sound off, so
-- enabling mid-surge doesn't retro-alert.
local lastAlertKey

local function maybeAlert()
  local a = state.active
  if not a or a.key == lastAlertKey then return end
  -- zone-only mode: stay silent out of zone WITHOUT recording the key, so
  -- entering the zone mid-surge still alerts
  if CursedSurgesDB and CursedSurgesDB.onlyInZone and not onCoiledIsle() then return end
  lastAlertKey = a.key
  if CursedSurgesDB and CursedSurgesDB.sound then
    PlaySound(SOUNDKIT.READY_CHECK, "Master")
    chat(safefmt(L["%s is live!"], eventName(a)) or (eventName(a) .. "!"))
  end
end

local function requestEvents()
  if C_EventScheduler and C_EventScheduler.RequestEvents then
    pcall(C_EventScheduler.RequestEvents)
  end
end

-- ---------------------------------------------------------------- actions

-- The event the buttons act on: the active surge if one is running, else the next one
local function targetEvent()
  return state.active or state.nextEv
end

local function setWaypoint()
  local ev = targetEvent()
  if not ev then chat(L["no surge to point at"]) return end
  local mapID, x, y = eventPosition(ev)
  if not mapID then
    chat(L["this surge's location isn't known yet - it's learned the first time each surge runs"])
    return
  end
  local name = eventName(ev)
  local pinned = false
  if C_Map.CanSetUserWaypointOnMap(mapID) then
    local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    C_Map.SetUserWaypoint(point)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    pinned = true
  end
  local tomtom = false
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = name, from = "CursedSurges" })
    tomtom = ok
  end
  if pinned or tomtom then
    chat(safefmt(L["waypoint set: %s (%.1f, %.1f)%s"], name, x * 100, y * 100,
      tomtom and " + TomTom" or "") or "OK")
  else
    chat(L["couldn't set a waypoint on this map"])
  end
end

local function zoneChannelIndex()
  -- locale-safe: the client reports the zone's server channels in its own
  -- language (General first); match that against the joined channel list,
  -- with the English name as a fallback
  local generalName = EnumerateServerChannels and (EnumerateServerChannels()) or nil
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local id, name = list[i], list[i + 1]
    local ok, hit = pcall(function()
      if generalName and name:find(generalName, 1, true) then return true end
      return name:find("General", 1, true) ~= nil
    end)
    if ok and hit then return id end
  end
end

-- clickable pin in chat — same link the game makes when you shift-click a
-- map pin into the chat box; readers click it to get the spot on their map
local function pinLink(mapID, x, y)
  return safefmt("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r",
    mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5),
    MAP_PIN_HYPERLINK or "Map Pin Location")
end

local function buildAnnounce()
  local ev = targetEvent()
  if not ev then return end
  local name = eventName(ev)
  local now = GetServerTime()
  local mapID, x, y = eventPosition(ev)
  local where = ""
  if mapID and x and y then
    local link = pinLink(mapID, x, y)
    where = safefmt(" at %.1f, %.1f %s", x * 100, y * 100, link or "") or ""
  end
  local mi = C_Map.GetMapInfo(COILED_ISLE)
  local zone = (mi and mi.name) or "The Coiled Isle"
  if state.active == ev then
    if ev.endT then
      return safefmt(L["%s is active on %s%s - ends in %s!"], name, zone, where, fmtDuration(ev.endT - now))
    end
    return safefmt(L["%s is active on %s%s!"], name, zone, where)
  else
    return safefmt(L["%s starts in %s on %s%s"], name, fmtDuration(ev.start - now), zone, where)
  end
end

-- ---------------------------------------------------------------- UI

local function openSettingsMenu(anchor)
  local ok, err = pcall(function()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
      error("MenuUtil unavailable", 0)
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle("Cursed Surges")
      root:CreateCheckbox(L["Audio alert when a surge starts"],
        function() return CursedSurgesDB.sound end,
        function() CursedSurgesDB.sound = not CursedSurgesDB.sound end)
      local mi = C_Map.GetMapInfo(COILED_ISLE)
      root:CreateCheckbox(safefmt(L["Only show on %s"], (mi and mi.name) or "the Coiled Isle")
          or "Only show on the Coiled Isle",
        function() return CursedSurgesDB.onlyInZone end,
        function() CursedSurgesDB.onlyInZone = not CursedSurgesDB.onlyInZone end)
      root:CreateTitle(L["Announce to"])
      root:CreateRadio(L["Zone chat"],
        function() return CursedSurgesDB.announceTarget ~= "group" end,
        function() CursedSurgesDB.announceTarget = "zone" end)
      root:CreateRadio(L["Group (party/raid/instance)"],
        function() return CursedSurgesDB.announceTarget == "group" end,
        function() CursedSurgesDB.announceTarget = "group" end)
    end)
  end)
  if not ok then
    chat("settings menu failed (" .. tostring(err) .. ") — use /surge sound on|off and /surge announce zone|group")
  end
end

local function ensureUI()
  if ui then return ui end
  ui = CreateFrame("Frame", "CursedSurgesWindow", UIParent, "BackdropTemplate")
  ui:SetSize(240, 108)
  ui:SetPoint("CENTER", 0, 200)
  ui:SetMovable(true)
  ui:EnableMouse(true)
  ui:RegisterForDrag("LeftButton")
  ui:SetScript("OnDragStart", function(self)
    if not CursedSurgesDB.locked then self:StartMoving() end
  end)
  ui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    CursedSurgesDB.pos = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  ui:SetClampedToScreen(true)
  ui:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  ui:SetBackdropColor(0.05, 0.02, 0.10, 0.88)

  ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ui.title:SetPoint("TOPLEFT", 10, -8)
  ui.title:SetText("|cff9966ffCursed Surges|r")

  local close = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    ui.userHidden = true -- session-only; a /reload brings it back
    ui:Hide()
  end)

  local gear = CreateFrame("Button", nil, ui)
  gear:SetSize(16, 16)
  gear:SetPoint("RIGHT", close, "LEFT", 2, 0)
  gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
  gear:SetScript("OnClick", function() openSettingsMenu(gear) end)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Settings"])
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  ui.name = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.name:SetPoint("TOPLEFT", 10, -24)
  ui.name:SetPoint("TOPRIGHT", -10, -24)
  ui.name:SetJustifyH("LEFT")
  ui.name:SetWordWrap(false)

  ui.timer = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.timer:SetPoint("TOPLEFT", 10, -40)
  ui.timer:SetPoint("TOPRIGHT", -10, -40)
  ui.timer:SetJustifyH("LEFT")

  ui.nextLine = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ui.nextLine:SetPoint("TOPLEFT", 10, -60)
  ui.nextLine:SetPoint("TOPRIGHT", -10, -60)
  ui.nextLine:SetJustifyH("LEFT")
  ui.nextLine:SetTextColor(0.7, 0.7, 0.7)

  ui.waypointBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
  ui.waypointBtn:SetSize(100, 22)
  ui.waypointBtn:SetPoint("BOTTOMLEFT", 10, 9)
  ui.waypointBtn:SetText(L["Waypoint"])
  ui.waypointBtn:SetScript("OnClick", setWaypoint)

  ui.announceBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
  ui.announceBtn:SetSize(100, 22)
  ui.announceBtn:SetPoint("BOTTOMRIGHT", -10, 9)
  ui.announceBtn:SetText(L["Announce"])
  -- SendChatMessage to a public channel needs a hardware event: it must run
  -- directly inside this OnClick, not via any timer/callback indirection
  ui.announceBtn:SetScript("OnClick", function()
    local msg = buildAnnounce()
    if not msg then chat(L["nothing to announce"]) return end
    -- "group" resolves to the chat the player is actually in; solo falls
    -- through to zone with a note
    if CursedSurgesDB.announceTarget == "group" then
      local chatType
      if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        chatType = "INSTANCE_CHAT"
      elseif IsInRaid() then
        chatType = "RAID"
      elseif IsInGroup() then
        chatType = "PARTY"
      end
      if chatType then
        SendChatMessage(msg, chatType)
        return
      end
      chat(L["not in a group - announcing to zone chat instead"])
    end
    local idx = zoneChannelIndex()
    if not idx then
      chat(L["couldn't find the zone General channel - announcing in /say instead"])
      SendChatMessage(msg, "SAY")
      return
    end
    SendChatMessage(msg, "CHANNEL", nil, idx)
  end)

  -- right-click anywhere on the panel also opens settings
  ui:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then openSettingsMenu(ui) end
  end)

  if CursedSurgesDB.pos then
    local p = CursedSurgesDB.pos
    ui:ClearAllPoints()
    ui:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
  end
  return ui
end

local function refreshUI()
  local ev = state.active or state.nextEv
  if not ev or (CursedSurgesDB.onlyInZone and not onCoiledIsle()) then
    if ui then ui:Hide() end
    return
  end
  ensureUI()
  if ui.userHidden then return end

  local now = GetServerTime()
  if state.active then
    ui.name:SetText(eventName(state.active))
    if state.active.endT then
      ui.timer:SetText("|cff33ff66" .. L["Active"] .. "|r — " .. (safefmt(L["ends in %s"], fmtDuration(state.active.endT - now)) or ""))
    else
      ui.timer:SetText("|cff33ff66" .. L["Active"] .. "|r")
    end
    if state.nextEv then
      ui.nextLine:SetText(safefmt(L["Next: %s in %s"], eventName(state.nextEv), fmtDuration(state.nextEv.start - now)) or "")
    else
      ui.nextLine:SetText("")
    end
  else
    ui.name:SetText(eventName(state.nextEv))
    ui.timer:SetText(safefmt(L["Starts in %s"], "|cffffcc00" .. fmtDuration(state.nextEv.start - now) .. "|r") or "")
    ui.nextLine:SetText("")
  end
  ui:Show()
end

-- ---------------------------------------------------------------- update loop

local lastRebuild = 0

local function rebuild()
  lastRebuild = GetTime()
  collectEvents()
  maybeAlert()
  refreshUI()
end

local function onTick()
  local now = GetServerTime()
  -- roll over when the displayed event starts or ends
  if (state.active and state.active.endT and now >= state.active.endT)
    or (state.nextEv and now >= state.nextEv.start) then
    rebuild()
    return
  end
  -- periodic re-request keeps the schedule fresh
  if GetTime() - lastRebuild > 300 then
    requestEvents()
    rebuild()
    return
  end
  refreshUI()
end

-- ---------------------------------------------------------------- debug window

local dbgWin
local function ensureDebugWindow()
  if dbgWin then return dbgWin end
  dbgWin = CreateFrame("Frame", "CursedSurgesDebugWindow", UIParent, "BackdropTemplate")
  dbgWin:SetSize(680, 460)
  dbgWin:SetPoint("CENTER")
  dbgWin:SetMovable(true)
  dbgWin:EnableMouse(true)
  dbgWin:RegisterForDrag("LeftButton")
  dbgWin:SetScript("OnDragStart", dbgWin.StartMoving)
  dbgWin:SetScript("OnDragStop", dbgWin.StopMovingOrSizing)
  dbgWin:SetFrameStrata("DIALOG")
  dbgWin:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  local title = dbgWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("CursedSurges debug — Select All, then Cmd/Ctrl+C")

  local scroll = CreateFrame("ScrollFrame", "CursedSurgesDebugScroll", dbgWin, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -38)
  scroll:SetPoint("BOTTOMRIGHT", -36, 46)

  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(620)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self) self:SetWidth(620) end)
  scroll:SetScrollChild(eb)
  dbgWin.editBox = eb

  local selectBtn = CreateFrame("Button", nil, dbgWin, "UIPanelButtonTemplate")
  selectBtn:SetSize(110, 24)
  selectBtn:SetPoint("BOTTOMLEFT", 16, 14)
  selectBtn:SetText("Select All")
  selectBtn:SetScript("OnClick", function()
    eb:SetFocus()
    eb:HighlightText()
  end)

  local closeBtn = CreateFrame("Button", nil, dbgWin, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)

  return dbgWin
end

local function dbgval(v)
  local tv = type(v)
  if tv == "string" then
    local ok, s = pcall(function() return (v:gsub("|", "||")) end)
    return ok and ("%q"):format(s) or "<secret string>"
  end
  return tostring(v)
end

-- shallow-ish dump: scalars at both levels, functions skipped (vector mixins are noisy)
local function dbgdump(t, prefix, outLines, depth)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local v = t[k]
    if type(v) == "table" and depth > 1 then
      outLines[#outLines + 1] = prefix .. tostring(k) .. " = {"
      dbgdump(v, prefix .. "    ", outLines, depth - 1)
      outLines[#outLines + 1] = prefix .. "}"
    elseif type(v) ~= "function" then
      outLines[#outLines + 1] = prefix .. tostring(k) .. " = " .. dbgval(v)
    end
  end
end

local function debugDump()
  local outLines = {}
  local function out(fmt, ...)
    outLines[#outLines + 1] = safefmt(fmt, ...) or tostring(fmt)
  end

  local now = GetServerTime()
  out("CursedSurges v%s | server time %d (%s) | player map %s",
    VERSION, now, date("%H:%M:%S"), tostring(C_Map.GetBestMapForUnit("player")))
  for _, probe in ipairs({ "HasData", "CanShowEvents", "GetActiveContinentName" }) do
    local fn = C_EventScheduler and C_EventScheduler[probe]
    if fn then
      local ok, v = pcall(fn)
      out("%s = %s", probe, ok and tostring(v) or ("ERR " .. tostring(v)))
    end
  end

  out("state: active=%s next=%s", tostring(state.active and state.active.areaPoiID),
    tostring(state.nextEv and state.nextEv.areaPoiID))
  out("learned names/locations:")
  if CursedSurgesDB then
    for poiID in pairs(SURGES) do
      local loc = CursedSurgesDB.locs and CursedSurgesDB.locs[poiID]
      out("  %d: %s | %s", poiID,
        tostring(CursedSurgesDB.names and CursedSurgesDB.names[poiID]),
        loc and safefmt("map %d %.4f,%.4f", loc.mapID, loc.x, loc.y) or "no location yet")
    end
  end

  for _, getter in ipairs({ "GetOngoingEvents", "GetScheduledEvents" }) do
    local fn = C_EventScheduler and C_EventScheduler[getter]
    local ok, list
    if fn then ok, list = pcall(fn) end
    if not ok or type(list) ~= "table" then
      out("== %s: no table (%s) ==", getter, tostring(list))
    else
      out("== %s: %d entries ==", getter, #list)
      if #list == 0 and next(list) ~= nil then
        out("(not a plain array — raw shape below)")
        dbgdump(list, "  ", outLines, 3)
      end
      for i, raw in ipairs(list) do
        if type(raw) == "table" then
          local okM, mapID = pcall(C_EventScheduler.GetEventUiMapID, raw.areaPoiID)
          local mi = okM and mapID and C_Map.GetMapInfo(mapID)
          out("-- [%d]%s map=%s (%s) start %+ds end %+ds", i,
            SURGES[raw.areaPoiID] and " [SURGE]" or "", tostring(okM and mapID or "?"),
            mi and mi.name or "?", (tonumber(raw.startTime) or 0) - now,
            (tonumber(raw.endTime) or 0) - now)
          dbgdump(raw, "    ", outLines, 3)
          if raw.areaPoiID then
            local pi, piMap = poiInfoFor(raw.areaPoiID)
            if pi then
              out("    poiInfo (via map %s):", tostring(piMap))
              dbgdump(pi, "        ", outLines, 2)
            else
              out("    poiInfo: nil (position not resolvable yet)")
            end
          end
        else
          out("-- [%d] = %s", i, dbgval(raw))
        end
      end
    end
  end

  local w = ensureDebugWindow()
  w.editBox:SetText(table.concat(outLines, "\n"))
  w:Show()
  chat("debug dump in window — Select All + Cmd/Ctrl+C")
end

-- ---------------------------------------------------------------- slash commands

SLASH_CURSEDSURGES1 = "/cursedsurges"
SLASH_CURSEDSURGES2 = "/surge"
SlashCmdList.CURSEDSURGES = function(msg)
  local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "toggle" then
    if ui and ui:IsShown() then
      ui.userHidden = true
      ui:Hide()
    else
      if ui then ui.userHidden = false end
      requestEvents()
      rebuild()
      if not (state.active or state.nextEv) then
        chat("no surge events in the scheduler right now (data may still be loading — try /surge refresh)")
      end
    end
  elseif cmd == "lock" then
    CursedSurgesDB.locked = true
    chat("window locked")
  elseif cmd == "unlock" then
    CursedSurgesDB.locked = false
    chat("window unlocked")
  elseif cmd == "reset" then
    CursedSurgesDB.pos = nil
    if ui then
      ui:ClearAllPoints()
      ui:SetPoint("CENTER", 0, 200)
    end
    chat("position reset")
  elseif cmd == "refresh" then
    requestEvents()
    rebuild()
    chat("refreshed")
  elseif cmd == "sound" then
    if rest == "on" then
      CursedSurgesDB.sound = true
    elseif rest == "off" then
      CursedSurgesDB.sound = false
    else
      CursedSurgesDB.sound = not CursedSurgesDB.sound
    end
    chat(CursedSurgesDB.sound and L["audio alert ON"] or L["audio alert OFF"])
  elseif cmd == "zoneonly" then
    if rest == "on" then
      CursedSurgesDB.onlyInZone = true
    elseif rest == "off" then
      CursedSurgesDB.onlyInZone = false
    else
      CursedSurgesDB.onlyInZone = not CursedSurgesDB.onlyInZone
    end
    chat("zone-only " .. (CursedSurgesDB.onlyInZone
      and "ON (hidden and silent outside the Coiled Isle)" or "OFF"))
  elseif cmd == "announce" then
    if rest == "zone" or rest == "group" then
      CursedSurgesDB.announceTarget = rest
    end
    chat("announce target: " .. (CursedSurgesDB.announceTarget == "group"
      and "group (party/raid/instance, zone when solo)" or "zone chat")
      .. "  (/surge announce zone|group)")
  elseif cmd == "debug" then
    debugDump()
  else
    chat("commands: /surge (toggle), lock, unlock, reset, refresh, sound on|off, zoneonly on|off, announce zone|group, debug — or the gear icon")
  end
end

-- ---------------------------------------------------------------- init

CS:RegisterEvent("ADDON_LOADED")
CS:RegisterEvent("PLAYER_ENTERING_WORLD")
CS:RegisterEvent("EVENT_SCHEDULER_UPDATE")
CS:RegisterEvent("ZONE_CHANGED_NEW_AREA")
CS:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    CursedSurgesDB = CursedSurgesDB or {}
    CursedSurgesDB.names = CursedSurgesDB.names or {}
    CursedSurgesDB.locs = CursedSurgesDB.locs or {}
    if CursedSurgesDB.sound == nil then CursedSurgesDB.sound = true end
    CursedSurgesDB.announceTarget = CursedSurgesDB.announceTarget or "zone"
  elseif event == "PLAYER_ENTERING_WORLD" then
    requestEvents()
    rebuild()
    if not ticker then
      ticker = C_Timer.NewTicker(1, onTick)
    end
  elseif event == "EVENT_SCHEDULER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
    rebuild()
  end
end)
