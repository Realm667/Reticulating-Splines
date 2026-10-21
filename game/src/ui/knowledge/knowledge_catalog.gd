class_name KnowledgeCatalog
extends RefCounted
## Original editorial summaries. Rule provenance: docs/tips-and-knowledge.md.

# Stable ID, title, short text, explanation, optional view/action.
const ENTRIES := [
	["start", "Start small. Grow with purpose.", "Plan small residential, commercial and industrial areas with power and transport access. Keep an eye on running costs.", "Use demand to decide what to expand next. Give new areas time to develop before zoning more land.", "demand"],
	["demand", "Demand shows a direction", "Follow residential, commercial and industrial demand instead of a fixed ratio of zones.", "Positive demand does not guarantee growth at every location. Check the site's power, access and land value too.", "growth"],
	["vacant", "Check your existing zones", "Before zoning more land, inspect areas that are still empty.", "More zoning does not repair a missing connection. The query tool helps you inspect a specific site.", "growth"],
	["density", "Density sets a limit", "Light and dense zones allow different building sizes. Dense zoning alone does not guarantee tall buildings.", "Further development also depends on the site and the growth rules for its zone type.", "growth"],
	["time", "Development takes time", "The simulation visits different parts of the city in stages. A new connection may not produce an immediate change.", "Let the relevant simulation phases finish before judging a repair. Pausing the city also pauses development.", "growth"],
	["power", "Power supply", "Check both generation and connections in the power view. Spare capacity does not help an isolated area.", "A high usage percentage alone does not prove a citywide outage. Inspect the affected connections before building another plant.", "power"],
	["plants", "Choose an available power source", "The power menu shows which plant types are currently available.", "Compare construction cost, capacity and the needs of your city before committing your funds.", "power"],
	["age", "Plan for power plant replacement", "Most large power plants age. Set aside replacement funds and check their age before supply fails. Hydro and wind do not use this regular replacement cycle.", "", "power"],
	["water", "Water supply", "Use the water view to distinguish a supply problem from a disconnected part of the network.", "A pipe alone is not enough: it must connect to a working water supply. Then check whether that supply is sufficient.", "water"],
	["pumps", "Fresh water helps pumps", "Powered pumps produce more beside fresh water. Salt water gives ordinary pumps no bonus. Check actual output before adding more pumps.", "", "water"],
	["waterworks", "Water facilities have different jobs", "Pumps, towers, desalination and treatment are not interchangeable.", "Read the selected facility's information. Storage or treatment alone is not a substitute for a connected water source.", "water"],
	["access", "Access is more than a nearby road", "A nearby transport route and a reachable destination are different requirements.", "Use the query tool to inspect access. A positive local check does not promise that every simulated journey succeeds.", "traffic"],
	["networks", "Connect your transport networks", "Separate rail, subway and highway sections need suitable connections to work together.", "Check junctions and stations rather than assuming that two nearby networks are connected.", "traffic"],
	["traffic", "Maintain your transport network", "Cutting transport funding can let routes decay. Check maintenance before expanding the network: a broken connection can affect several districts.", "", "traffic"],
	["value", "Water can support denser buildings", "Water supply can raise land value and help residential or commercial buildings reach a higher density. Power, routes and demand still matter; water does not guarantee growth.", "", "land"],
	["environment", "Inspect local conditions", "City averages can hide local pollution or crime problems.", "Compare the relevant maps around the affected site before deciding which service or connection to improve.", "pollution"],
	["services", "A building is not the whole service", "Service buildings, their funding and their local effect are separate questions.", "Inspect coverage and the budget before adding another service building.", "budget"],
	["education", "Watch long-term trends", "Education and health should be assessed over time, not just immediately after construction.", "Use the population reports and graphs to compare longer-term changes.", "graphs"],
	["budget", "Cash is not the annual balance", "Check running costs and the annual forecast before large projects. A healthy bank balance can temporarily hide a deficit.", "The budget separates income and expenses. Include the ongoing cost of new facilities in your plans.", "budget"],
	["bonds", "Borrowing has ongoing costs", "A bond provides cash now and creates debt and interest obligations.", "Check existing debt and the budget before borrowing again. Keep repayment in your longer-term plan.", "budget"],
	["ordinances", "Review ordinance costs", "Ordinances can change the city's finances and conditions.", "Read each ordinance's description and check its budget effect instead of enabling every option.", "ordinances"],
	["limits", "Growth has several constraints", "Recreation, outside connections and city development can matter alongside demand.", "Inspect the relevant reports before expanding. Population growth, appearance and quality of life are different valid goals.", "graphs"],
	["unlock", "New opportunities", "Inventions and rewards can make new tools or buildings available.", "Check the updated menus and the city's notice before planning around a new option.", ""],
	["recovery", "Check the city after a disaster", "Inspect damaged roads, power lines and pipes. Restore essential connections before expanding. The event button takes you to a known affected location.", "", "event"],
	["industry", "Industry needs a destination", "Industry needs a transport connection to a residential or commercial zone to develop. A nearby road with no reachable destination is not enough.", "", "growth"],
	["scenario", "Review scenario objectives", "Scenario goals and deadlines depend on the loaded scenario. Review unfinished objectives before time runs out.", "", "scenario"],
	["coal", "Coal: cheap power, heavy pollution", "Coal offers inexpensive generating capacity, but produces substantial pollution. Leave space between the plant and sensitive residential areas.", "", "power"],
	["gas", "Gas: low purchase cost, low output", "A gas plant costs less to build than other large fuel plants, but supplies much less power. Compare capacity as well as purchase price.", "", "power"],
	["oil", "Oil: weigh cost against pollution", "Oil produces less pollution than coal, but costs more to build for a modest increase in output. Check whether that trade-off suits your budget.", "", "power"],
	["hydro", "Hydro needs a waterfall", "Hydro plants need waterfall terrain. Each provides limited power without the regular aging cycle of large plants; check the site's suitability and connections.", "", "power"],
	["wind", "Wind needs a reserve", "Wind output depends on elevation and wind. Higher sites can help, but output varies. Keep spare generating capacity for weaker conditions.", "", "power"],
	["solar", "Solar output follows the weather", "Solar generation varies with weather. Do not plan the network around its best output; keep capacity in reserve for worse conditions.", "", "power"],
	["nuclear", "Nuclear: output and risk", "Nuclear plants supply substantial power with little routine pollution, but have a high purchase cost. A meltdown is possible when disasters are enabled.", "", "power"],
	["microwave", "Microwave: powerful but costly", "Microwave plants provide high output at a high initial cost. With disasters enabled, a beam accident is possible. Keep replacement funds available.", "", "power"],
	["fusion", "Fusion needs capital", "Fusion offers very high output and little pollution, but ties up a large amount of money. Buy it when your city can afford the cost and use the capacity.", "", "power"],
	["desalination", "Desalination needs salt water", "Desalination needs power and adjacent salt water. An inland site or fresh-water shore will not provide the required salt-water intake.", "", "water"],
	["towers", "Towers store water", "Water towers store surplus water and release it during shortages. They do not create water: connect them to a network with a working source.", "", "water"],
	["reserve", "Keep a water reserve", "Pump output changes with rainfall and water conditions. A system that barely meets demand can fail during dry weather. Check output and stored reserves.", "", "water"],
	["police", "Police need funding and power", "Police coverage depends on funding and power as well as station placement. Check the coverage map before paying for another station.", "", "budget"],
	["fire", "Fire stations need support", "Fire protection depends on station placement, power and funding. Restore a weak existing service before building more stations in the same area.", "", "budget"],
	["prison", "Prisons support police", "Prisons can support police effectiveness, but do not replace local police coverage. They also add pollution; choose their location carefully.", "", "budget"],
	["schools", "Schools work over time", "Schools need adequate funding to serve pupils. Education changes gradually as residents age; judge the trend instead of expecting an instant jump.", "", "graphs"],
	["college", "College complements school", "Colleges serve a different age group from schools. Fund both stages as needed; a college does not replace primary schooling.", "", "graphs"],
	["hospital", "Hospitals need sustained funding", "Hospital capacity depends on funding. Health improves over time, so inspect capacity and the long-term trend before adding another hospital.", "", "graphs"],
	["recreation", "Recreation can lift a growth limit", "Large parks, zoos, stadiums and marinas can expand the city's residential growth allowance. Build for an actual need; they do not repair missing power or routes.", "", "growth"],
	["stadium", "A stadium needs space and money", "A stadium can support residential growth, but occupies a large site, costs money and adds some pollution. Compare it with smaller leisure investments.", "", "growth"],
	["taxes", "Taxes influence demand", "Higher taxes can reduce demand. If zones remain empty, compare tax rates and the budget before lowering taxes; lost income must still cover services.", "", "budget"],
	["abandoned", "Abandoned buildings can recover", "Do not demolish every abandoned building immediately. Check power, reachable destinations and demand, then allow development time after repairing the cause.", "", "growth"],
	["outside", "Outside connections support growth", "Neighbor roads and developed airports can lift commercial limits; seaports and suitable rail or highway connections can help industry. Empty port zoning alone is not enough.", "", "growth"],
	["road_distance", "Keep zones close to roads", "Along a straight road, plan no more than three rows of zones; roads on both sides can serve six rows. Distance counts horizontal and vertical grid steps together. A route to a suitable destination is still needed.", "", "traffic"],
]


