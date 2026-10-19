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
	["age", "Plan for power plant replacement", "Power plants can reach the end of their service life. Keep funds available for replacement.", "Inspect plant information and the city's existing notices. Replacing a plant must also restore its network connections.", "power"],
	["water", "Water supply", "Use the water view to distinguish a supply problem from a disconnected part of the network.", "A pipe alone is not enough: it must connect to a working water supply. Then check whether that supply is sufficient.", "water"],
	["pumps", "Pump output can vary", "Location and weather matter to water supply. Inspect actual output before adding more pumps.", "Use the water view to distinguish a supply problem from a disconnected part of the network.", "water"],
	["waterworks", "Water facilities have different jobs", "Pumps, towers, desalination and treatment are not interchangeable.", "Read the selected facility's information. Storage or treatment alone is not a substitute for a connected water source.", "water"],
	["access", "Access is more than a nearby road", "A nearby transport route and a reachable destination are different requirements.", "Use the query tool to inspect access. A positive local check does not promise that every simulated journey succeeds.", "traffic"],
	["networks", "Connect your transport networks", "Separate rail, subway and highway sections need suitable connections to work together.", "Check junctions and stations rather than assuming that two nearby networks are connected.", "traffic"],
	["traffic", "Traffic also has a cost", "Watch traffic patterns and transport maintenance as the city expands.", "Use the traffic map and budget together before choosing where to add or improve routes.", "traffic"],
	["value", "Land value can limit density", "Residential and commercial buildings can need a higher local land value for their next density level.", "The threshold depends on the building's current density. This rule does not apply identically to industry or a zone already at its density limit.", "land"],
	["environment", "Inspect local conditions", "City averages can hide local pollution or crime problems.", "Compare the relevant maps around the affected site before deciding which service or connection to improve.", "pollution"],
	["services", "A building is not the whole service", "Service buildings, their funding and their local effect are separate questions.", "Inspect coverage and the budget before adding another service building.", "budget"],
	["education", "Watch long-term trends", "Education and health should be assessed over time, not just immediately after construction.", "Use the population reports and graphs to compare longer-term changes.", "graphs"],
	["budget", "Cash is not the annual balance", "Check running costs and the annual forecast before large projects. A healthy bank balance can temporarily hide a deficit.", "The budget separates income and expenses. Include the ongoing cost of new facilities in your plans.", "budget"],
	["bonds", "Borrowing has ongoing costs", "A bond provides cash now and creates debt and interest obligations.", "Check existing debt and the budget before borrowing again. Keep repayment in your longer-term plan.", "budget"],
	["ordinances", "Review ordinance costs", "Ordinances can change the city's finances and conditions.", "Read each ordinance's description and check its budget effect instead of enabling every option.", "ordinances"],
	["limits", "Growth has several constraints", "Recreation, outside connections and city development can matter alongside demand.", "Inspect the relevant reports before expanding. Population growth, appearance and quality of life are different valid goals.", "graphs"],
	["unlock", "New opportunities", "Inventions and rewards can make new tools or buildings available.", "Check the updated menus and the city's notice before planning around a new option.", ""],
	["recovery", "Check the city after an event", "After a disaster, inspect damaged connections and services. In a scenario, also review its actual objectives.", "Restore essential connections before expanding. Scenario goals and deadlines belong to the loaded scenario, not a universal checklist.", "scenario"],
]


static func entry(id: String) -> Array:
	for value: Array in ENTRIES:
		if value[0] == id:
			return value
	return []