static func entry(id: String) -> Array:
	for value: Array in ENTRIES:
		if value[0] == id:
			return value
	return []


static func for_tool(group: int, subtool: int) -> String:
	match group:
		CityToolIds.Group.POWER:
			return {CityToolIds.Power.COAL: "coal", CityToolIds.Power.HYDRO: "hydro",
				CityToolIds.Power.OIL: "oil", CityToolIds.Power.GAS: "gas", CityToolIds.Power.NUCLEAR: "nuclear",
				CityToolIds.Power.WIND: "wind", CityToolIds.Power.SOLAR: "solar",
				CityToolIds.Power.MICROWAVE: "microwave", CityToolIds.Power.FUSION: "fusion"}.get(subtool, "")
		CityToolIds.Group.WATER:
			return {CityToolIds.Water.PUMP: "pumps", CityToolIds.Water.TOWER: "towers",
				CityToolIds.Water.DESALINIZATION: "desalination", CityToolIds.Water.TREATMENT: "waterworks"}.get(subtool, "")
		CityToolIds.Group.SERVICES:
			return {CityToolIds.Services.POLICE_STATION: "police", CityToolIds.Services.FIRE_STATION: "fire",
				CityToolIds.Services.HOSPITAL: "hospital", CityToolIds.Services.PRISON: "prison"}.get(subtool, "")
		CityToolIds.Group.EDUCATION:
			return {CityToolIds.Education.SCHOOL: "schools", CityToolIds.Education.COLLEGE: "college"}.get(subtool, "education")
		CityToolIds.Group.RECREATION:
			return "stadium" if subtool == CityToolIds.Recreation.STADIUM else "recreation"
		CityToolIds.Group.PORTS:
			return "outside"
		CityToolIds.Group.INDUSTRIAL:
			return "industry"
		CityToolIds.Group.ROADS:
			return "road_distance" if subtool == CityToolIds.Roads.ROAD else "networks"
	return ""
